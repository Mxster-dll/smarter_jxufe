import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/campus_address/data/campus_map_repository.dart';
import 'package:smarter_jxufe/features/campus_address/domain/campus_map_geometry.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';

/// 取数入口（无状态，可安全重建）。
final campusMapRepositoryProvider = Provider<CampusMapRepository>(
  (ref) => const CampusMapRepository(),
);

/// 单个校区的矢量底图（**随包 asset，不发网络**）。
///
/// 入参 = [MyCampus] 的**枚举名**（`jiaoqiao` / `mailu` / `fenglin` / `qingshan`），
/// 与 `assets/campus_map/<id>.json` 的文件名一一对应；这份对应关系由
/// `tool/jxufe_map/build_geometry.py` 的 `CAMPUS_KEYS` 决定，
/// 守卫 = `test/campus_map_test.dart`（asset 台账 + 枚举对齐）。
///
/// 刻意**不使用 autoDispose**：四个校区的图加起来不到 80KB，
/// 用户在校区之间来回切换时不该反复解析（也避免每次重建都闪一下加载态）。
final campusMapGeometryProvider =
    FutureProvider.family<CampusMapGeometry, String>((ref, id) async {
  final repo = ref.watch(campusMapRepositoryProvider);
  return repo.load(id);
});

/// 把 [MyCampus] 直接喂给 [campusMapGeometryProvider]，省得每个调用点自己拆枚举名。
final myCampusMapGeometryProvider =
    FutureProvider.family<CampusMapGeometry, MyCampus>((ref, campus) {
  return ref.watch(campusMapGeometryProvider(campus.name).future);
});
