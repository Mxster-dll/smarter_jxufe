/// 宫格卡片的渲染件（**支持异形**）。
///
/// 重构前一张卡就是一个 `Material(shape: appCardShape)` 圆角矩形；聚合之后一张卡可以
/// 占任意一组连通格子（L 形 / F 形 / 互补嵌合的形状），所以卡片轮廓改由
/// [homeGridShapePath] 用「形状的轮廓环 + 全转角倒圆角」画出来：
/// - 环沿**格线**走（同一张卡里相邻两格之间的 12px 格缝本来就在环内部），外框仍然
///   恰好落在包围盒上；每个 90° 转角都做成半径 `kAppCardRadius` 的圆角 ——
///   **凸角收圆、凹角也倒圆**，整块异形看起来就是**一张卡**；
/// - 一个环画一条子路径（中间有洞的形状会得到第二个反向环），**不靠布尔并**：
///   叠合处不会留抗锯齿细线，拐弯内侧也不会留方角突起（`§31` 找空闲教室那轮踩过的
///   同款坑，见 `home_grid_shape.dart` 的 `gridOutlineLoops` 文档）。
///
/// 卡片内部：**一个格子放一个服务**，每格是一张普通磁贴的脸（[HomeGridTileFace]，
/// 与重构前的磁贴逐字同款）。
///
/// ⚠ 格与格之间**默认不画分隔线**（用户 2026-09-21 四轮：「我希望功能与功能之间不显示
/// 分割线」）—— [HomeGridCard.showDividers] 只在需要时打开；拆解模式下的分割线由
/// `home_service_grid.dart` 的缝图层画（可点击、断开后变虚线），不在这里画。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/status_palette.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_layout.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_shape.dart';
import 'package:smarter_jxufe/features/home/presentation/home_grid_metrics.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

/// 卡片内分隔短线的缩进（竖直缝的上下、水平缝的左右各缩进这么多）。
const double kHomeGridDividerInset = 12;

/// 一张（可异形）卡片的轮廓路径（坐标系 = 卡片包围盒的左上角）。
///
/// [origin] = 卡片包围盒左上角所在的格子。
///
/// 口径：**先取形状的轮廓环，再把每个 90° 转角做成圆角**（凸角收圆、凹角倒圆，
/// 半径同为 `radius`），因此：
/// - 拐弯**内侧**是圆滑的倒角，而不是「逐格圆角矩形做布尔并」在格缝交叉处留下的
///   12×12 方角突起（用户 2026-09-21 原话：「卡片在拐弯的时候，内侧会有一个突起，
///   我希望做成圆角」）；
/// - 同一张卡里相邻的两格之间那道 12px 格缝**本来就在轮廓内部**（环只沿格线走、
///   格缝由相邻两格共同填掉），不需要再靠「矩形外扩一个缝宽」去补 —— 旧写法补出来
///   的正是那个突起。
Path homeGridShapePath({
  required Iterable<GridCell> cells,
  required GridCell origin,
  required HomeGridMetrics metrics,
  double radius = kAppCardRadius,
}) {
  final set = gridCellSet(cells);
  if (set.isEmpty) return Path();
  final maxRadius = math.min(metrics.cellWidth, metrics.cellHeight) / 2;
  final eff = radius > maxRadius ? maxRadius : radius;
  final loops = gridOutlineLoops(set);
  final path = Path();
  for (final loop in loops) {
    _addRoundedLoop(
      path,
      <Offset>[
        for (var i = 0; i < loop.length; i++)
          _outlineVertex(
            loop: loop,
            i: i,
            origin: origin,
            metrics: metrics,
          ),
      ],
      eff < 0 ? 0 : eff,
    );
  }
  return path;
}

/// 轮廓顶点的像素位置：**它那条竖边给 x、那条横边给 y**（一个转角恰好一竖一横）。
///
/// ⚠ 一条格线其实有**两个**像素位置：左格的右边（`k*步距 - 缝`）与右格的左边
/// （`k*步距`），差一个缝宽。取哪一个取决于**卡片在那一侧有没有格子** —— 把格线当成
/// 固定位置（比如一律取 `k*格宽 + (k-1)*缝`）会让「拐角内侧贴着哪一格」整体差 12px，
/// 异形卡片的拐角就画歪、倒圆角也跟着歪。
///
/// 判据来自轮廓环的绕向约定（内部恒在前进方向右手边）：向下走 → 料在左（低侧）、
/// 向上走 → 料在右（高侧）；向左走 → 料在上（低侧）、向右走 → 料在下（高侧）。
Offset _outlineVertex({
  required List<GridCell> loop,
  required int i,
  required GridCell origin,
  required HomeGridMetrics metrics,
}) {
  final n = loop.length;
  final prev = loop[(i - 1 + n) % n];
  final cur = loop[i];
  final next = loop[(i + 1) % n];
  double? x;
  double? y;
  void take(GridCell a, GridCell b) {
    if (a.x == b.x) {
      final k = a.x - origin.x;
      x = k * metrics.pitchX - (b.y > a.y ? HomeGridMetrics.gap : 0);
    } else {
      final j = a.y - origin.y;
      y = j * metrics.pitchY - (b.x < a.x ? HomeGridMetrics.gap : 0);
    }
  }

  take(prev, cur);
  take(cur, next);
  return Offset(x ?? 0, y ?? 0);
}

/// 把一条正交折线写进 [path]：**凸角收圆 + 凹角倒圆**（半径不够时按最短边的一半收）。
///
/// 圆弧方向由环的绕向决定：外环（屏幕坐标下顺时针）的凸角是「右转」→ 弧也顺时针；
/// 凹角反过来（弧朝角点鼓出去，把方角补成圆角）。
void _addRoundedLoop(Path path, List<Offset> pts, double radius) {
  final n = pts.length;
  if (n < 3) return;
  if (radius <= 0) {
    path.addPolygon(pts, true);
    return;
  }
  var area = 0.0;
  for (var i = 0; i < n; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % n];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  final clockwise = area > 0; // 屏幕坐标 y 向下：正面积 = 顺时针（外环）
  for (var i = 0; i < n; i++) {
    final prev = pts[(i - 1 + n) % n];
    final cur = pts[i];
    final next = pts[(i + 1) % n];
    final inLen = (cur - prev).distance;
    final outLen = (next - cur).distance;
    final din = inLen <= 0 ? Offset.zero : (cur - prev) / inLen;
    final dout = outLen <= 0 ? Offset.zero : (next - cur) / outLen;
    final cross = din.dx * dout.dy - din.dy * dout.dx;
    if (cross == 0) {
      // 共线（正常情况下已被 gridSimplifyLoop 去掉，这里只是兜底）
      if (i == 0) {
        path.moveTo(cur.dx, cur.dy);
      } else {
        path.lineTo(cur.dx, cur.dy);
      }
      continue;
    }
    final r = math.min(radius, math.min(inLen, outLen) / 2);
    final convex = (cross > 0) == clockwise;
    final start = cur - din * r;
    final end = cur + dout * r;
    if (i == 0) {
      path.moveTo(start.dx, start.dy);
    } else {
      path.lineTo(start.dx, start.dy);
    }
    path.arcToPoint(
      end,
      radius: Radius.circular(r),
      clockwise: convex == clockwise,
    );
  }
  path.close();
}

/// 卡片内「相邻格子」之间的分隔短线（坐标 = 卡片包围盒左上角）。
List<(Offset, Offset)> homeGridDividerSegments({
  required Iterable<GridCell> cells,
  required GridCell origin,
  required HomeGridMetrics metrics,
}) {
  final set = gridCellSet(cells);
  final out = <(Offset, Offset)>[];
  for (final c in gridSorted(set)) {
    final left = (c.x - origin.x) * metrics.pitchX;
    final top = (c.y - origin.y) * metrics.pitchY;
    if (set.contains((x: c.x + 1, y: c.y))) {
      final x = left + metrics.cellWidth + HomeGridMetrics.gap / 2;
      out.add((
        Offset(x, top + kHomeGridDividerInset),
        Offset(x, top + metrics.cellHeight - kHomeGridDividerInset),
      ));
    }
    if (set.contains((x: c.x, y: c.y + 1))) {
      final y = top + metrics.cellHeight + HomeGridMetrics.gap / 2;
      out.add((
        Offset(left + kHomeGridDividerInset, y),
        Offset(left + metrics.cellWidth - kHomeGridDividerInset, y),
      ));
    }
  }
  return out;
}

/// 卡片轮廓的裁剪器（内容按形状裁剪；交互命中同样受它约束）。
class HomeGridShapeClipper extends CustomClipper<Path> {
  /// 轮廓路径。
  final Path path;

  const HomeGridShapeClipper(this.path);

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(covariant HomeGridShapeClipper old) => old.path != path;
}

/// 卡片底色 + 细描边 + 内部分隔线。
class HomeGridShapePainter extends CustomPainter {
  final Path path;

  /// 形状指纹（`shouldRepaint` 用；`Path` 本身没有值相等）。
  final String shapeKey;
  final Color fill;
  final Color borderColor;
  final double borderWidth;
  final Color dividerColor;
  final List<(Offset, Offset)> dividers;

  /// 拖动中（抬起的那张卡）画投影，与静止的卡片区分开。
  final bool shadow;

  const HomeGridShapePainter({
    required this.path,
    required this.shapeKey,
    required this.fill,
    required this.borderColor,
    required this.borderWidth,
    required this.dividerColor,
    required this.dividers,
    this.shadow = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (shadow) {
      canvas.drawShadow(path, StatusPalette.liftedShadow, 8, false);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = fill
        ..isAntiAlias = true
        ..style = PaintingStyle.fill,
    );
    if (borderWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = borderColor
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    }
    if (dividers.isNotEmpty) {
      final paint = Paint()
        ..color = dividerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (final d in dividers) {
        canvas.drawLine(d.$1, d.$2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant HomeGridShapePainter old) =>
      old.shapeKey != shapeKey ||
      old.fill != fill ||
      old.borderColor != borderColor ||
      old.borderWidth != borderWidth ||
      old.dividerColor != dividerColor ||
      old.shadow != shadow ||
      !listEquals(old.dividers, dividers);
}

/// 虚线框（拖动中的落点预览）。
class HomeGridDashedPainter extends CustomPainter {
  final Path path;
  final Color color;

  /// 虚框内部的淡底（null = 只画虚线）。
  final Color? fill;
  final double strokeWidth;
  final double dash;
  final double dashGap;

  const HomeGridDashedPainter({
    required this.path,
    required this.color,
    this.fill,
    this.strokeWidth = 1.6,
    this.dash = 7,
    this.dashGap = 5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final background = fill;
    if (background != null) {
      canvas.drawPath(path, Paint()..color = background);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant HomeGridDashedPainter old) =>
      old.color != color ||
      old.fill != fill ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.dashGap != dashGap ||
      old.path != path;
}

/// 单个服务磁贴的脸（定宽等高；[compact] = 手机端紧凑形态）。
///
/// 与重构前的 `_HomeTile` 逐字同款（宽屏：图标左 + 标题 + 副标题恒占 2 行；
/// 紧凑：图标上 + 标题），只是把「卡片底色 / 描边」交给 [HomeGridCard]。
class HomeGridTileFace extends StatelessWidget {
  final HomeServiceEntry entry;
  final bool compact;

  const HomeGridTileFace({
    super.key,
    required this.entry,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = entry.accent;
    // ⚠ `triggerMode: manual`：Tooltip 默认在触摸端**长按**弹出，而长按现在是
    // 「抬起宫格开始拖动」的手势（用户 2026-09-21 需求）—— 两个 LongPress 识别器
    // 会抢同一个手势，Tooltip 在树里更深、先入 arena，实测拖动永远起不来。
    // 桌面端悬停照旧能看全文；触摸端由拖动优先（副标题本身最多 2 行）。
    return Tooltip(
      message: entry.subtitle,
      triggerMode: TooltipTriggerMode.manual,
      child: InkWell(
        key: Key('homeTile-${entry.title}'),
        onTap: entry.onTap,
        hoverColor: accent.withValues(alpha: 0.05),
        child: compact
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 14,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.tint(context, accent, 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(entry.icon, color: accent, size: 22),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 16 / 13,
                      ),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.tint(context, accent, 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(entry.icon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            entry.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 20 / 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          // 副标题恒占 2 行高（不足 1 行也照样占满）。
                          SizedBox(
                            key: Key('homeSubtitleBox-${entry.title}'),
                            height:
                                HomeGridMetrics.subtitleLineHeight * 2,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(
                                entry.subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 16 / 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// 一张宫格卡片（1..N 个服务 + 任意连通形状）。
class HomeGridCard extends StatelessWidget {
  /// 卡片（形状 + 服务）。
  final HomeGridTile tile;

  /// 几何度量。
  final HomeGridMetrics metrics;

  /// 服务标题 → 目录条目（脸要图标 / 强调色 / `onTap`）。
  final Map<String, HomeServiceEntry> entriesByTitle;

  /// 拖动中（抬起）→ 画投影。
  final bool lifted;

  /// 画格与格之间的分隔短线（默认**不画**；拆解模式的分割线由宫格图层负责）。
  final bool showDividers;

  /// 给每张脸套一层（界面层在这里挂长按拖动的手势）。
  final Widget Function(HomeServiceEntry entry, GridCell cell, Widget face)?
  faceWrapper;

  const HomeGridCard({
    super.key,
    required this.tile,
    required this.metrics,
    required this.entriesByTitle,
    this.lifted = false,
    this.showDividers = false,
    this.faceWrapper,
  });

  @override
  Widget build(BuildContext context) {
    final origin = (x: tile.bounds.left, y: tile.bounds.top);
    final path = homeGridShapePath(
      cells: tile.cells,
      origin: origin,
      metrics: metrics,
    );
    final border = appCardBorderSide(Theme.of(context).colorScheme);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: HomeGridShapePainter(
              path: path,
              shapeKey: gridShapeKey(tile.cells),
              fill: appCardColor(context),
              borderColor: border.color,
              borderWidth: border.width,
              dividerColor: border.color,
              dividers: showDividers
                  ? homeGridDividerSegments(
                      cells: tile.cells,
                      origin: origin,
                      metrics: metrics,
                    )
                  : const <(Offset, Offset)>[],
              shadow: lifted,
            ),
          ),
        ),
        Positioned.fill(
          child: ClipPath(
            clipper: HomeGridShapeClipper(path),
            child: Material(
              type: MaterialType.transparency,
              child: Stack(children: _faces(origin)),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _faces(GridCell origin) {
    final out = <Widget>[];
    for (var i = 0; i < tile.cells.length; i++) {
      final entry = entriesByTitle[tile.titles[i]];
      if (entry == null) continue; // 目录里已删掉的入口（正常不该出现）
      final cell = tile.cells[i];
      final offset = metrics.offsetOfCell(cell, origin);
      Widget face = HomeGridTileFace(entry: entry, compact: metrics.compact);
      final wrap = faceWrapper;
      if (wrap != null) face = wrap(entry, cell, face);
      out.add(
        Positioned(
          left: offset.dx,
          top: offset.dy,
          width: metrics.cellWidth,
          height: metrics.cellHeight,
          child: face,
        ),
      );
    }
    return out;
  }
}
