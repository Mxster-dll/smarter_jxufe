/// OpenAI 兼容端点客户端（唯一联网出口）。
///
/// 只做一件事：把「一次 chat/completions 请求」变成一条事件流。
/// 工具循环、历史管理、降级策略都在编排层，**不在**这里 —— 这样换端点
/// （或者以后接别家协议）只需换这一个文件。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../domain/ai_config.dart';
import '../domain/ai_message.dart';
import '../tools/ai_tool.dart';
import 'ai_stream.dart';

/// 一次完整回复（流结束 / 非流式响应解析后的结果）。
class AiCompletion {
  final String content;

  /// 思维链（reasoner 类模型才有）。
  final String reasoning;
  final List<AiToolCall> toolCalls;
  final AiUsage usage;
  final String? finishReason;

  const AiCompletion({
    this.content = '',
    this.reasoning = '',
    this.toolCalls = const [],
    this.usage = AiUsage.none,
    this.finishReason,
  });

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// 对话事件。
sealed class AiChatEvent {
  const AiChatEvent();
}

/// 增量的正文（打字机效果）。
class AiTextEvent extends AiChatEvent {
  final String text;
  const AiTextEvent(this.text);
}

/// 增量的思维链（界面单列一块灰色区域，不混进正文）。
class AiReasoningEvent extends AiChatEvent {
  final String text;
  const AiReasoningEvent(this.text);
}

/// 一轮结束。
class AiDoneEvent extends AiChatEvent {
  final AiCompletion completion;
  const AiDoneEvent(this.completion);
}

/// 一轮失败。
class AiErrorEvent extends AiChatEvent {
  final String message;
  final int statusCode;

  /// 端点明确拒绝 `tools` → 编排层降级成「预取数据塞提示词」。
  final bool toolsUnsupported;

  /// 端点拒绝 `stream_options` → 重发一次不带它的请求即可，不算失败。
  final bool streamOptionsRejected;

  /// 端点拒绝流式 → 改用非流式重发。
  final bool streamUnsupported;

  const AiErrorEvent(
    this.message, {
    this.statusCode = 0,
    this.toolsUnsupported = false,
    this.streamOptionsRejected = false,
    this.streamUnsupported = false,
  });
}

class AiClient {
  final Dio dio;

  AiClient(this.dio);

  /// 发起一次请求。
  ///
  /// [stream] 显式覆盖配置里的开关（降级重试时用）。
  Stream<AiChatEvent> chat({
    required AiConfig config,
    required List<AiChatMessage> messages,
    List<AiToolSpec> tools = const [],
    bool? stream,
    bool includeStreamOptions = true,
  }) async* {
    final url = config.chatCompletionsUrl;
    if (url.isEmpty) {
      yield const AiErrorEvent('接口地址为空，请到「设置 → AI 助手」填写。');
      return;
    }
    final body = buildAiRequestBody(
      config: config,
      messages: messages,
      toolWires: [for (final t in tools) t.toWire()],
      streamOverride: stream,
      includeStreamOptions: includeStreamOptions,
    );
    final useStream = stream ?? config.stream;

    Response<ResponseBody> response;
    try {
      response = await dio.post<ResponseBody>(
        url,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Authorization': 'Bearer ${config.apiKey.trim()}',
            'Content-Type': 'application/json',
            'Accept': useStream ? 'text/event-stream' : 'application/json',
          },
          // 自己处理非 2xx：要把响应体读出来才能给出「Key 无效 / 模型名不对」
          // 这类可操作提示，交给 Dio 抛 DioException 会把 body 吞掉。
          validateStatus: (_) => true,
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(seconds: 60),
        ),
      );
    } on DioException catch (e) {
      yield AiErrorEvent(_dioMessage(e));
      return;
    } catch (e) {
      yield AiErrorEvent('请求失败：$e');
      return;
    }

    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      final raw = await _readAll(response.data);
      final message = aiExtractError(raw, status);
      yield AiErrorEvent(
        message,
        statusCode: status,
        toolsUnsupported: tools.isNotEmpty && aiLooksLikeToolsUnsupported(message),
        streamOptionsRejected: useStream && aiIsStreamOptionsRejected(message),
        streamUnsupported: useStream && aiLooksLikeStreamUnsupported(message),
      );
      return;
    }

    final body$ = response.data;
    if (body$ == null) {
      yield const AiErrorEvent('服务端返回了空响应。');
      return;
    }

    if (!useStream) {
      yield* _consumeWhole(body$);
      return;
    }
    yield* _consumeStream(body$);
  }

  /// 非流式：整段读完再解析（也用于「端点不支持流式」的降级重试）。
  Stream<AiChatEvent> _consumeWhole(ResponseBody body) async* {
    final raw = await _readAll(body);
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      yield AiErrorEvent('响应不是合法 JSON：${_clip(raw)}');
      return;
    }
    if (decoded is! Map) {
      yield AiErrorEvent('响应格式不对：${_clip(raw)}');
      return;
    }
    final json = Map<String, dynamic>.from(decoded);
    final err = _inlineError(json);
    if (err != null) {
      yield AiErrorEvent(err);
      return;
    }
    final chunk = parseAiChunkJson(json);
    final accumulator = AiStreamAccumulator()..apply(chunk);
    if (accumulator.content.isNotEmpty) yield AiTextEvent(accumulator.content);
    if (accumulator.reasoning.isNotEmpty) {
      yield AiReasoningEvent(accumulator.reasoning);
    }
    yield AiDoneEvent(
      AiCompletion(
        content: accumulator.content,
        reasoning: accumulator.reasoning,
        toolCalls: accumulator.toolCalls,
        usage: accumulator.usage,
        finishReason: accumulator.finishReason,
      ),
    );
  }

  /// 流式：SSE 逐帧。
  ///
  /// `utf8.decoder` + `LineSplitter` 是**流式转换器**，会自己缓冲跨 chunk 的
  /// 半个多字节字符与半行 —— 中文正文在这里最容易被切坏，必须用它们而不是
  /// 手工 split。
  Stream<AiChatEvent> _consumeStream(ResponseBody body) async* {
    final framer = AiSseFramer();
    final accumulator = AiStreamAccumulator();

    final lines = utf8.decoder.bind(body.stream).transform(const LineSplitter());

    await for (final line in lines) {
      for (final payload in framer.feedLine(line)) {
        final trimmed = payload.trim();
        if (trimmed == '[DONE]') continue;
        final inline = _streamInlineError(trimmed);
        if (inline != null) {
          yield AiErrorEvent(inline);
          return;
        }
        final chunk = parseAiStreamData(payload);
        if (chunk == null || chunk.isEmpty) continue;
        accumulator.apply(chunk);
        if (chunk.content != null && chunk.content!.isNotEmpty) {
          yield AiTextEvent(chunk.content!);
        }
        if (chunk.reasoning != null && chunk.reasoning!.isNotEmpty) {
          yield AiReasoningEvent(chunk.reasoning!);
        }
      }
    }
    // 有的端点在 [DONE] 前不补空行，残留的数据体在这里收尾
    for (final payload in framer.flush()) {
      final chunk = parseAiStreamData(payload);
      if (chunk == null || chunk.isEmpty) continue;
      accumulator.apply(chunk);
      if (chunk.content != null && chunk.content!.isNotEmpty) {
        yield AiTextEvent(chunk.content!);
      }
    }

    yield AiDoneEvent(
      AiCompletion(
        content: accumulator.content,
        reasoning: accumulator.reasoning,
        toolCalls: accumulator.toolCalls,
        usage: accumulator.usage,
        finishReason: accumulator.finishReason,
      ),
    );
  }

  /// 「测试连接」：拉一次模型列表。
  ///
  /// 刻意**不**发一次真实对话 —— 那要花钱、还慢；`/models` 401/200 足以
  /// 区分「Key 不对」与「通了」。
  Future<AiConnectionTest> testConnection(AiConfig config) async {
    final url = config.modelsUrl;
    if (url.isEmpty) return const AiConnectionTest(false, '接口地址为空');
    if (config.apiKey.trim().isEmpty) return const AiConnectionTest(false, 'API Key 为空');
    try {
      final response = await dio.get<dynamic>(
        url,
        options: Options(
          headers: {'Authorization': 'Bearer ${config.apiKey.trim()}'},
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        final models = _modelIds(response.data);
        if (models.isEmpty) {
          return const AiConnectionTest(true, '连接成功（该端点未返回模型列表）');
        }
        return AiConnectionTest(
          true,
          '连接成功，可用模型 ${models.length} 个：${_clip(models.take(6).join('、'))}'
              '${models.length > 6 ? ' 等' : ''}',
          models: models,
        );
      }
      return AiConnectionTest(false, aiExtractError(response.data, status));
    } on DioException catch (e) {
      return AiConnectionTest(false, _dioMessage(e));
    } catch (e) {
      return AiConnectionTest(false, '连接失败：$e');
    }
  }

  List<String> _modelIds(Object? data) {
    Object? decoded = data;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! Map) return const [];
    final list = decoded['data'];
    if (list is! List) return const [];
    final ids = <String>[];
    for (final item in list) {
      if (item is Map && item['id'] != null) {
        final id = aiStrOf(item['id']).trim();
        if (id.isNotEmpty) ids.add(id);
      } else if (item is String && item.trim().isNotEmpty) {
        ids.add(item.trim());
      }
    }
    return ids;
  }

  Future<String> _readAll(ResponseBody? body) async {
    if (body == null) return '';
    final bytes = <int>[];
    await for (final chunk in body.stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 流里夹的错误帧（HTTP 200 但内容报错，网关超时常见）。
  String? _streamInlineError(String payload) {
    if (!payload.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return _inlineError(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _inlineError(Map<String, dynamic> json) {
    if (json['error'] == null) return null;
    // 有的端点把 error 字段当业务提示用（不是失败）；只有内容非空才算错
    final detail = _errorDetailOf(json);
    return detail.isEmpty ? null : detail;
  }

  String _errorDetailOf(Map<String, dynamic> json) {
    final err = json['error'];
    if (err is Map) {
      final msg = aiStrOf(err['message']).trim();
      if (msg.isNotEmpty) return msg;
      final code = aiStrOf(err['code']).trim();
      if (code.isNotEmpty) return code;
      return '未知错误';
    }
    if (err is String) return err.trim();
    return '';
  }

  String _dioMessage(DioException e) {
    final type = e.type;
    return switch (type) {
      DioExceptionType.connectionTimeout => '连接超时：检查网络，或确认接口地址可达。',
      DioExceptionType.sendTimeout => '发送超时：网络太慢。',
      DioExceptionType.receiveTimeout => '等待响应超时：模型长时间没有返回。',
      DioExceptionType.connectionError =>
        '连不上服务器：${e.message ?? '请检查接口地址与网络'}',
      DioExceptionType.cancel => '请求已取消。',
      DioExceptionType.badCertificate => '证书校验失败。',
      _ => '请求失败：${e.message ?? e.type.name}',
    };
  }
}

/// 「测试连接」结果。
class AiConnectionTest {
  final bool ok;
  final String message;
  final List<String> models;

  const AiConnectionTest(this.ok, this.message, {this.models = const []});
}

String _clip(String text, [int max = 200]) =>
    text.length <= max ? text : '${text.substring(0, max)}…';
