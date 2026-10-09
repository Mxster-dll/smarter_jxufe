/// 首页宫格 · 缝线预览与形状预览（只收显式参数的渲染件）（顶层函数）。
///
/// 拆分自 `home_service_grid.dart`（2026-10-08 架构审计第三轮 · 通用拆分器 `.scratch/split_extract.py`）：
/// 这里只放**不碰字段 / `widget` / `setState`** 的一层；`BuildContext` 本来就是显式参数的
/// 渲染件也在此列。留在原类的是读字段的那批，正文字号 / 全局 key 之类要么收显式参数、
/// 要么留在 State（口径见 AGENTS.md §33.4.4）。
library;

import '../home_service_grid.dart';
import 'package:flutter/material.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_layout.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_split.dart';
import 'package:smarter_jxufe/features/home/presentation/home_grid_card.dart';
import 'package:smarter_jxufe/features/home/presentation/home_grid_metrics.dart';

/// 布局里每一条缝 + 它所属的卡（分割线图层与整卡拖动手势带共用）。
List<({HomeGridTile tile, GridSeam seam})> hgTileSeams(HomeGridLayout layout) => [
  for (final t in layout.tiles)
    for (final s in gridSeamsOf(t.cells)) (tile: t, seam: s),
];

/// 缝的命中带：缝本身只有 12px 宽，向两侧各外扩 [kHomeGridSeamHitPad]。
Rect hgSeamBand(GridSeam seam, HomeGridMetrics metrics) {
  const pad = kHomeGridSeamHitPad;
  const gap = HomeGridMetrics.gap;
  if (seam.a.x != seam.b.x) {
    // 竖缝（左右相邻）：a 在左。
    final x = seam.a.x * metrics.pitchX + metrics.cellWidth + gap / 2;
    final top = seam.a.y * metrics.pitchY;
    return Rect.fromLTRB(
      x - gap / 2 - pad,
      top,
      x + gap / 2 + pad,
      top + metrics.cellHeight,
    );
  }
  final y = seam.a.y * metrics.pitchY + metrics.cellHeight + gap / 2;
  final left = seam.a.x * metrics.pitchX;
  return Rect.fromLTRB(
    left,
    y - gap / 2 - pad,
    left + metrics.cellWidth,
    y + gap / 2 + pad,
  );
}

/// 缝的那条线（网格坐标）：竖缝取缝正中一条竖线，横缝同理；[inset] = 两端缩进
/// （分割线风格 12；断开后通长 0）。
(Offset, Offset) hgSeamLine(
  GridSeam seam,
  HomeGridMetrics metrics,
  double inset,
) {
  const gap = HomeGridMetrics.gap;
  if (seam.a.x != seam.b.x) {
    final x = seam.a.x * metrics.pitchX + metrics.cellWidth + gap / 2;
    final top = seam.a.y * metrics.pitchY;
    return (
      Offset(x, top + inset),
      Offset(x, top + metrics.cellHeight - inset),
    );
  }
  final y = seam.a.y * metrics.pitchY + metrics.cellHeight + gap / 2;
  final left = seam.a.x * metrics.pitchX;
  return (
    Offset(left + inset, y),
    Offset(left + metrics.cellWidth - inset, y),
  );
}

/// 虚线框：**合并后的整张卡**画虚线轮廓（不是贴在旁边的一个独立方框 ——
/// 用户 2026-09-21 二轮：「虚线框要与将要连接的卡片**相连**，展示合并后的卡片形状」），
/// 参与合并的每张卡各淡染一层。
List<Widget> hgPreview(
  HomeGridDropTarget plan,
  HomeGridMetrics metrics,
  BuildContext context,
) {
  final accent = appCardAccent(context);
  final out = <Widget>[];
  final merged = plan.mergedResult;
  var index = 0;
  for (final tier in plan.joined) {
    out.add(
      hgShapePreview(
        // 第一张沿用老 key（守卫与用例都在找它），其余按卡片 key 区分。
        key: index == 0
            ? const Key('homeGridPreviewTarget')
            : Key('homeGridPreviewTarget-${tier.key}'),
        tile: tier,
        metrics: metrics,
        path: homeGridShapePath(
          cells: tier.cells,
          origin: (x: tier.bounds.left, y: tier.bounds.top),
          metrics: metrics,
        ),
        color: accent.withValues(alpha: 0.55),
        fill: AppColors.tint(context, accent, 0.06),
        strokeWidth: 1.2,
        dash: 5,
        dashGap: 4,
      ),
    );
    index++;
  }
  final landing = merged ?? plan.landing;
  // 被**推开**（但不并入）的卡片：在它们的新位置上画一圈细实线 ——
  // 合并会把后续卡片往后顶一位，不提前画出来的话松手后那一跳会很突然。
  for (final pushed in plan.pushed.values) {
    out.add(
      hgShapePreview(
        key: Key('homeGridPreviewPush-${pushed.key}'),
        tile: pushed,
        metrics: metrics,
        path: homeGridShapePath(
          cells: pushed.cells,
          origin: (x: pushed.bounds.left, y: pushed.bounds.top),
          metrics: metrics,
        ),
        color: AppColors.textMuted(context),
        fill: AppColors.tint(context, accent, 0.03),
        strokeWidth: 1,
        dash: 1e6, // 一整段 = 实线（同一个画笔，不再引第二个 painter）
        dashGap: 0,
      ),
    );
  }
  out.add(
    hgShapePreview(
      key: const Key('homeGridPreview'),
      tile: landing,
      metrics: metrics,
      path: homeGridShapePath(
        cells: landing.cells,
        origin: (x: landing.bounds.left, y: landing.bounds.top),
        metrics: metrics,
      ),
      color: accent,
      fill: AppColors.tint(context, accent, 0.10),
    ),
  );
  return out;
}

Widget hgShapePreview({
  required Key key,
  required HomeGridTile tile,
  required HomeGridMetrics metrics,
  required Path path,
  required Color color,
  required Color fill,
  double strokeWidth = 1.6,
  double dash = 7,
  double dashGap = 5,
}) {
  final topLeft = metrics.topLeftOfTile(tile);
  final size = metrics.sizeOfTile(tile);
  return Positioned(
    left: topLeft.dx,
    top: topLeft.dy,
    width: size.width,
    height: size.height,
    child: IgnorePointer(
      child: CustomPaint(
        key: key,
        painter: HomeGridDashedPainter(
          path: path,
          color: color,
          fill: fill,
          strokeWidth: strokeWidth,
          dash: dash,
          dashGap: dashGap,
        ),
      ),
    ),
  );
}
