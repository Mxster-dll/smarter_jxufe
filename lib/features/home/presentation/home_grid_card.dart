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
/// ⚠ 手势分区（用户 2026-09-21 六轮：「功能的点击区不要太大，不然就很难移动整个卡片」）：
/// 每格只有**内容块**（[homeGridFaceContentPadding] 圈出来的那块）是「抓这一个功能」的
/// 区域，格子减去内容块的那一圈 + 格与格之间的缝都算「卡片其余部分」（抓整张卡）。
/// 两条手势都由界面层挂在 [faceWrapper] 里（脸的视觉与轻点区照旧占满整格），本文件只管几何。
///
/// ⚠ 格与格之间**默认不画分隔线**（用户 2026-09-21 四轮：「我希望功能与功能之间不显示
/// 分割线」）—— [HomeGridCard.showDividers] 只在需要时打开；编辑模式下的分割线由
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

/// 功能脸的悬停提示：鼠标**停留这么久之后**才显示（用户 2026-09-21 十轮：
/// 「不要功能的悬停显示不要立刻显示，只有鼠标停留一会后才显示」）。
///
/// 传给 [Tooltip.waitDuration] —— 框架只在「鼠标进入悬停」那一刻读一次这个值
/// （`tooltip.dart` 的 `_handleMouseEnter` → `_scheduleShowTooltip(withDelay: _waitDuration)`），
/// 所以它必须与 [kHomeGridTooltipSuppressed] 一起用：按下 / 拖动中进悬停时读到的是后者。
const Duration kHomeGridTooltipWait = Duration(milliseconds: 600);

/// 「按着东西 / 正拖着东西」时给 [Tooltip.waitDuration] 的值 = **等于不显示**。
///
/// 用户 2026-09-21 十轮：「如果是鼠标按下的状态，则不显示」。
/// 为什么不是「把 Tooltip 从树里摘掉」：摘掉会让 `Tooltip` 与脸之间的父子结构变化，
/// 脸的 `InkWell`（它才是「轻点打开功能」的识别器）会随 Element 一起重建 —— 按下过程中
/// 重建等于把这次点击丢掉（本模块踩过三次手势识别器被 dispose 的坑）。
/// 改 `waitDuration` 只是**属性**变化，树形不变、Element 复用，脸与识别器都还在。
/// 已有的那份提示也不会赖着：任何 `PointerDownEvent` 都会让框架把它收掉
/// （`tooltip.dart` 的 `_handleGlobalPointerEvent` → `_handleTapToDismiss`）。
const Duration kHomeGridTooltipSuppressed = Duration(days: 1);

/// 虚线轮廓的步长 / 间隔 —— 与编辑模式里「断开的那条缝」同口径（5 / 4）。
///
/// 用户 2026-09-21 十一轮：卡片形状也可以是**临时**的 —— 拆出来的碎块、以及拖功能时
/// 源卡片「放回来还是这个形状」的原位预览。临时形状一律画成主题红虚线轮廓，
/// 与实心的「确定形状」区分开。
const double kHomeGridDashedBorderDash = 5;
const double kHomeGridDashedBorderGap = 4;

/// 把 [path] 按虚线描边 —— [HomeGridDashedPainter] 与卡片的虚线轮廓共用这一个画笔口径。
///
/// [dash] 取一个大过路径周长的值、[dashGap] 取 0 就是实线（界面上「实线 / 虚线」两档
/// 因此不需要第二个画笔：分割线、落点预览、被推开的卡片预览都这么用）。
void paintDashedPath(
  Canvas canvas,
  Path path,
  Paint paint, {
  double dash = 5,
  double dashGap = 4,
}) {
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + dash, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + dashGap;
    }
  }
}

/// 磁贴「内容块」的内边距 —— **宽屏 / 紧凑两档的唯一出处**。
///
/// 内容块 = 图标 + 标题 + 副标题那一块（脸自己 padding 出来的区域）。
/// 界面层拿它算两件事（用户 2026-09-21 六轮：「我们希望每个卡片内，功能的点击区不要
/// 太大，不然就很难移动整个卡片」）：
/// - **功能自己的长按抓取区** = 这一块（长按 → 只拖这一个功能）；
/// - **卡片其余部分** = 格子减去这一块的那一圈 + 格与格之间的缝（长按 → 拖整张卡）。
///
/// ⚠ 必须与 [HomeGridTileFace] 里真正用的 `Padding` 是同一份 —— 否则「看得见的功能」
///   与「抓得住的功能」会差一条边（改脸的内边距时这里要跟着走，两处都引用本函数）。
EdgeInsets homeGridFaceContentPadding({required bool compact}) => compact
    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 14)
    : const EdgeInsets.all(16);

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

  /// 轮廓画成虚线（临时形状，见 [kHomeGridDashedBorderDash]）。
  final bool dashed;

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
    this.dashed = false,
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
      final paint = Paint()
        ..color = borderColor
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth;
      if (dashed) {
        paint.strokeCap = StrokeCap.round;
        paintDashedPath(
          canvas,
          path,
          paint,
          dash: kHomeGridDashedBorderDash,
          dashGap: kHomeGridDashedBorderGap,
        );
      } else {
        canvas.drawPath(path, paint);
      }
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
      old.dashed != dashed ||
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
    paintDashedPath(canvas, path, paint, dash: dash, dashGap: dashGap);
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

  /// 是否允许悬停提示（副标题全文）。
  ///
  /// `false` = 手上按着 / 正拖着东西（用户 2026-09-21 十轮：「如果是鼠标按下的状态，
  /// 则不显示」）→ [Tooltip.waitDuration] 取 [kHomeGridTooltipSuppressed]（等于不显示）。
  final bool showTooltip;

  const HomeGridTileFace({
    super.key,
    required this.entry,
    required this.compact,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = entry.accent;
    // ⚠ `triggerMode: manual`：Tooltip 默认在触摸端**长按**弹出，而长按现在是
    // 「抬起宫格开始拖动」的手势（用户 2026-09-21 需求）—— 两个 LongPress 识别器
    // 会抢同一个手势，Tooltip 在树里更深、先入 arena，实测拖动永远起不来。
    // 桌面端悬停照旧能看全文；触摸端由拖动优先（副标题本身最多 2 行）。
    // ⚠ `waitDuration`：默认是 `Duration.zero`（一碰就弹），用户 2026-09-21 十轮要求
    // 「停留一会才显示」+「按下的状态不显示」→ 取 [kHomeGridTooltipWait] /
    // [kHomeGridTooltipSuppressed]（见两个常量的文档；改的是属性不是树形）。
    return Tooltip(
      message: entry.subtitle,
      triggerMode: TooltipTriggerMode.manual,
      waitDuration:
          showTooltip ? kHomeGridTooltipWait : kHomeGridTooltipSuppressed,
      child: InkWell(
        key: Key('homeTile-${entry.title}'),
        onTap: entry.onTap,
        hoverColor: accent.withValues(alpha: 0.05),
        child: compact
            ? Padding(
                padding: homeGridFaceContentPadding(compact: true),
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
                padding: homeGridFaceContentPadding(compact: false),
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

  /// 画格与格之间的分隔短线（默认**不画**；编辑模式的分割线由宫格图层负责）。
  final bool showDividers;

  /// 这几格**不画面**（只剩卡片底色的一块空位）。
  ///
  /// 用户 2026-09-21 十轮：「我希望长按组合卡片的某一个功能时，此时原位置卡片的此功能
  /// 不显示，而是只显示被我拖动的状态」→ 拖单格时界面层把「被抠出来的那一格」传进来，
  /// 源卡片就地留一个空位（卡片形状 / 底色不动，别处不受影响）。
  ///
  /// ⚠ 只换 [[faceWrapper]] 收到的那个 `face`，**不动**外层的 `IgnorePointer` 与两条
  ///   手势带 —— 拖动的识别器就挂在手势带上，跟着脸一起重建的话拖动会断在半路
  ///   （本模块踩过三次）。
  final Set<GridCell> blankCells;

  /// 是否允许脸显示悬停提示（拖动中 / 按下时关掉，见 [HomeGridTileFace.showTooltip]）。
  final bool showTooltip;

  /// 画**轮廓 / 底色 / 分隔线**用的格子集合（null = 就用 [HomeGridTile.tile] 自己的格子）。
  ///
  /// 用户 2026-09-21 十一轮：「不只是功能不显示，而是卡片形状也要改变……如果在其他位置，
  /// 原卡片直接显示去除此功能的形状」→ 拖功能时界面层把「源卡片剩下的格子」传进来，
  /// 卡片**轮廓真的缩小一格**（不再是「同一块底上留个空位」）。
  ///
  /// ⚠ 脸的铺排（[_faces]）与两条手势带照旧按 [HomeGridTile.tile] 的格子走 —— 元素不重建，
  ///   拖动识别器才不会随 Element 一起 dispose（本模块踩过三次）。多出来的那格被
  ///   [HomeGridShapeClipper] 裁掉，看不见也点不到。
  final Set<GridCell>? skinCells;

  /// 轮廓画成**主题红虚线 + 淡淡一层底**（临时形状，见 [kHomeGridDashedBorderDash]）。
  ///
  /// 两种情形（用户 2026-09-21 十一轮）：
  /// - 拖功能时那个功能**还压在自己的原格子上** → 源卡片画「原来完整轮廓」的虚线
  ///   （「就像是其余部分将要添加当前拖动的一样」= 放回来还是这个形状）；
  /// - 编辑模式里点分割线**真的把卡片分开** → 拆出来的每一块画虚线，与实心的
  ///   「确定形状」区分开（点缝之后卡片立刻分成两块，白卡白底时只有这圈虚线看得出来）。
  final bool dashedOutline;

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
    this.blankCells = const <GridCell>{},
    this.showTooltip = true,
    this.skinCells,
    this.dashedOutline = false,
    this.faceWrapper,
  });

  @override
  Widget build(BuildContext context) {
    final origin = (x: tile.bounds.left, y: tile.bounds.top);
    final skin = skinCells ?? gridCellSet(tile.cells);
    final path = homeGridShapePath(
      cells: skin,
      origin: origin,
      metrics: metrics,
    );
    final scheme = Theme.of(context).colorScheme;
    final border = appCardBorderSide(scheme);
    final accent = appCardAccent(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: HomeGridShapePainter(
              path: path,
              // 形状指纹要把「画轮廓的格子」一起算进去：光看 tile.cells 时抽掉一格
              // 不会触发重绘（`Path` 没有值相等）。
              shapeKey: '${gridShapeKey(tile.cells)}|${gridShapeKey(skin)}',
              fill: dashedOutline
                  ? AppColors.tint(context, accent, 0.06)
                  : appCardColor(context),
              borderColor: dashedOutline ? accent : border.color,
              borderWidth: dashedOutline ? 1.6 : border.width,
              dividerColor: border.color,
              dividers: showDividers
                  ? homeGridDividerSegments(
                      cells: skin,
                      origin: origin,
                      metrics: metrics,
                    )
                  : const <(Offset, Offset)>[],
              dashed: dashedOutline,
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
      // 被抠走的那一格：脸留空（用户 2026-09-21 十轮），手势带照旧（见 [blankCells]）。
      Widget face = blankCells.contains(cell)
          ? const SizedBox.expand()
          : HomeGridTileFace(
              entry: entry,
              compact: metrics.compact,
              showTooltip: showTooltip,
            );
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
