/// 综测 providers：存储 + 自动源（教务加权 / 第二课堂志愿累计）。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/weighted_grade_repository_provider.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_store.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

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

/// 自动源 · 教务加权成绩（typeId 1 全部课程累计；无登录/失败 → null）。
final zcAutoWeightProvider = FutureProvider<double?>((ref) async {
  try {
    final wg = await ref.watch(weightedGradeRankingProvider(1).future);
    return double.tryParse(wg?.grade ?? '');
  } catch (_) {
    return null;
  }
});

/// 自动源 · 第二课堂志愿累计小时（SSP 活动 recognizedHours 求和；无登录/失败 → null）。
final zcAutoVolunteerProvider = FutureProvider<double?>((ref) async {
  try {
    final acts = await ref.watch(volunteerActivitiesProvider.future);
    var total = 0.0;
    for (final a in acts) {
      total += double.tryParse(a.recognizedHours) ?? 0;
    }
    return total;
  } catch (_) {
    return null;
  }
});
