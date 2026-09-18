/// 对话历史的持久化（Hive `aiChat` 单 key JSON，**按账号隔离**）。
///
/// 为什么要按账号隔离：对话里会带出成绩、课表、学籍这些个人数据，
/// 换账号后绝不能看到上一个账号的聊天记录。
///
/// 存的是**本地消息形态**（`AiChatMessage.toJson`），不是线上形态 ——
/// 线上形态有 `content: null` 这类只为发请求而存在的细节，不适合落盘。
///
/// ⚠ 本 box **不得**加入云同步载荷白名单（`lib/features/library_sync/data/libsp_payload.dart`）：
/// 聊天记录里含个人成绩与课表，不该外传。
library;

import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ai/domain/ai_message.dart';

/// 存储 box 名。
const aiChatBoxName = 'aiChat';

/// 最多保留多少条（超出丢最早的）—— 聊天记录会无限长，必须设闸。
const int aiChatMaxMessages = 60;

String _keyFor(String account) => 'chat|${account.isEmpty ? 'none' : account}';

/// 读取某账号的对话历史（任何失败 → 空列表，绝不抛）。
Future<List<AiChatMessage>> loadAiChat(String account) async {
  try {
    final box = await Hive.openBox<String>(aiChatBoxName);
    final raw = box.get(_keyFor(account));
    return decodeAiChat(raw);
  } catch (_) {
    return const [];
  }
}

/// 写入某账号的对话历史（只保留最后 [aiChatMaxMessages] 条）。
Future<void> saveAiChat(String account, List<AiChatMessage> messages) async {
  try {
    final box = await Hive.openBox<String>(aiChatBoxName);
    if (messages.isEmpty) {
      await box.delete(_keyFor(account));
      return;
    }
    final keep = messages.length <= aiChatMaxMessages
        ? messages
        : messages.sublist(messages.length - aiChatMaxMessages);
    final raw = jsonEncode([for (final m in keep) m.toJson()]);
    await box.put(_keyFor(account), raw);
  } catch (_) {
    // 落盘失败不影响本次会话
  }
}

/// 容错解析（坏条目逐条丢弃；整表坏 → 空列表）。
List<AiChatMessage> decodeAiChat(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <AiChatMessage>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      try {
        final msg = AiChatMessage.fromJson(Map<String, dynamic>.from(item));
        // system 提示词不落盘（它每次都重新拼），别的保留
        if (msg.role == AiRole.system) continue;
        out.add(msg);
      } catch (_) {
        // 单条坏 → 跳过
      }
    }
    return out;
  } catch (_) {
    return const [];
  }
}
