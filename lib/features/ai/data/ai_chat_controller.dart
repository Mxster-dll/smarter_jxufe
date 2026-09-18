/// AI 对话编排层：把「一次提问」变成「用户消息 → 若干轮工具调用 → 最终回答」。
///
/// 这一层**不碰网络细节**（那是 [AiClient]），也**不做界面**。它负责：
/// 1. 维护对话历史（含 assistant 的 tool_calls 与 tool 结果，顺序必须严格配对）；
/// 2. 跑工具循环，并把最多 [AiSettings.maxToolRounds] 轮的上限当闸门
///    （模型偶尔会反复查同一个工具，没有闸门就一直烧 token）；
/// 3. 三条自动降级：端点不认 `stream_options` → 重发；不支持流式 → 转非流式；
///    不支持函数调用 → 转「预取数据塞提示词」（用户拍板的降级口径）；
/// 4. 把工具调用轨迹暴露给界面（用户能看到「它查了什么」）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/features/ai/data/ai_client.dart';
import 'package:smarter_jxufe/features/ai/data/ai_chat_store.dart';
import 'package:smarter_jxufe/features/ai/data/ai_providers.dart';
import 'package:smarter_jxufe/features/ai/data/ai_settings_store.dart';
import 'package:smarter_jxufe/features/ai/data/ai_snapshot.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_config.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_message.dart';
import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/ai/tools/tool_registry.dart';
import 'package:smarter_jxufe/core/network/current_account_provider.dart';

/// 一次工具调用的轨迹（界面据此显示「正在查询…」与折叠的明细）。
class AiToolTrace {
  final String name;

  /// 给用户看的中文说明（工具自己不知道中文名，这里按名字映射）。
  final String label;
  final Map<String, dynamic> args;
  final bool ok;
  final bool running;
  final String preview;

  /// 工具给界面的结构化数据（如 `{'kind':'navigate','title':'成绩'}`）。
  final Map<String, dynamic>? ui;

  const AiToolTrace({
    required this.name,
    required this.label,
    this.args = const {},
    this.ok = true,
    this.running = false,
    this.preview = '',
    this.ui,
  });

  AiToolTrace copyWith({bool? ok, bool? running, String? preview}) => AiToolTrace(
    name: name,
    label: label,
    args: args,
    ok: ok ?? this.ok,
    running: running ?? this.running,
    preview: preview ?? this.preview,
    ui: ui,
  );
}

/// 工具名 → 给用户看的中文动作说明。
const Map<String, String> kAiToolLabels = {
  'search_rules': '检索规章制度',
  'read_rule': '查规章原文',
  'get_my_schedule': '查我的课表',
  'find_free_time': '算无课时间',
  'query_timetable': '查课表',
  'get_grades': '查成绩',
  'get_score_estimate': '查分数估计',
  'get_deadlines': '查截止日期',
  'get_curriculum': '查培养方案',
  'get_graduation_credits': '查毕业学分',
  'get_volunteer_hours': '查志愿时长',
  'get_zongce': '查综测',
  'list_materials': '查材料库',
  'get_school_calendar': '查校历',
  'get_energy': '查电费网费',
  'get_student_info': '查学籍信息',
  'get_app_settings': '读设置',
  'update_app_setting': '修改设置',
  'open_page': '准备页面入口',
};

String aiToolLabel(String name) => kAiToolLabels[name] ?? name;

/// 对话控制器。
class AiChatController extends ChangeNotifier {
  final Ref _ref;
  final DateTime Function() clock;

  AiChatController(this._ref, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  final List<AiChatMessage> _messages = [];
  final List<AiToolTrace> _traces = [];

  bool _busy = false;
  bool _cancelRequested = false;
  bool _disposed = false;
  String _streamText = '';
  String _streamReasoning = '';
  String? _error;
  AiUsage _lastUsage = AiUsage.none;

  /// 会话级降级标记（不写回配置 —— 用户下次仍然按自己的设置来）。
  bool _toolsDisabled = false;
  bool _streamDisabled = false;

  /// 写操作确认回调；界面在 initState 里挂上。没挂 = 一律拒绝（安全默认值）。
  Future<bool> Function(AiWriteRequest request)? onConfirmWrite;

  List<AiChatMessage> get messages => List.unmodifiable(_messages);
  List<AiToolTrace> get traces => List.unmodifiable(_traces);
  bool get busy => _busy;
  String get streamText => _streamText;
  String get streamReasoning => _streamReasoning;
  String? get error => _error;
  AiUsage get lastUsage => _lastUsage;
  bool get toolsDisabled => _toolsDisabled;

  /// 是否还没有任何消息（首次进入引导页用）。
  bool get isEmpty => _messages.isEmpty && !_busy;

  /// 载入历史（界面 initState 调用；失败静默）。
  Future<void> restore() async {
    try {
      final account = _ref.read(currentAccountProvider);
      final saved = await loadAiChat(account);
      if (saved.isEmpty || _disposed) return;
      _messages
        ..clear()
        ..addAll(saved);
      _safeNotify();
    } catch (_) {
      // 历史读不出来不影响使用
    }
  }

  /// 清空对话。
  Future<void> clear() async {
    _messages.clear();
    _traces.clear();
    _streamText = '';
    _streamReasoning = '';
    _error = null;
    _lastUsage = AiUsage.none;
    _safeNotify();
    try {
      await saveAiChat(_ref.read(currentAccountProvider), const []);
    } catch (_) {
      // 落盘失败不影响本次会话
    }
  }

  /// 停止当前生成。
  void cancel() {
    if (!_busy) return;
    _cancelRequested = true;
  }

  /// 关掉错误条。
  void clearError() {
    if (_error == null) return;
    _error = null;
    _safeNotify();
  }

  /// 发一条用户消息并跑到「最终回答」为止。
  Future<void> send(String text) async {
    final input = text.trim();
    if (input.isEmpty || _busy) return;

    final config = _ref.read(aiSettingsStoreProvider).settings.active;
    if (config == null || !config.ready) {
      _error = '还没有配置可用的 AI 接口。请到「设置 → AI 助手」填写供应商、模型与 API Key。';
      _safeNotify();
      return;
    }

    _error = null;
    _traces.clear();
    _cancelRequested = false;
    _busy = true;
    _messages.add(
      AiChatMessage(
        id: const Uuid().v4(),
        role: AiRole.user,
        content: input,
        createdAt: clock(),
      ),
    );
    _safeNotify();

    try {
      await _runLoop(config);
    } catch (e) {
      _error = '对话出错：$e';
    } finally {
      _busy = false;
      _streamText = '';
      _streamReasoning = '';
      _safeNotify();
      unawaited(_persist());
    }
  }

  /// 工具循环本体。
  Future<void> _runLoop(AiConfig config) async {
    final settings = _ref.read(aiSettingsStoreProvider).settings;
    final maxRounds = settings.maxToolRounds;
    final client = _ref.read(aiClientProvider);

    // 降级时预取的「已知数据」只算一次（它要跑好几个工具，不便宜）
    String dataPack = '';

    for (var round = 0; round <= maxRounds; round++) {
      if (_cancelRequested) {
        _appendNotice('（已停止）');
        return;
      }
      // 是否处于降级态（用户关掉了 tools，或端点明确拒绝过 tools）
      final degraded = !config.useTools || _toolsDisabled;
      if (degraded && dataPack.isEmpty) {
        dataPack = await buildAiDataPack(_toolContext());
        dataPack = dataPack.isEmpty ? '（没有取到任何本地数据）' : dataPack;
      }
      // 最后一轮不再给工具：逼模型用已经查到的东西作答，而不是继续查
      final useTools = !degraded && round < maxRounds;

      final snapshot = config.includeSnapshot
          ? await buildAiSnapshot(_ref, now: clock())
          : '';
      final system = AiChatMessage(
        id: 'system',
        role: AiRole.system,
        content: aiSystemPrompt(
          snapshot: snapshot,
          dataPack: dataPack,
          toolsEnabled: useTools,
          extra: config.extraSystemPrompt,
        ),
        createdAt: clock(),
      );

      final toolSpecs = useTools
          ? [for (final t in availableAiTools(_toolContext())) t.spec]
          : const <AiToolSpec>[];
      final completion = await _streamOnce(
        client: client,
        config: config,
        system: system,
        tools: toolSpecs,
      );
      if (completion == null) return; // 已经置了 _error
      if (_cancelRequested) {
        _appendNotice('（已停止）');
        return;
      }

      _lastUsage = completion.usage;

      if (!completion.hasToolCalls) {
        _messages.add(
          AiChatMessage(
            id: const Uuid().v4(),
            role: AiRole.assistant,
            content: completion.content.trim().isEmpty
                ? '（模型没有返回内容）'
                : completion.content,
            createdAt: clock(),
          ),
        );
        _safeNotify();
        return;
      }

      // 有工具调用：先落 assistant 消息（content 可能是空串，配 toolCalls 一起发回）
      _messages.add(
        AiChatMessage(
          id: const Uuid().v4(),
          role: AiRole.assistant,
          content: completion.content,
          toolCalls: completion.toolCalls,
          createdAt: clock(),
        ),
      );
      _streamText = '';
      _streamReasoning = '';
      _safeNotify();

      await _runToolCalls(completion.toolCalls);

      if (round == maxRounds) {
        _appendNotice('（已达工具调用轮次上限，先给你目前查到的结果）');
        return;
      }
    }
  }

  /// 跑一轮工具调用，把结果作为 `tool` 消息接回对话。
  Future<void> _runToolCalls(List<AiToolCall> calls) async {
    final ctx = _toolContext();
    for (final call in calls) {
      final label = aiToolLabel(call.name);
      final index = _traces.length;
      _traces.add(
        AiToolTrace(
          name: call.name,
          label: label,
          args: call.args,
          running: true,
        ),
      );
      _safeNotify();

      AiToolResult result;
      final tool = aiToolByName(call.name);
      if (tool == null) {
        result = AiToolResult.fail(
          '不存在名为 ${call.name} 的工具。可用工具：${kAllAiTools.map((t) => t.spec.name).join('、')}',
        );
      } else {
        try {
          result = await tool.run(ctx, call.args);
        } catch (e) {
          result = AiToolResult.fail('工具执行异常：$e');
        }
      }

      _traces[index] = AiToolTrace(
        name: call.name,
        label: label,
        args: call.args,
        running: false,
        ok: result.ok,
        preview: _preview(result.content),
        ui: result.ui,
      );
      _messages.add(
        AiChatMessage(
          id: const Uuid().v4(),
          role: AiRole.tool,
          content: result.content,
          toolCallId: call.id,
          toolName: call.name,
          createdAt: clock(),
        ),
      );
      _safeNotify();
      if (_cancelRequested) return;
    }
  }

  /// 发一次请求并消费事件流。
  ///
  /// 返回 null 表示这一轮失败（[_error] 已置好）；三条降级都在这里就地重试。
  Future<AiCompletion?> _streamOnce({
    required AiClient client,
    required AiConfig config,
    required AiChatMessage system,
    required List<AiToolSpec> tools,
  }) async {
    var includeStreamOptions = true;
    var stream = config.stream && !_streamDisabled;
    var droppedTools = false;

    for (var attempt = 0; attempt < 4; attempt++) {
      _streamText = '';
      _streamReasoning = '';
      _safeNotify();

      AiCompletion? done;
      AiErrorEvent? failure;
      final history = _trimHistory(system);

      await for (final event in client.chat(
        config: config,
        messages: history,
        tools: droppedTools ? const <AiToolSpec>[] : tools,
        stream: stream,
        includeStreamOptions: includeStreamOptions,
      )) {
        switch (event) {
          case AiTextEvent(:final text):
            _streamText += text;
            _safeNotify();
          case AiReasoningEvent(:final text):
            _streamReasoning += text;
            _safeNotify();
          case AiDoneEvent(:final completion):
            done = completion;
          case AiErrorEvent():
            failure = event;
        }
        if (_cancelRequested) break;
      }

      if (done != null) return done;
      if (_cancelRequested) return null;
      if (failure == null) {
        _error = '请求中断了，请重试。';
        _safeNotify();
        return null;
      }

      // ── 三条自动降级（每次只降一档，最多重试 4 次）──
      if (failure.streamOptionsRejected && includeStreamOptions) {
        includeStreamOptions = false;
        continue;
      }
      if (failure.streamUnsupported && stream) {
        stream = false;
        _streamDisabled = true;
        continue;
      }
      if (failure.toolsUnsupported && !droppedTools) {
        droppedTools = true;
        _toolsDisabled = true;
        _safeNotify();
        continue;
      }
      _error = failure.message;
      _safeNotify();
      return null;
    }
    _error = '多次重试仍未成功，请检查配置或稍后再试。';
    _safeNotify();
    return null;
  }

  /// 裁剪历史：保留最近的若干条，但**绝不拆散 tool_calls 与它的 tool 结果**
  /// （拆散会让端点直接 400）。
  List<AiChatMessage> _trimHistory(AiChatMessage system) {
    const maxTail = 40;
    final wire = AiChatMessage.wireFiltered(_messages);
    if (wire.length <= maxTail) return [system, ...wire];

    var start = wire.length - maxTail;
    // 往前退到一条 user 消息（对话轮次的自然边界）
    while (start > 0 && wire[start].role != AiRole.user) {
      start--;
    }
    // 再退到「不属于任何未闭合 tool 结果」的位置
    while (start > 0 && wire[start].role == AiRole.tool) {
      start--;
    }
    return [system, ...wire.sublist(start)];
  }

  AiToolContext _toolContext() => AiToolContext(
    ref: _ref,
    gate: _GateAdapter(onConfirmWrite),
    now: clock(),
  );

  void _appendNotice(String text) {
    _messages.add(
      AiChatMessage(
        id: const Uuid().v4(),
        role: AiRole.assistant,
        content: text,
        createdAt: clock(),
        isError: true, // 本地提示，不发给端点
      ),
    );
    _safeNotify();
  }

  Future<void> _persist() async {
    try {
      final account = _ref.read(currentAccountProvider);
      await saveAiChat(account, _messages);
    } catch (_) {
      // 落盘失败不影响本次会话
    }
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 把可空的确认回调包成 [AiWriteGate]（没挂回调 = 拒绝）。
class _GateAdapter implements AiWriteGate {
  final Future<bool> Function(AiWriteRequest request)? _confirm;

  const _GateAdapter(this._confirm);

  @override
  Future<bool> confirm(AiWriteRequest request) async {
    final fn = _confirm;
    if (fn == null) return false;
    try {
      return await fn(request);
    } catch (_) {
      return false;
    }
  }
}

String _preview(String content) {
  final one = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  return one.length <= 120 ? one : '${one.substring(0, 120)}…';
}

/// 对话控制器（**非 autoDispose**：对话页与悬浮球共用同一份历史）。
final aiChatControllerProvider = ChangeNotifierProvider<AiChatController>((ref) {
  final controller = AiChatController(ref);
  unawaited(controller.restore());
  return controller;
});
