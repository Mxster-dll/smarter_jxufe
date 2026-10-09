import 'dart:ui' show Offset, Rect;

import 'package:smarter_jxufe/features/campus_address/domain/campus_map_geometry.dart';

/// 解析 `assets/campus_map/<id>.json`（由 `tool/jxufe_map/build_geometry.py` 生成）。
///
/// 容错口径照本仓约定（§3「模型」）：认不出的要素**跳过**、
/// 认得出的照收，缺字段取默认值 —— 旧 asset 不许把页面打崩。
/// 但「整份文档不可解析」是另一回事，由调用方（repository）处理成错误态。
class CampusMapParser {
  const CampusMapParser();

  /// 坐标精度：生成脚本已量化到 6 位小数，这里只做类型收敛。
  static double _num(Object? v) => v is num ? v.toDouble() : 0.0;

  static String _str(Object? v) => v is String ? v : '';

  /// 解析一个 `[lon, lat]` 点；非法返回 null。
  static ({double lon, double lat})? _point(Object? raw) {
    if (raw is! List || raw.length < 2) return null;
    final lon = raw[0];
    final lat = raw[1];
    if (lon is! num || lat is! num) return null;
    return (lon: lon.toDouble(), lat: lat.toDouble());
  }

  /// 把 `[{lon,lat},...]` 的经纬度环投成米制环。
  static List<Offset> _ring(Object? raw, CampusProjection proj) {
    if (raw is! List) return const <Offset>[];
    final out = <Offset>[];
    for (final p in raw) {
      final ll = _point(p);
      if (ll == null) continue;
      out.add(proj.project(ll.lon, ll.lat));
    }
    return out;
  }

  static List<Offset> _line(Object? raw, CampusProjection proj) => _ring(raw, proj);

  /// 解析整份文档。`id` 缺失时用 [fallbackId]。
  CampusMapGeometry parse(Map<String, dynamic> json, {String fallbackId = ''}) {
    final boundsRaw = json['bounds'];
    var west = 0.0, south = 0.0, east = 0.0, north = 0.0;
    var hasBounds = false;
    if (boundsRaw is List && boundsRaw.length >= 4) {
      final w = boundsRaw[0], s = boundsRaw[1], e = boundsRaw[2], n = boundsRaw[3];
      if (w is num && s is num && e is num && n is num) {
        west = w.toDouble();
        south = s.toDouble();
        east = e.toDouble();
        north = n.toDouble();
        hasBounds = true;
      }
    }

    // 投影原点：优先用 asset 的 origin（生成脚本写的校区中心），
    // 缺失时退回 bounds 中心 —— 两者都拿不到才用 (0,0)，此时图会退化但不会崩。
    final originRaw = json['origin'];
    var originLon = hasBounds ? (west + east) / 2 : 0.0;
    var originLat = hasBounds ? (south + north) / 2 : 0.0;
    if (originRaw is List && originRaw.length >= 2) {
      final lon = originRaw[0], lat = originRaw[1];
      if (lon is num && lat is num) {
        originLon = lon.toDouble();
        originLat = lat.toDouble();
      }
    }
    final proj = CampusProjection(originLon: originLon, originLat: originLat);

    final buildings = <CampusPolygon>[];
    for (final raw in _list(json['building'])) {
      final pts = _ring(raw['p'], proj);
      if (pts.length < 3) continue;
      final cRaw = _point(raw['c']);
      buildings.add(CampusPolygon(
        points: pts,
        name: _str(raw['n']),
        kind: CampusBuildingKind.parse(raw['k'] as String?),
        centroid: cRaw == null ? null : proj.project(cRaw.lon, cRaw.lat),
        areaM2: _num(raw['a']),
      ));
    }

    final roads = <CampusPolyline>[];
    for (final raw in _list(json['road'])) {
      final pts = _line(raw['p'], proj);
      if (pts.length < 2) continue;
      roads.add(CampusPolyline(
        points: pts,
        name: _str(raw['n']),
        kind: _str(raw['k']),
        width: _num(raw['w']).round().clamp(1, 5),
      ));
    }

    final waterAreas = <CampusPolygon>[];
    final waterLines = <CampusPolyline>[];
    for (final raw in _list(json['water'])) {
      final pts = _ring(raw['p'], proj);
      if (pts.length < 2) continue;
      // 生成脚本把闭合水体（natural=water）与河道（waterway）都放进 water 层，
      // 用「是否闭合」区分：闭合成面、不闭合成线。
      if (pts.length >= 4 && (pts.first - pts.last).distance < 0.5) {
        waterAreas.add(CampusPolygon(points: pts, name: _str(raw['n'])));
      } else {
        waterLines.add(CampusPolyline(points: pts, name: _str(raw['n'])));
      }
    }

    final greens = <CampusPolygon>[];
    for (final raw in _list(json['green'])) {
      final pts = _ring(raw['p'], proj);
      if (pts.length < 3) continue;
      greens.add(CampusPolygon(points: pts, name: _str(raw['n'])));
    }

    final sports = <CampusPolygon>[];
    for (final raw in _list(json['sport'])) {
      final pts = _ring(raw['p'], proj);
      if (pts.length < 3) continue;
      sports.add(CampusPolygon(
        points: pts,
        name: _str(raw['n']),
        kind: null,
      ));
    }

    final labels = <CampusLabel>[];
    for (final raw in _list(json['label'])) {
      final name = _str(raw['n']).trim();
      if (name.isEmpty) continue;
      final lon = raw['x'], lat = raw['y'];
      if (lon is! num || lat is! num) continue;
      labels.add(CampusLabel(
        name: name,
        position: proj.project(lon.toDouble(), lat.toDouble()),
        priority: _num(raw['pri']).round().clamp(1, 3),
      ));
    }

    return CampusMapGeometry(
      id: _str(json['id']).isEmpty ? fallbackId : _str(json['id']),
      name: _str(json['name']),
      projection: proj,
      bounds: hasBounds
          ? _projectedBounds(proj, west, south, east, north)
          : _boundsOf(buildings, roads, waterAreas, waterLines, greens, sports),
      buildings: buildings,
      roads: roads,
      waterAreas: waterAreas,
      waterLines: waterLines,
      greens: greens,
      sports: sports,
      labels: labels,
      attribution: _str(json['attribution']),
      clip: _str(json['clip']),
    );
  }

  /// 经纬度包围盒 → 投影平面包围盒。
  static Rect _projectedBounds(
    CampusProjection proj,
    double west,
    double south,
    double east,
    double north,
  ) {
    final a = proj.project(west, south);
    final b = proj.project(east, north);
    return Rect.fromLTRB(
      a.dx < b.dx ? a.dx : b.dx,
      a.dy < b.dy ? a.dy : b.dy,
      a.dx > b.dx ? a.dx : b.dx,
      a.dy > b.dy ? a.dy : b.dy,
    );
  }

  /// asset 没给 bounds 时的兜底：扫全部几何求包围盒。
  static Rect _boundsOf(
    List<CampusPolygon> buildings,
    List<CampusPolyline> roads,
    List<CampusPolygon> waterAreas,
    List<CampusPolyline> waterLines,
    List<CampusPolygon> greens,
    List<CampusPolygon> sports,
  ) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    void eat(Iterable<Offset> pts) {
      for (final p in pts) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }

    for (final b in buildings) {
      eat(b.points);
    }
    for (final r in roads) {
      eat(r.points);
    }
    for (final w in waterAreas) {
      eat(w.points);
    }
    for (final w in waterLines) {
      eat(w.points);
    }
    for (final g in greens) {
      eat(g.points);
    }
    for (final s in sports) {
      eat(s.points);
    }
    if (minX > maxX || minY > maxY) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// 取出 `List<Map>` 视图；非列表或元素不是 Map 一律跳过。
  static Iterable<Map<String, dynamic>> _list(Object? raw) sync* {
    if (raw is! List) return;
    for (final e in raw) {
      if (e is Map) yield Map<String, dynamic>.from(e);
    }
  }
}
