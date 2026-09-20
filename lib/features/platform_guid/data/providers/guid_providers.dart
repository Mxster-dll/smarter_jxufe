/// 智慧江财「平台标识」（GUID）的**唯一**存储与读取口径。
///
/// GUID 仅微信授权「智慧江财」可得（等同账号标识），由设置页「平台标识」向导写入
/// Hive box `wxPlatform` 的 key `guid`；未配置时依赖它的功能退回离线快照 / 门户兜底源。
///
/// ⚠ **为什么住在 platform_guid 而不是使用方**（2026-09-20 · 架构审查 ⑦）：
/// 它被 **7 个 feature** 使用（校历 / 校园网 / 请假 / 我的邮箱 / 成绩单 / 设置 / 本向导）。
/// 从前定义在 `features/school_calendar/data/providers/wxcal_providers.dart`，而
/// `features/net_fee` 又复制了一份 —— 两份 provider 读同一个 box、**彼此不联动**：
/// 保存 GUID 后必须挨个手工 `invalidate` 别家 provider，也就把 platform_guid 与
/// leave / net_fee / school_calendar 咬成了三条依赖环。归一之后
/// **只要 `ref.invalidate(platformGuidProvider)`，所有 watch 它的 provider
/// （校历安排、网费汇总、请假列表…）自动级联重取**，不再需要手工失效名单。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 平台标识存储 box（key `guid`）。
final platformGuidBoxProvider = FutureProvider<Box<String>>(
  (ref) => Hive.openBox<String>('wxPlatform'),
);

/// 已配置的平台 GUID；**未配置（缺失 / 空白）一律为 null**。
///
/// 「空白 = 未配置」是全体使用方的共同口径，靠它才能让「去配置平台标识」的引导与
/// 「有没有实时源」的判断处处一致 —— 旧 `wxGuidProvider` 不 trim，`''` 会被当成
/// 「已配置」，是个只在用户把输入框清空时才现形的坑。
final platformGuidProvider = FutureProvider<String?>((ref) async {
  final box = await ref.watch(platformGuidBoxProvider.future);
  final raw = box.get('guid');
  final guid = raw?.trim();
  return (guid == null || guid.isEmpty) ? null : guid;
});
