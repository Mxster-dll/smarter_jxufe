/// 综测 providers：存储 + 自动源（课程加权 / 第二课堂志愿时长，**均按测评学年**）。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_providers.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_store.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_year_sources.dart';

/// 综测本地 box 的**基础**名（实际 box 按账号隔离）。
const zcBoxName = 'zongce';

/// 综测本地 box（**按账号隔离**：本人录的材料与认定结果不该跨账号串）。
///
/// 见 `core/storage/account_scoped_box.dart`：box 名 = `zongce_<账号>`，
/// 账号未确定时用 `zongce__none`；旧的全局 box 被第一个打开的账号迁移认领一次。
///
/// 注：材料附件目录（`zc_files`）仍全校共用——它只存图片等附件，文件名唯一，
/// 且列表只从**本账号的 box** 读，因此不会互相看见；反之若按账号分目录，
/// 存量附件会立刻变孤儿。
final zcBoxProvider = FutureProvider<Box<String>>(
  (ref) => openAccountScopedBox(zcBoxName, ref.watch(currentAccountProvider)),
);

final zcStoreProvider = FutureProvider<ZcStore>((ref) async {
  final box = await ref.watch(zcBoxProvider.future);
  final dir = await getApplicationSupportDirectory();
  final filesDir = p.join(dir.path, 'zc_files');
  await Directory(filesDir).create(recursive: true);
  return ZcStore(box, filesDir);
});

/// 证明材料库（数据源层，供测算页与独立材料库页共同 watch）。
/// 任一侧保存/删除材料后 `ref.invalidate(zcMaterialsProvider)` 即全链路刷新。
final zcMaterialsProvider = FutureProvider<List<ZcMaterial>>((ref) async {
  final store = await ref.watch(zcStoreProvider.future);
  return store.loadMaterials();
});

/// 自动源 · 该**测评学年**的课程加权成绩（`yearEnd` = 学年结束年）。
///
/// 口径（用户 2026-09-16 裁定「综测按学年算」）：只统计学期落在该学年的课程
/// —— `yearEnd` 2026 → 2025-2026 学年 → 学期码 `251/252/253`。
/// 数据来自成绩缓存（账号隔离 + 成绩页排除名单 + 同课去重，见
/// `gePriorGradesProvider`），**离线可读**；该学年无成绩 / 未登录 → null
/// （界面回退手动填写）。
final zcAutoWeightProvider = FutureProvider.family<double?, int>((
  ref,
  yearEnd,
) async {
  try {
    final grades = await ref.watch(gePriorGradesProvider.future);
    return zcWeightedForYear(grades, yearEnd: yearEnd);
  } catch (_) {
    return null;
  }
});

/// 自动源 · 该**测评学年**内认定的第二课堂志愿时长（小时）。
///
/// 活动按活动日期归入学年窗口 `[yearEnd-1]-09-01 ~ [yearEnd]-08-31`；一条日期
/// 都取不到 → null（回退手动填写，**别显示 0**）。
final zcAutoVolunteerProvider = FutureProvider.family<double?, int>((
  ref,
  yearEnd,
) async {
  try {
    final acts = await ref.watch(volunteerActivitiesProvider.future);
    return zcVolunteerHoursForYear(acts, yearEnd: yearEnd);
  } catch (_) {
    return null;
  }
});
