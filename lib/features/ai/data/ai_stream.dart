/// OpenAI 兼容端点的**协议细节**：SSE 分帧、增量累积、错误文案、请求体构造。
///
/// 全部是纯函数 / 纯类，**不碰 Dio** —— 联网在 `ai_client.dart`，这样协议的
/// 每一条分支都能用单测钉住（流式的坑基本都在这里，而不在网络上）。
library;

import 'dart:convert';

import '../domain/ai_config.dart';
import '../domain/ai_message.dart';

/// 流式响应里的一片工具调用参数。
///
/// 关键事实：OpenAI 兼容端点把 `arguments` **逐字切片**发过来
/// （`{"loc` + `ation":` + `"南` …），并且 `id` / `name` 只在**第一片**出现。
/// 所以必须按 `index` 累积，不能每片当独立调用。
class AiToolCallDelta {
  final int index;
  final String? id;
  final String? name;
  final String? arguments;

  const AiToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.arguments,
  });
}

/// 流式响应的一帧（非流式响应解析成**唯一一帧**）。
class AiStreamChunk {
  final String? content;
  final String? reasoning;
  final List<AiToolCallDelta> toolCalls;
  final String? finishReason;
  final AiUsage? usage;

  const AiStreamChunk({
    this.content,
    this.reasoning,
    this.toolCalls = const [],
    this.finishReason,
    this.usage,
  });

  bool get isEmpty =>
      (content == null || content!.isEmpty) &&
      (reasoning == null || reasoning!.isEmpty) &&
      toolCalls.isEmpty &&
      finishReason == null &&
      usage == null;
}

/// 累积流式分片 → 最终的一次 assistant 回复。
class AiStreamAccumulator {
  final StringBuffer _content = StringBuffer();
  final StringBuffer _reasoning = StringBuffer();
  final Map<int, _ToolCallBuilder> _calls = {};
  AiUsage _usage = AiUsage.none;
  String? _finishReason;

  String get content => _content.toString();

  /// 思维链（DeepSeek reasoner / Qwen-thinking 等；普通模型恒为空）。
  String get reasoning => _reasoning.toString();

  AiUsage get usage => _usage;

  String? get finishReason => _finishReason;

  /// 累积到的工具调用（按 index 升序，保证与模型发出顺序一致）。
  List<AiToolCall> get toolCalls {
    final keys = _calls.keys.toList()..sort();
    return [for (final k in keys) _calls[k]!.build()];
  }

  bool get hasToolCalls => _calls.isNotEmpty;

  void apply(AiStreamChunk chunk) {
    final text = chunk.content;
    if (text != null && text.isNotEmpty) _content.write(text);
    final think = chunk.reasoning;
    if (think != null && think.isNotEmpty) _reasoning.write(think);
    if (chunk.usage != null && !chunk.usage!.isEmpty) _usage = chunk.usage!;
    if (chunk.finishReason != null) _finishReason = chunk.finishReason;
    for (final d in chunk.toolCalls) {
      final builder = _calls.putIfAbsent(d.index, () => _ToolCallBuilder(d.index));
      builder.apply(d);
    }
  }

  /// 收尾成一条 assistant 消息。
  ///
  /// [id] / [now] 由调用方给 —— 领域层不引 uuid 包，也方便测试固定时间。
  AiChatMessage toMessage({required String id, required DateTime now}) =>
      AiChatMessage(
        id: id,
        role: AiRole.assistant,
        content: content,
        toolCalls: toolCalls,
        createdAt: now,
      );

  void clear() {
    _content.clear();
    _reasoning.clear();
    _calls.clear();
    _usage = AiUsage.none;
    _finishReason = null;
  }
}

class _ToolCallBuilder {
  final int index;
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();

  _ToolCallBuilder(this.index);

  void apply(AiToolCallDelta d) {
    if (d.id != null && d.id!.isNotEmpty) id = d.id;
    if (d.name != null && d.name!.isNotEmpty) name = d.name;
    final a = d.arguments;
    if (a != null && a.isNotEmpty) arguments.write(a);
  }

  AiToolCall build() => AiToolCall(
    // 没有 id 时兜一个稳定值：端点不接受空 tool_call_id，
    // 而「模型没给 id」在降级 / 非标准端点上确实会遇到。
    id: (id == null || id!.isEmpty) ? 'call_$index' : id!,
    name: name ?? '',
    arguments: arguments.toString(),
  );
}

/// SSE 分帧器：喂行，吐「已完成事件」的数据体。
///
/// 只做分帧，不做 JSON 解析 —— 这样 `data:` 里是不是合法 JSON 与分帧正确性
/// 可以分开测。`event:` / `id:` / `: 注释` 一律忽略（OpenAI 兼容端点用不到）。
class AiSseFramer {
  final StringBuffer _data = StringBuffer();

  /// 喂一行（**不含换行符**）。返回本次凑齐的事件数据（通常 0 或 1 条）。
  List<String> feedLine(String line) {
    final trimmedRight = line.endsWith('\r')
        ? line.substring(0, line.length - 1)
        : line;
    if (trimmedRight.isEmpty) {
      // 空行 = 事件结束
      if (_data.isEmpty) return const [];
      final payload = _data.toString();
      _data.clear();
      return [payload];
    }
    if (trimmedRight.startsWith(':')) return const [];
    if (!trimmedRight.startsWith('data:')) return const [];
    var value = trimmedRight.substring(5);
    if (value.startsWith(' ')) value = value.substring(1);
    // 同一事件多条 data: 行按 SSE 规范用 \n 连接
    if (_data.isNotEmpty) _data.write('\n');
    _data.write(value);
    return const [];
  }

  /// 流意外结束时把残留的数据体交出去（有的端点在 `[DONE]` 前不补空行）。
  List<String> flush() {
    if (_data.isEmpty) return const [];
    final payload = _data.toString();
    _data.clear();
    return [payload];
  }
}

/// 解析一条 SSE 数据体。
///
/// 返回 null 表示「这一帧不该产生消息」（`[DONE]` 或空体）。
AiStreamChunk? parseAiStreamData(String data) {
  final text = data.trim();
  if (text.isEmpty) return null;
  if (text == '[DONE]') return null;
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    // 少数端点会插心跳/纯文本帧，直接忽略
    return null;
  }
  if (decoded is! Map) return null;
  return parseAiChunkJson(Map<String, dynamic>.from(decoded));
}

/// 解析一帧的 JSON（流式与非流式共用：非流式 = `choices[0].message`，
/// 流式 = `choices[0].delta`）。
AiStreamChunk parseAiChunkJson(Map<String, dynamic> json) {
  final usage = json['usage'] == null ? null : AiUsage.fromJson(json['usage']);
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) {
    // 只有 usage 的收尾帧（stream_options.include_usage 的行为）
    return AiStreamChunk(usage: usage);
  }
  final first = choices.first;
  if (first is! Map) return AiStreamChunk(usage: usage);
  final choice = Map<String, dynamic>.from(first);
  // 流式 delta / 非流式 message 都取到（哪个在就取哪个）
  final container = choice['delta'] is Map
      ? Map<String, dynamic>.from(choice['delta'] as Map)
      : (choice['message'] is Map
            ? Map<String, dynamic>.from(choice['message'] as Map)
            : const <String, dynamic>{});

  final content = _textOf(container['content']);
  // DeepSeek 用 reasoning_content，部分端点用 reasoning
  final reasoning =
      _textOf(container['reasoning_content']) ?? _textOf(container['reasoning']);

  final calls = <AiToolCallDelta>[];
  final rawCalls = container['tool_calls'];
  if (rawCalls is List) {
    for (var i = 0; i < rawCalls.length; i++) {
      final item = rawCalls[i];
      if (item is! Map) continue;
      final call = Map<String, dynamic>.from(item);
      final fn = call['function'] is Map
          ? Map<String, dynamic>.from(call['function'] as Map)
          : const <String, dynamic>{};
      calls.add(
        AiToolCallDelta(
          index: aiIntOf(call['index'], i),
          id: call['id'] == null ? null : aiStrOf(call['id']),
          name: fn['name'] == null ? null : aiStrOf(fn['name']),
          arguments: fn['arguments'] == null ? null : aiStrOf(fn['arguments']),
        ),
      );
    }
  }

  return AiStreamChunk(
    content: content,
    reasoning: reasoning,
    toolCalls: calls,
    finishReason: choice['finish_reason'] == null
        ? null
        : aiStrOf(choice['finish_reason']),
    usage: usage,
  );
}

/// `content` 可能是字符串，也可能是多模态数组（`[{type:'text',text:…}]`）。
String? _textOf(Object? raw) {
  if (raw == null) return null;
  if (raw is String) return raw;
  if (raw is List) {
    final buffer = StringBuffer();
    for (final part in raw) {
      if (part is Map && part['text'] != null) buffer.write(aiStrOf(part['text']));
    }
    final text = buffer.toString();
    return text.isEmpty ? null : text;
  }
  return null;
}

/// 构造请求体。
///
/// 几条实测口径：
/// - `stream_options.include_usage` **默认带上**（能拿到 token 用量）；收到
///   「不认这个字段」的 400 时由 [aiIsStreamOptionsRejected] 识别并自动重发；
/// - `tools` 为空数组时**整条不发** —— 有的端点（Kimi 旧版）对空数组直接 400；
/// - 温度只在需要时发（`temperature: 0` 是合法值，不能用 `if (t > 0)` 判空）。
Map<String, dynamic> buildAiRequestBody({
  required AiConfig config,
  required List<AiChatMessage> messages,
  List<Map<String, dynamic>> toolWires = const [],
  bool? streamOverride,
  bool includeStreamOptions = true,
}) {
  final stream = streamOverride ?? config.stream;
  final body = <String, dynamic>{
    'model': config.model,
    'messages': [for (final m in AiChatMessage.wireFiltered(messages)) m.toWire()],
    'temperature': config.temperature,
    'stream': stream,
  };
  if (stream && includeStreamOptions) {
    body['stream_options'] = {'include_usage': true};
  }
  if (toolWires.isNotEmpty) {
    body['tools'] = toolWires;
    body['tool_choice'] = 'auto';
  }
  return body;
}

/// 从错误响应体里抠出人能看懂的中文说明。
///
/// 端点错误形态千奇百怪（OpenAI 的 `{error:{message}}`、网关的 HTML、
/// 纯文本），一律兜住，并把常见状态码翻译成人话。
String aiExtractError(Object? body, int statusCode) {
  final detail = _errorDetail(body);
  final hint = switch (statusCode) {
    401 => 'API Key 无效或已过期',
    402 => '账户余额不足',
    403 => '无权访问该模型（检查 Key 的权限或模型名）',
    404 => '接口地址不对（多数端点需要带 /v1，或模型名不存在）',
    408 => '请求超时',
    413 => '请求体过大（对话历史太长，试试开新对话）',
    429 => '触发限流或额度用尽，稍后再试',
    >= 500 => '服务端错误（$statusCode），稍后再试',
    _ => statusCode == 0 ? '网络不可达' : '请求失败（HTTP $statusCode）',
  };
  if (detail.isEmpty) return hint;
  return '$hint：$detail';
}

String _errorDetail(Object? body) {
  Object? decoded = body;
  if (body is String) {
    final text = body.trim();
    if (text.isEmpty) return '';
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      // 非 JSON（HTML 错误页 / 纯文本）：截断后用原文
      return text.length > 200 ? '${text.substring(0, 200)}…' : text;
    }
  }
  if (decoded is Map) {
    final map = Map<String, dynamic>.from(decoded);
    final err = map['error'];
    if (err is Map) {
      final m = Map<String, dynamic>.from(err);
      final msg = aiStrOf(m['message']).trim();
      if (msg.isNotEmpty) return msg;
      final code = aiStrOf(m['code']).trim();
      if (code.isNotEmpty) return code;
    }
    if (err is String && err.trim().isNotEmpty) return err.trim();
    for (final key in const ['message', 'msg', 'error_msg', 'detail']) {
      final v = aiStrOf(map[key]).trim();
      if (v.isNotEmpty) return v;
    }
  }
  final text = decoded?.toString() ?? '';
  return text.length > 200 ? '${text.substring(0, 200)}…' : text;
}

/// 端点是否因为「不认识 stream_options」而拒绝。
///
/// 命中后调用方**重发一次不带该字段的请求** —— 这样既拿到了多数端点的用量，
/// 又不会在老端点上整个功能不可用。
bool aiIsStreamOptionsRejected(String statusMessage) {
  final s = statusMessage.toLowerCase();
  if (!s.contains('stream_options') && !s.contains('stream options')) return false;
  return s.contains('unknown') ||
      s.contains('unrecognized') ||
      s.contains('unsupported') ||
      s.contains('not support') ||
      s.contains('invalid') ||
      s.contains('extra');
}

/// 端点是否「不支持函数调用」。
///
/// 判定故意保守（**必须同时**提到 tools/function 与一个否定/非法词），
/// 否则一句普通 400（如「context length exceeded」）会被误判成不支持工具、
/// 让整个对话悄悄降级到「预取数据」模式。
bool aiLooksLikeToolsUnsupported(String statusMessage) {
  final s = statusMessage.toLowerCase();
  final mentions = s.contains('tool') || s.contains('function');
  if (!mentions) return false;
  final negative =
      s.contains('not support') ||
      s.contains('unsupported') ||
      s.contains('does not support') ||
      s.contains("doesn't support") ||
      s.contains('not supported') ||
      s.contains('unknown') ||
      s.contains('unrecognized') ||
      s.contains('invalid') ||
      s.contains('no such');
  return negative;
}

/// 端点是否「不支持流式」。
bool aiLooksLikeStreamUnsupported(String statusMessage) {
  final s = statusMessage.toLowerCase();
  if (!s.contains('stream')) return false;
  return s.contains('not support') ||
      s.contains('unsupported') ||
      s.contains('not supported') ||
      s.contains('invalid');
}
