/// 虚线边框 Decoration（2026-09-20 从 `grades_screen.dart` 外提 · 架构审查 ⑥）。
///
/// 只被 `GradesSummaryCard` 的「重修补考」分数格使用：`Container.foregroundDecoration`。
library;

import 'package:flutter/material.dart';

/// 虚线边框 Decoration，用于 Container.foregroundDecoration。
class DashedBorderDecoration extends Decoration {
  final Color color;
  final double strokeWidth;
  final double radius;

  const DashedBorderDecoration({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _DashedBoxPainter(color, strokeWidth, radius, onChanged);
  }
}


class _DashedBoxPainter extends BoxPainter {
  final Color color;
  final double strokeWidth;
  final double radius;

  _DashedBoxPainter(this.color, this.strokeWidth, this.radius, super.onChanged);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final rect = offset & cfg.size!;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + 6).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 4;
      }
    }
  }
}
