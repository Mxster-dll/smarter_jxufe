/// 宫格几何：列数 / 格宽 / 格高 / 格子 ↔ 像素换算的**唯一出处**。
///
/// 重构前这些数字散在 `HomeServiceGrid.build` 里（`cols` / `width` 的算法与几个
/// `static const` 常量）；聚合功能需要「格子 → 像素矩形」的双向换算（拖动命中、
/// 虚线框落点、异形路径），所以抽成一份可测的纯数据。
///
/// ⚠ 列数与格宽的算法**逐字沿用**重构前的实现（`test/home_service_grid_test.dart`
/// 的「等宽等高」「窄屏紧凑」两例是它的守卫）：宽屏按 [minCard] 决定列数（上限
/// [maxCols]），窄屏按 [compactExtent] 决定列数（下限 2 列）。
library;

import 'package:flutter/painting.dart';

import 'package:smarter_jxufe/features/home/domain/home_grid_layout.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_shape.dart';

/// 一次布局的几何度量。
class HomeGridMetrics {
  /// 是否紧凑形态（窄屏：图标在上、只留标题）。
  final bool compact;

  /// 列数。
  final int cols;

  /// 单格宽度（像素）。
  final double cellWidth;

  /// 单格高度（像素）。
  final double cellHeight;

  const HomeGridMetrics({
    required this.compact,
    required this.cols,
    required this.cellWidth,
    required this.cellHeight,
  });

  /// 窄屏断点（手机竖屏）：小于它走紧凑磁贴（图标在上、只留标题）。
  static const double compactBreakpoint = 620;

  /// 宽屏磁贴最小宽度（列数 = 可用宽度能摆几个这样的磁贴）。
  static const double minCard = 208;

  /// 磁贴间距（横竖同值）。
  static const double gap = 12;

  /// 紧凑磁贴的目标宽度（等价 `SliverGridDelegateWithMaxCrossAxisExtent` 语义）。
  static const double compactExtent = 108;

  /// 副标题单行高度（与 `TextStyle.height` 口径一致：12 × 16/12）。
  static const double subtitleLineHeight = 16;

  /// 标题单行高度（15 × 20/15）。
  static const double titleLineHeight = 20;

  /// 宽屏磁贴高度 = 内边距 16×2 + 标题 20 + 间距 2 + 副标题 2 行 32（= 86）+
  /// 2px 余量（字体度量取整，实测 2 行正好 32）。
  static const double cardHeight = 88;

  /// 紧凑磁贴高度 = 内边距 14×2 + 图标 42 + 间距 8 + 标题 16（= 94）。
  static const double compactCardHeight = 94;

  /// 宽屏最大列数（再宽也不铺更多列，避免磁贴被拉爆）。
  static const int maxCols = 6;

  /// 按可用宽度算度量。
  static HomeGridMetrics of(double maxWidth) {
    final width = maxWidth.isFinite && maxWidth > 0 ? maxWidth : 0.0;
    final isCompact = width < compactBreakpoint;
    int cols;
    if (isCompact) {
      cols = ((width + gap) / (compactExtent + gap)).ceil();
      if (cols < 2) cols = 2;
    } else {
      cols = (width + gap) ~/ (minCard + gap);
      if (cols < 1) cols = 1;
      if (cols > maxCols) cols = maxCols;
    }
    final cell = (width - gap * (cols - 1)) / cols;
    return HomeGridMetrics(
      compact: isCompact,
      cols: cols,
      cellWidth: cell < 0 ? 0 : cell,
      cellHeight: isCompact ? compactCardHeight : cardHeight,
    );
  }

  /// 列步距（格宽 + 缝）。
  double get pitchX => cellWidth + gap;

  /// 行步距（格高 + 缝）。
  double get pitchY => cellHeight + gap;

  /// 若干行的总高度（最后一行的缝不算）。
  double heightOfRows(int rows) => rows <= 0 ? 0 : rows * pitchY - gap;

  /// 形状包围盒左上角的像素位置。
  Offset topLeftOfBounds(GridBounds b) =>
      b.right < b.left ? Offset.zero : Offset(b.left * pitchX, b.top * pitchY);

  /// 形状包围盒的像素尺寸（空形状 → `Size.zero`）。
  Size sizeOfBounds(GridBounds b) {
    if (b.right < b.left) return Size.zero;
    final w = gridWidthOf(b) * pitchX - gap;
    final h = gridHeightOf(b) * pitchY - gap;
    return Size(w < 0 ? 0 : w, h < 0 ? 0 : h);
  }

  /// 卡片左上角像素位置。
  Offset topLeftOfTile(HomeGridTile tile) => topLeftOfBounds(tile.bounds);

  /// 卡片像素尺寸。
  Size sizeOfTile(HomeGridTile tile) => sizeOfBounds(tile.bounds);

  /// 某个格子相对 [origin] 的像素偏移（画每格内容用）。
  Offset offsetOfCell(GridCell cell, GridCell origin) => Offset(
    (cell.x - origin.x) * pitchX,
    (cell.y - origin.y) * pitchY,
  );

  /// 像素位置落在哪个格子（缝归给左 / 上那个格子）。
  GridCell cellAt(Offset local) {
    if (pitchX <= 0 || pitchY <= 0) return (x: 0, y: 0);
    return (x: (local.dx / pitchX).floor(), y: (local.dy / pitchY).floor());
  }

  /// 像素位置在**自己那个格子内**的比例（0..1）—— 判断「指针是不是贴在卡片边缘」用。
  ({double x, double y}) cellFractionAt(Offset local) {
    final cell = cellAt(local);
    if (cellWidth <= 0 || cellHeight <= 0) return (x: 0.5, y: 0.5);
    final fx = (local.dx - cell.x * pitchX) / cellWidth;
    final fy = (local.dy - cell.y * pitchY) / cellHeight;
    return (
      x: fx < 0 ? 0 : (fx > 1 ? 1 : fx),
      y: fy < 0 ? 0 : (fy > 1 ? 1 : fy),
    );
  }
}
