/// 校区矢量地图的领域模型。
///
/// 数据来源 = `assets/campus_map/<id>.json`，由 `tool/jxufe_map/build_geometry.py`
/// 从 OpenStreetMap 快照裁出来（生成脚本与实测台账见 `tool/jxufe_map/`）。
///
/// 设计三口径：
/// 1. **保留 WGS84 经纬度**，投影在加载时做一次（[CampusProjection]）——
///    与生成脚本的坐标系一致，将来换渲染端（Web / 桌面 / 导出 SVG）不用改数据。
/// 2. 坐标一律 `[lon, lat]`（x, y），**不是** `[lat, lon]`，与 GeoJSON 一致。
/// 3. 解析全程容错：缺字段 / 类型不对一律跳过该条或取默认值，
///    **不让旧 asset 把页面打崩**（本仓 §3「模型」约定）。
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// 建筑分类（决定填充色深浅）。与生成脚本 `classify_building` 的键一一对应。
enum CampusBuildingKind {
  /// 教学楼 / 院系楼 / 图书馆等公共建筑。
  teaching,

  /// 宿舍 / 公寓。
  dorm,

  /// 体育馆 / 健身房 / 看台。
  sport,

  /// 食堂、商业、后勤、厂房等。
  service;

  static CampusBuildingKind parse(String? raw) {
    for (final k in CampusBuildingKind.values) {
      if (k.name == raw) return k;
    }
    return CampusBuildingKind.service;
  }
}

/// 一条多边形要素（建筑 / 水体 / 绿地 / 运动场）。
class CampusPolygon {
  const CampusPolygon({
    required this.points,
    this.name = '',
    this.kind,
    this.centroid,
    this.areaM2 = 0,
  });

  /// 投影后的平面坐标（米），首尾**已闭合**（首点 == 末点）。
  final List<Offset> points;

  /// OSM 上的名字；无名要素为空串。
  final String name;

  /// 仅建筑有：分类。
  final CampusBuildingKind? kind;

  /// 质心（米），标签锚点用；生成脚本没给时为 [points] 的算术平均。
  final Offset? centroid;

  /// 面积（平方米），仅建筑有。
  final double areaM2;

  /// 标签锚点。
  Offset get anchor => centroid ?? _fallbackCentroid(points);

  static Offset _fallbackCentroid(List<Offset> pts) {
    if (pts.isEmpty) return Offset.zero;
    var sx = 0.0, sy = 0.0;
    final n = pts.length == 1 ? 1 : pts.length - 1; // 闭合时末点重复
    for (var i = 0; i < n; i++) {
      sx += pts[i].dx;
      sy += pts[i].dy;
    }
    return Offset(sx / n, sy / n);
  }
}

/// 一条折线要素（道路 / 河道 / 围墙）。
class CampusPolyline {
  const CampusPolyline({
    required this.points,
    this.name = '',
    this.kind = '',
    this.width = 1,
  });

  /// 投影后的平面坐标（米）。
  final List<Offset> points;

  /// OSM 名字（多为空 —— 校内路基本没名字）。
  final String name;

  /// `highway=*` 原值，如 `footway`。
  final String kind;

  /// 生成脚本给的宽度档（1 小路 / 2 步道 / 3 次干 / 4 主干 / 5 快速路）。
  final int width;
}

/// 一个文字标签。
class CampusLabel {
  const CampusLabel({
    required this.name,
    required this.position,
    required this.priority,
  });

  final String name;

  /// 投影后的平面坐标（米）。
  final Offset position;

  /// 优先级：3 = 图书馆/食堂/校门/场馆这类找路锚点，2 = 普通建筑，1 = 其他。
  /// 越大越优先上屏；位置不够时**先牺牲小的**。
  final int priority;

  /// 上屏门槛：只有 ≥ [CampusMapGeometry.labelMinPriority] 的才参与排版。
  bool get isAnchor => priority >= 3;
}

/// 一个校区的完整矢量底图。
class CampusMapGeometry {
  const CampusMapGeometry({
    required this.id,
    required this.name,
    required this.projection,
    required this.bounds,
    required this.buildings,
    required this.roads,
    required this.waterAreas,
    required this.waterLines,
    required this.greens,
    required this.sports,
    required this.labels,
    this.attribution = '',
    this.clip = '',
  });

  /// 与 `MyCampus` 枚举名一致（`jiaoqiao` / `mailu` / `fenglin` / `qingshan`）。
  final String id;

  /// 官方校区名，如「蛟桥园校区」。
  final String name;

  /// 经纬度 → 平面米制（含原点），加载时建立一次。
  final CampusProjection projection;

  /// 全部几何在**投影平面**上的包围盒（米）。
  final Rect bounds;

  final List<CampusPolygon> buildings;
  final List<CampusPolyline> roads;
  final List<CampusPolygon> waterAreas;
  final List<CampusPolyline> waterLines;
  final List<CampusPolygon> greens;
  final List<CampusPolygon> sports;
  final List<CampusLabel> labels;

  /// 版权署名，如「地图数据 © OpenStreetMap 贡献者 (ODbL)」。
  final String attribution;

  /// 裁剪依据（生成脚本写入，排查用）。
  final String clip;

  /// 参与文字排版的标签门槛。优先级 1 的是「周边小店」这类噪声，默认不上屏。
  static const int labelMinPriority = 2;

  /// 是否是一张「几乎空白」的图（OSM 在该校区缺测绘）。
  ///
  /// 用于界面上**如实提示用户**，而不是给一张看着像出错的空图。
  bool get isSparse => buildings.length < 8;

  /// 建筑总数（散点统计等用）。
  int get buildingCount => buildings.length;
}

/// Web Mercator 投影（与 `tool/jxufe_map/build_geometry.py` 的局部平面一致）。
///
/// 只做**局部**等距近似：以校区中心为原点，经度按 `cos(lat0)` 收缩，
/// 纬度按每度 [metersPerDegLat] 计。校区尺度（<2km）下误差远小于 1m，
/// 不足以在屏幕上看出形变 —— 换来的是渲染端每次只要两次乘加。
class CampusProjection {
  const CampusProjection({
    required this.originLon,
    required this.originLat,
  });

  /// 投影原点（校区中心，取自 asset 的 `origin`）。
  final double originLon;
  final double originLat;

  /// 每度纬度对应的米数（WGS84 子午线弧长的局部近似）。
  static const double metersPerDegLat = 110574.0;

  /// 每度经度对应的米数（随纬度收缩）。
  static const double _metersPerDegLonAtEquator = 111320.0;

  double get metersPerDegLon =>
      _metersPerDegLonAtEquator * math.cos(originLat * math.pi / 180.0);

  /// 经纬度 → 平面米制坐标。**y 轴向上**（北为正），与 SVG / 屏幕的 y 向下相反，
  /// 翻转换算放在渲染端（[CampusProjection.toScreen] 之外），保持领域模型与地理直觉一致。
  Offset project(double lon, double lat) => Offset(
        (lon - originLon) * metersPerDegLon,
        (lat - originLat) * metersPerDegLat,
      );

  /// [project] 的逆运算（用于把点击位置换回经纬度）。
  ({double lon, double lat}) unproject(Offset p) => (
        lon: originLon + p.dx / metersPerDegLon,
        lat: originLat + p.dy / metersPerDegLat,
      );

  /// 两点间的近似地面距离（米）。
  double distance(Offset a, Offset b) => (a - b).distance;
}
