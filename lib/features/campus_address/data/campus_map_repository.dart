import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'package:smarter_jxufe/features/campus_address/data/anti_corruption/campus_map_parser.dart';
import 'package:smarter_jxufe/features/campus_address/domain/campus_map_geometry.dart';

/// 校区矢量地图的取数入口。
///
/// 数据是**随包内置的 asset**（`assets/campus_map/<id>.json`，
/// 由 `tool/jxufe_map/build_geometry.py` 生成）：没有网络请求、没有会话依赖，
/// 因此不需要 `PageAutoRefresher`、也不会有「会话失效」这种错误态。
class CampusMapRepository {
  const CampusMapRepository({
    this.parser = const CampusMapParser(),
  });

  final CampusMapParser parser;

  /// asset 目录前缀。与 `pubspec.yaml` 的 `assets/campus_map/` 声明一一对应。
  static const String assetDir = 'assets/campus_map';

  /// `<id>.json` 的完整 asset key。
  static String assetFor(String id) => '$assetDir/$id.json';

  /// 按校区 id 读图。
  ///
  /// asset 缺失 / JSON 损坏时**抛异常**（交给 `AsyncValue.error` 上屏）——
  /// 这里刻意不返回空图：空图会被用户当成「这个校区就是这样」，
  /// 而真实原因是资源没打包进去，必须让人看见（§30 的教训）。
  Future<CampusMapGeometry> load(String id) async {
    final raw = await rootBundle.loadString(assetFor(id));
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw FormatException('校区地图 asset 格式不对：$id');
    }
    return parser.parse(Map<String, dynamic>.from(decoded), fallbackId: id);
  }

  /// 一次性读多个校区（并行）。任一失败即整体失败，避免半截状态。
  Future<Map<String, CampusMapGeometry>> loadAll(List<String> ids) async {
    final result = <String, CampusMapGeometry>{};
    for (final id in ids) {
      result[id] = await load(id);
    }
    return result;
  }
}
