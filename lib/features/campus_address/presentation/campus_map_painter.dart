import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/features/campus_address/domain/campus_map_geometry.dart';

/// 一套地图配色（浅色 / 深色），由 `lib/design/status_palette.dart` 的
/// `CampusMapTone` 组装而来 —— 页面里不许自己写 `Color(0x…)`。
@immutable
class CampusMapStyle {
  const CampusMapStyle({
    required this.ground,
    required this.water,
    required this.waterEdge,
    required this.green,
    required this.sport,
    required this.sportEdge,
    required this.road,
    required this.roadCasing,
    required this.building,
    required this.buildingEdge,
    required this.buildingNamed,
    required this.label,
    required this.labelHalo,
    required this.accent,
  });

  final Color ground;
  final Color water;
  final Color waterEdge;
  final Color green;
  final Color sport;
  final Color sportEdge;
  final Color road;
  final Color roadCasing;
  final Color building;
  final Color buildingEdge;
  final Color buildingNamed;
  final Color label;
  final Color labelHalo;
  final Color accent;
}

/// 校区矢量地图的绘制。
///
/// 三件事，与参考实现（杭州行程图那套手写 SVG 引擎）同构：
/// 1. **投影 + 适配**：`fit` 把 [CampusMapGeometry.bounds] 等比放进
///    「逻辑底图尺寸」，得到一个线性变换；平移缩放交给外层
///    [InteractiveViewer] / [TransformationController]，Painter 不持手势状态。
/// 2. **分层顺序**：绿地 → 运动场 → 水面 → 道路（先描边后填充，做出路缘）
///    → 建筑 → 标注。改顺序就会看起来像另一张图。
/// 3. **标注互斥**：按 [CampusLabel.priority] 从高到低**贪心占位**，
///    与已上屏的标签框重叠或出界的直接不画 —— 参考实现用的是
///    「物理松弛 + 位移超限即隐藏」，校区图标签是静态的，
///    贪心一次算完更简单、且结果稳定（同样的缩放永远同样的结果）。
class CampusMapPainter extends CustomPainter {
  CampusMapPainter({
    required this.geometry,
    required this.style,
    required this.textScale,
    required this.showLabels,
    this.highlight,
  });

  final CampusMapGeometry geometry;
  final CampusMapStyle style;

  /// 文字缩放（0.9 = 小屏 / 1.0 常规）。地图几何不受它影响。
  final double textScale;

  /// 是否画文字标注。手指缩放到很小的时候关掉，图更干净。
  final bool showLabels;

  /// 需要高亮的点（如「我的校区」的定位点），null = 不高亮。
  final Offset? highlight;

  /// 底图四周留白（逻辑 px）。
  static const double _pad = 48.0;

  /// 世界（米）→ 逻辑底图的线性变换。
  ///
  /// 返回 `(scale, dx, dy)`：`screenX = x * scale + dx`，
  /// `screenY = -y * scale + dy`（**y 翻转**：几何 y 向北为正，屏幕 y 向下为正）。
  ({double scale, double dx, double dy}) fit(Size size) {
    final b = geometry.bounds;
    final w = math.max(b.width, 1e-6);
    final h = math.max(b.height, 1e-6);
    final availW = math.max(size.width - _pad * 2, 1.0);
    final availH = math.max(size.height - _pad * 2, 1.0);
    final scale = math.min(availW / w, availH / h);
    final dx = (size.width - w * scale) / 2 - b.left * scale;
    final dy = (size.height + h * scale) / 2 + b.top * scale;
    return (scale: scale, dx: dx, dy: dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final f = fit(size);
    final visible = Offset.zero & size;
    // 视口裁剪：放得很大时只画看得见的部分（建筑 + 道路动辄上千点）。
    final worldVisible = _worldVisibleRect(f, visible);

    canvas.save();
    // 底色铺满整块画布（不然放大到图外会看到透明）。
    canvas.drawRect(visible, Paint()..color = style.ground);
    canvas.clipRect(visible);

    canvas.translate(f.dx, f.dy);
    canvas.scale(f.scale);
    canvas.scale(1, -1); // y 翻转：世界 y 向北，画布 y 向南

    _paintPolygons(canvas, geometry.greens, worldVisible, style.green, null, 0);
    _paintPolygons(canvas, geometry.sports, worldVisible, style.sport,
        style.sportEdge, 1.2 / f.scale);
    _paintPolygons(canvas, geometry.waterAreas, worldVisible, style.water,
        style.waterEdge, 2.0 / f.scale);
    _paintPolylines(canvas, geometry.waterLines, worldVisible, style.water,
        6.0 / f.scale);

    _paintRoads(canvas, f.scale, worldVisible);
    _paintBuildings(canvas, f.scale, worldVisible);

    canvas.restore();

    if (showLabels) {
      _paintLabels(canvas, size, f);
    }
    _paintHighlight(canvas, f);
  }

  /// 屏幕可见区对应的世界（米）矩形，含一点余量。
  Rect _worldVisibleRect(
    ({double scale, double dx, double dy}) f,
    Rect visible,
  ) {
    // screenX = x*s + dx  ⇒  x = (screenX - dx)/s
    // screenY = -y*s + dy ⇒  y = (dy - screenY)/s
    final x0 = (visible.left - f.dx) / f.scale;
    final x1 = (visible.right - f.dx) / f.scale;
    final y0 = (f.dy - visible.bottom) / f.scale;
    final y1 = (f.dy - visible.top) / f.scale;
    final margin = 40.0;
    return Rect.fromLTRB(x0 - margin, y0 - margin, x1 + margin, y1 + margin);
  }

  void _paintPolygons(
    Canvas canvas,
    List<CampusPolygon> list,
    Rect world,
    Color fill,
    Color? stroke,
    double strokeWidth,
  ) {
    final paint = Paint()..color = fill;
    final edge = stroke == null
        ? null
        : (Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth);
    for (final poly in list) {
      if (!_intersects(poly.points, world)) continue;
      final path = _pathOf(poly.points);
      canvas.drawPath(path, paint);
      if (edge != null) canvas.drawPath(path, edge);
    }
  }

  void _paintPolylines(
    Canvas canvas,
    List<CampusPolyline> list,
    Rect world,
    Color color,
    double strokeWidth,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final line in list) {
      if (!_intersects(line.points, world)) continue;
      canvas.drawPath(_pathOf(line.points), paint);
    }
  }

  /// 道路：先画一遍较宽的「路缘」再画一遍路面 —— 参考实现里
  /// 这一步让平面图立刻有层次，比给每条路配两种颜色省事。
  void _paintRoads(
    Canvas canvas,
    double scale,
    Rect world,
  ) {
    final casing = Paint()
      ..color = style.roadCasing
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final surface = Paint()
      ..color = style.road
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final road in geometry.roads) {
      if (!_intersects(road.points, world)) continue;
      // 世界坐标是米，线宽也按米给：主路 ~14m、步道 ~2.5m 更贴近真实观感。
      final metres = 2.0 + road.width * 2.6;
      casing.strokeWidth = (metres + 1.6) / 1.0;
      surface.strokeWidth = metres;
      final path = _pathOf(road.points);
      canvas.drawPath(path, casing);
      canvas.drawPath(path, surface);
    }
  }

  void _paintBuildings(Canvas canvas, double scale, Rect world) {
    final fills = <CampusBuildingKind, Paint>{
      CampusBuildingKind.teaching: Paint()..color = style.buildingNamed,
      CampusBuildingKind.dorm: Paint()..color = style.building,
      CampusBuildingKind.sport: Paint()..color = style.buildingNamed,
      CampusBuildingKind.service: Paint()..color = style.building,
    };
    // 描边按屏幕像素恒定：世界坐标里除一个 scale。
    final edge = Paint()
      ..color = style.buildingEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / scale;
    for (final b in geometry.buildings) {
      if (!_intersects(b.points, world)) continue;
      final path = _pathOf(b.points);
      canvas.drawPath(path, fills[b.kind] ?? fills[CampusBuildingKind.service]!);
      canvas.drawPath(path, edge);
    }
  }

  /// 标注排版：按优先级贪心占位。
  void _paintLabels(
    Canvas canvas,
    Size size,
    ({double scale, double dx, double dy}) f,
  ) {
    // 文字大小跟着缩放走，但夹在一个可读区间里：
    // 缩得太小读不了、放得太大挡图。开方让文字的放大慢于地图。
    final zoom = (f.scale / _referenceScale).clamp(0.5, 8.0);
    final fontSize =
        (10.5 * math.sqrt(zoom) * textScale).clamp(9.0, 20.0);
    final placed = <Rect>[];
    final visible = Offset.zero & size;

    final ordered = [...geometry.labels]
      ..sort((a, b) => b.priority.compareTo(a.priority));

    for (final label in ordered) {
      if (label.priority < CampusMapGeometry.labelMinPriority) continue;
      final (sx, sy) = _toScreen(label.position, f);
      if (!visible.contains(Offset(sx, sy))) continue;

      final tp = TextPainter(
        text: TextSpan(
          text: label.name,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.0,
            fontWeight:
                label.isAnchor ? FontWeight.w600 : FontWeight.w400,
            color: style.label,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final box = Rect.fromCenter(
        center: Offset(sx, sy),
        width: tp.width + 8,
        height: tp.height + 5,
      );
      if (!visible.overlaps(box)) continue;
      // 贪心：与已上屏的任何一个标签相交就放弃（锚点级标签之间也让位，
      // 因为校区图里「图书馆」和「一食堂」叠在一起同样读不出来）。
      var clash = false;
      for (final r in placed) {
        if (r.overlaps(box)) {
          clash = true;
          break;
        }
      }
      if (clash) continue;
      placed.add(box);

      // 半透明底衬，保证压在建筑/水面上也读得清（深色款尤其需要）。
      final rrect = RRect.fromRectAndRadius(box, const Radius.circular(3));
      canvas.drawRRect(rrect, Paint()..color = style.labelHalo);
      tp.paint(canvas, Offset(box.center.dx - tp.width / 2,
          box.center.dy - tp.height / 2));
    }
  }

  void _paintHighlight(Canvas canvas, ({double scale, double dx, double dy}) f) {
    final h = highlight;
    if (h == null) return;
    final (sx, sy) = _toScreen(h, f);
    // 高亮点位随缩放**缓慢**变大（开方），缩到最小时也不至于消失。
    final zoom = (f.scale / _referenceScale).clamp(0.25, 8.0);
    final r = (6.0 * math.sqrt(zoom)).clamp(4.0, 14.0);
    canvas.drawCircle(Offset(sx, sy), r + 2,
        Paint()..color = style.labelHalo);
    canvas.drawCircle(Offset(sx, sy), r, Paint()..color = style.accent);
  }

  /// 世界（米）→ 屏幕像素。
  (double, double) _toScreen(
    Offset world,
    ({double scale, double dx, double dy}) f,
  ) =>
      (world.dx * f.scale + f.dx, f.dy - world.dy * f.scale);

  /// 底图逻辑尺寸（与 [CampusMapView] 的内容尺寸同源）。
  ///
  /// `fit()` 在**这个**尺寸下算出的 scale 就是「未缩放」的基准，
  /// 文字与高亮点位都按 `当前 scale / 基准 scale` 决定大小 ——
  /// 于是同一张图在手机和桌面上「看起来一样密」，放大后文字才变大。
  static Size referenceSizeFor(CampusMapGeometry g) {
    final b = g.bounds;
    return b.width >= b.height
        ? const Size(_baseLong, _baseShort)
        : const Size(_baseShort, _baseLong);
  }

  static const double _baseLong = 1600.0;
  static const double _baseShort = 1000.0;

  /// 当前绘制尺度相对「整图适配」的倍数。1.0 = 刚好看全整张图。
  double zoomFactor(Size size) => fit(size).scale / _referenceScale;

  /// 把 [CampusMapPainter.referenceSizeFor] 的适配比例作为基准。
  double get _referenceScale => fit(referenceSizeFor(geometry)).scale;

  static Path _pathOf(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    if (pts.length > 2) path.close();
    return path;
  }

  /// 折线/多边形的包围盒是否与 [world] 相交（粗筛，省掉大量 path 构建）。
  static bool _intersects(List<Offset> pts, Rect world) {
    if (pts.isEmpty) return false;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return world.overlaps(Rect.fromLTRB(minX, minY, maxX, maxY));
  }

  /// 命中测试：返回覆盖 [screenPoint] 的最小的建筑（小的优先，避免大建筑
  /// 把里面的小建筑全遮住）。
  CampusPolygon? buildingAt(Offset screenPoint, Size size) {
    final f = fit(size);
    final world = Offset(
      (screenPoint.dx - f.dx) / f.scale,
      (f.dy - screenPoint.dy) / f.scale,
    );
    CampusPolygon? best;
    var bestArea = double.infinity;
    for (final b in geometry.buildings) {
      final area = b.areaM2 > 0 ? b.areaM2 : _approxArea(b.points);
      if (area >= bestArea) continue;
      if (!_pointInPolygon(world, b.points)) continue;
      best = b;
      bestArea = area;
    }
    return best;
  }

  static double _approxArea(List<Offset> pts) {
    if (pts.length < 3) return 0;
    var s = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      s += pts[i].dx * pts[i + 1].dy - pts[i + 1].dx * pts[i].dy;
    }
    return s.abs() / 2;
  }

  static bool _pointInPolygon(Offset p, List<Offset> ring) {
    if (ring.length < 3) return false;
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  @override
  bool shouldRepaint(CampusMapPainter old) =>
      old.geometry != geometry ||
      old.style != style ||
      old.textScale != textScale ||
      old.showLabels != showLabels ||
      old.highlight != highlight;
}

/// 把 [CampusMapPainter] 包成 Widget：负责手势（拖动 / 双指缩放 / 滚轮）、
/// 点击命中测试与「重置视图」。
class CampusMapView extends StatefulWidget {
  const CampusMapView({
    super.key,
    required this.geometry,
    required this.style,
    this.onBuildingTap,
    this.highlight,
    this.resetToken = 0,
    this.labelsVisible = true,
  });

  final CampusMapGeometry geometry;
  final CampusMapStyle style;

  /// 点到建筑时回调（名字为空也会回调，由调用方决定说不说）。
  final void Function(CampusPolygon? building)? onBuildingTap;

  final Offset? highlight;

  /// 递增即把视图重置回「整图适配」。
  final int resetToken;

  final bool labelsVisible;

  @override
  State<CampusMapView> createState() => _CampusMapViewState();
}

class _CampusMapViewState extends State<CampusMapView> {
  final _controller = TransformationController();

  @override
  void didUpdateWidget(covariant CampusMapView old) {
    super.didUpdateWidget(old);
    if (old.geometry.id != widget.geometry.id ||
        old.resetToken != widget.resetToken) {
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 按当前视口建一个 Painter（既用来画，也用来做命中测试，参数必然一致）。
  CampusMapPainter _painterFor(Size box) => CampusMapPainter(
        geometry: widget.geometry,
        style: widget.style,
        textScale: box.width < Breakpoints.narrow ? 0.92 : 1.0,
        showLabels: widget.labelsVisible,
        highlight: widget.highlight,
      );

  @override
  Widget build(BuildContext context) {
    // 底图按几何长宽比选一个固定的逻辑尺寸（不随屏幕变），
    // InteractiveViewer 再把这块内容缩放到可视区。
    final size = CampusMapPainter.referenceSizeFor(widget.geometry);

    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        return ClipRect(
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: 0.5,
            maxScale: 12,
            // 双指缩放 / 单指拖动 / 滚轮都由它处理，触摸与桌面都可用。
            constrained: false,
            boundaryMargin: const EdgeInsets.all(240),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final cb = widget.onBuildingTap;
                  if (cb == null) return;
                  // 坐标是「底图逻辑坐标」，与 Painter 的 fit 同一坐标系。
                  cb(_painterFor(box).buildingAt(d.localPosition, size));
                },
                child: CustomPaint(
                  size: size,
                  painter: _painterFor(box),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
