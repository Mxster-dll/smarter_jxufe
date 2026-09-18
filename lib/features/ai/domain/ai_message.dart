/// AI 对话的消息模型（纯领域，无网络 / Flutter 依赖）。
///
/// 两套序列化口径**不要混用**：
/// - [AiChatMessage.toWire] → 发给 OpenAI 兼容端点的 `messages` 数组
///   （字段名必须是 `role` / `content` / `tool_calls` / `tool_call_id`）；
/// - [AiChatMessage.toJson] / [AiChatMessage.fromJson] → 本地历史持久化
///   （多存 `id` / `createdAt`，且允许带 UI 用的失败标记）。
library;

import 'dart:convert';

import 'ai_config.dart';

/// 消息角色。`tool` 是「工具执行结果」这一轮（必须带 [AiChatMessage.toolCallId]）。
enum AiRole {
  system,
  user,
  assistant,
  tool;

  /// 线上字段值 —— 恰好等于枚举名，但**显式写出来**，避免以后改枚举名悄悄改变协议。
  String get wire => switch (this) {
    AiRole.system => 'system',
    AiRole.user => 'user',
    AiRole.assistant => 'assistant',
    AiRole.tool => 'tool',
  };

  /// 容错解析（认不出 → [AiRole.user]）。
  static AiRole parse(Object? raw) {
    final v = aiStrOf(raw).trim().toLowerCase();
    for (final r in AiRole.values) {
      if (r.wire == v) return r;
    }
    return AiRole.user;
  }
}

/// 模型请求的一次函数调用。
///
/// [arguments] **保持原始 JSON 字符串**（不在这里 parse）—— 流式响应里参数是
/// 逐片拼出来的，只有拼完才是合法 JSON；提前 parse 会在半截处炸掉。
class AiToolCall {
  final String id;
  final String name;
  final String arguments;

  const AiToolCall({required this.id, required this.name, this.arguments = ''});

  /// 解析后的参数；不是合法 JSON / 不是对象 → 空 Map（调用方据此报「参数没给全」）。
  Map<String, dynamic> get args {
    final raw = arguments.trim();
    if (raw.isEmpty) return const {};
    try {
      final decoded = decodeAiJsonLoose(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 交给调用方按「参数解析失败」处理，不在这里抛
    }
    return const {};
  }

  /// 发给端点的形态。
  Map<String, dynamic> toWire() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': arguments},
  };

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'arguments': arguments};

  static AiToolCall? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = aiStrOf(raw['name']).trim();
    if (name.isEmpty) return null;
    return AiToolCall(
      id: aiStrOf(raw['id']),
      name: name,
      arguments: aiStrOf(raw['arguments']),
    );
  }

  @override
  String toString() => 'AiToolCall($name, ${arguments.length}B)';
}

/// 一条对话消息。
class AiChatMessage {
  final String id;
  final AiRole role;
  final String content;

  /// 仅 assistant 用：模型这一轮要求调用的工具。
  final List<AiToolCall> toolCalls;

  /// 仅 tool 用：回应的是哪一次调用（必须与 [AiToolCall.id] 对上，否则端点报错）。
  final String? toolCallId;

  /// 仅 tool 用：工具名（部分端点（如 Kimi）要求带上，缺了会 400）。
  final String? toolName;

  final DateTime createdAt;

  /// 本地标记：这条是报错信息（发给端点时会被过滤掉，见 [toWire]）。
  final bool isError;

  const AiChatMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    required this.createdAt,
    this.isError = false,
  });

  bool get isTool => role == AiRole.tool;

  /// 线上形态。
  ///
  /// ⚠ 三条容易踩的坑：
  /// 1. `assistant` 带 tool_calls 时 `content` **必须是 null 而不是空串** ——
  ///    部分端点（DeepSeek / 智谱）对空串会报「content 不能为空」；
  /// 2. `tool` 消息必须带 `tool_call_id`；
  /// 3. 本地造的报错消息（[isError]）不入线上数组 —— 它只是给用户看的。
  Map<String, dynamic> toWire() {
    final map = <String, dynamic>{'role': role.wire};
    if (role == AiRole.assistant && toolCalls.isNotEmpty) {
      map['content'] = content.isEmpty ? null : content;
      map['tool_calls'] = [for (final c in toolCalls) c.toWire()];
    } else {
      map['content'] = content;
    }
    if (role == AiRole.tool) {
      map['tool_call_id'] = toolCallId ?? '';
      if (toolName != null && toolName!.isNotEmpty) map['name'] = toolName;
    }
    return map;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.wire,
    'content': content,
    if (toolCalls.isNotEmpty) 'toolCalls': [for (final c in toolCalls) c.toJson()],
    if (toolCallId != null) 'toolCallId': toolCallId,
    if (toolName != null) 'toolName': toolName,
    'createdAt': createdAt.toIso8601String(),
    if (isError) 'isError': true,
  };

  /// 容错解析（坏条目交给调用方丢弃）。
  factory AiChatMessage.fromJson(Map<String, dynamic> json) {
    final calls = <AiToolCall>[];
    final rawCalls = json['toolCalls'];
    if (rawCalls is List) {
      for (final item in rawCalls) {
        final call = AiToolCall.fromJson(item);
        if (call != null) calls.add(call);
      }
    }
    final createdRaw = aiStrOf(json['createdAt']);
    return AiChatMessage(
      id: aiStrOf(json['id'], 'm'),
      role: AiRole.parse(json['role']),
      content: aiStrOf(json['content']),
      toolCalls: calls,
      toolCallId: json['toolCallId'] == null ? null : aiStrOf(json['toolCallId']),
      toolName: json['toolName'] == null ? null : aiStrOf(json['toolName']),
      createdAt: DateTime.tryParse(createdRaw) ?? DateTime.fromMillisecondsSinceEpoch(0),
      isError: aiBoolOf(json['isError'], false),
    );
  }

  AiChatMessage copyWith({
    String? content,
    List<AiToolCall>? toolCalls,
    bool? isError,
  }) => AiChatMessage(
    id: id,
    role: role,
    content: content ?? this.content,
    toolCalls: toolCalls ?? this.toolCalls,
    toolCallId: toolCallId,
    toolName: toolName,
    createdAt: createdAt,
    isError: isError ?? this.isError,
  );

  /// 过滤出真正能发给端点的消息（去掉本地报错条目）。
  static List<AiChatMessage> wireFiltered(List<AiChatMessage> messages) => [
    for (final m in messages)
      if (!m.isError) m,
  ];

  @override
  String toString() => 'AiChatMessage(${role.wire}, ${content.length}字)';
}

/// token 用量（端点不返回时全为 0）。
class AiUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const AiUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  static const AiUsage none = AiUsage();

  bool get isEmpty => promptTokens == 0 && completionTokens == 0 && totalTokens == 0;

  static AiUsage fromJson(Object? raw) {
    if (raw is! Map) return none;
    return AiUsage(
      promptTokens: aiIntOf(raw['prompt_tokens'], 0),
      completionTokens: aiIntOf(raw['completion_tokens'], 0),
      totalTokens: aiIntOf(raw['total_tokens'], 0),
    );
  }

  @override
  String toString() => 'AiUsage($promptTokens+$completionTokens=$totalTokens)';
}

/// 宽容地解析一段 JSON 文本。
///
/// 模型偶尔会把参数块包在 ```json 围栏里或多带一句解释（尤其是被降级成
/// 「文本里塞 JSON」的端点）—— 这里先剥一层围栏再解析。
/// 解析失败会抛 `FormatException`，由调用方按「参数解析失败」处理。
Object? decodeAiJsonLoose(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final firstLineEnd = text.indexOf('\n');
    if (firstLineEnd > 0) text = text.substring(firstLineEnd + 1);
    final fenceEnd = text.lastIndexOf('```');
    if (fenceEnd >= 0) text = text.substring(0, fenceEnd);
    text = text.trim();
  }
  return jsonDecode(text);
}
