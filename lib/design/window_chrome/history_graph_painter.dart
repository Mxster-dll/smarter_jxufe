// 本文件是 `lib/design/window_chrome/` 拆分件之一 —— 文件地图见 docs/agents/43 的 §43.5。
// 公开入口仍是 `package:smarter_jxufe/design/window_title_bar.dart`（桶文件，对外零改动）。
import 'package:flutter/material.dart';

class HistoryGraphPainter extends CustomPainter {
  const HistoryGraphPainter({
    required this.index,
    required this.current,
    required this.total,
    required this.lane,
    required this.active,
    required this.isForwardTarget,
    required this.activePath,
    required this.parentIndex,
    required this.parentLane,
    required this.activeColor,
    required this.idleColor,
    required this.dimColor,
  });

  final int index;
  final int current;
  final int total;

  /// 本笔的泳道（0 = 主干）。
  final int lane;

  /// 本笔是否在「根 → 游标」那条祖先链上（**亮不亮就看它**，别看列表下标）。
  final bool active;

  /// 是不是「前进」会去的那一笔（分叉后标出来）。
  final bool isForwardTarget;

  /// 整条祖先链（判断父节点亮不亮要用）。
  final Set<int> activePath;

  /// 父节点在列表里的下标（-1 = 没有父）。
  final int parentIndex;
  final int parentLane;

  final Color activeColor;
  final Color idleColor;
  final Color dimColor;

  static const double _rowHeight = 30;
  static const double _laneStep = 14;

  double _x(int lane) => 8 + lane * _laneStep;

  @override
  void paint(Canvas canvas, Size size) {
    final node = Offset(_x(lane), size.height / 2);
    final isCurrent = index == current;

    // 连到父节点那一段（跨泳道 = 曲线，见下）。
    if (parentIndex >= 0) {
      final parentY = node.dy - (index - parentIndex) * _rowHeight;
      final parent = Offset(_x(parentLane), parentY);
      final parentActive = activePath.contains(parentIndex);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        // 一段线只有在**两端都在祖先链上**时才算「走过的路」（其余是另一条分支 / 尾巴）。
        ..color = (active && parentActive)
            ? activeColor.withValues(alpha: 0.85)
            : idleColor;
      if (parentLane == lane) {
        canvas.drawLine(node, parent, paint);
      } else {
        // 分叉**不画直斜线**（用户 2026-10-09）——三次贝塞尔：两端各留一半做
        // 「先竖后弯 / 先弯后竖」，是从主干弯出去的一条弧，控制点只在 y 上偏移，
        // 所以不会横向甩出去。
        final dy = node.dy - parent.dy;
        canvas.drawPath(
          Path()
            ..moveTo(node.dx, node.dy)
            ..cubicTo(node.dx, node.dy - dy * 0.5, parent.dx,
                parent.dy + dy * 0.5, parent.dx, parent.dy),
          paint,
        );
      }
    }

    // 节点：当前 = 实心大点 + 外圈；走过的 = 实心小点；其余（另一支 / 还没前进回去
    // 的尾巴）= 空心点。
    if (isCurrent) {
      canvas.drawCircle(node, 6.5, Paint()..color = activeColor);
      canvas.drawCircle(
        node,
        6.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = activeColor.withValues(alpha: 0.35),
      );
    } else if (active) {
      canvas.drawCircle(node, 4.5, Paint()..color = activeColor);
    } else {
      canvas.drawCircle(
        node,
        4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = isForwardTarget ? activeColor : dimColor,
      );
    }
    // 「前进」的目标额外套一圈 —— 分叉之后点前进会走这一支，得让人看出来。
    if (isForwardTarget && !isCurrent) {
      canvas.drawCircle(
        node,
        7.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = activeColor.withValues(alpha: 0.7),
      );
    }
    assert(total >= 0);
  }

  @override
  bool shouldRepaint(HistoryGraphPainter old) =>
      old.index != index ||
      old.current != current ||
      old.total != total ||
      old.lane != lane ||
      old.active != active ||
      old.isForwardTarget != isForwardTarget ||
      old.parentIndex != parentIndex ||
      old.parentLane != parentLane ||
      old.activeColor != activeColor;
}
