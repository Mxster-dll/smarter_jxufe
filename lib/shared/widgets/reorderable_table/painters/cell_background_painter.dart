// lib/shared/widgets/reorderable_table/painters/cell_background_painter.dart

import 'package:flutter/material.dart';

class CellBackgroundPainter extends CustomPainter {
  final double rowProgress;
  final double colProgress;
  final double cellWidth;
  final double cellHeight;
  final Color highlightColor;
  final Color rowHighlightColor;
  final Color colHighlightColor;
  final Color normalColor;
  final bool isHoveredRow;
  final bool isHoveredColumn;
  final int rowMoveDirection;
  final int colMoveDirection;

  CellBackgroundPainter({
    required this.rowProgress,
    required this.colProgress,
    required this.cellWidth,
    required this.cellHeight,
    required this.highlightColor,
    required this.rowHighlightColor,
    required this.colHighlightColor,
    required this.normalColor,
    required this.isHoveredRow,
    required this.isHoveredColumn,
    required this.rowMoveDirection,
    required this.colMoveDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rowProgress > 0 && colProgress > 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = highlightColor);
      return;
    }

    if (rowProgress > 0) {
      double fillHeight = size.height * rowProgress;
      Paint rowPaint = Paint()..color = rowHighlightColor;

      if (isHoveredRow) {
        if (rowMoveDirection == 1) {
          canvas.drawRect(
            Rect.fromLTWH(0, 0, size.width, fillHeight),
            rowPaint,
          );
          if (fillHeight < size.height) {
            canvas.drawRect(
              Rect.fromLTWH(
                0,
                fillHeight,
                size.width,
                size.height - fillHeight,
              ),
              Paint()..color = normalColor,
            );
          }
        } else if (rowMoveDirection == -1) {
          canvas.drawRect(
            Rect.fromLTWH(0, size.height - fillHeight, size.width, fillHeight),
            rowPaint,
          );
          if (fillHeight < size.height) {
            canvas.drawRect(
              Rect.fromLTWH(0, 0, size.width, size.height - fillHeight),
              Paint()..color = normalColor,
            );
          }
        } else {
          canvas.drawRect(
            Rect.fromLTWH(0, 0, size.width, fillHeight),
            rowPaint,
          );
          if (fillHeight < size.height) {
            canvas.drawRect(
              Rect.fromLTWH(
                0,
                fillHeight,
                size.width,
                size.height - fillHeight,
              ),
              Paint()..color = normalColor,
            );
          }
        }
      } else {
        if (rowMoveDirection == 1) {
          canvas.drawRect(
            Rect.fromLTWH(0, size.height - fillHeight, size.width, fillHeight),
            rowPaint,
          );
          if (fillHeight < size.height) {
            canvas.drawRect(
              Rect.fromLTWH(0, 0, size.width, size.height - fillHeight),
              Paint()..color = normalColor,
            );
          }
        } else if (rowMoveDirection == -1) {
          canvas.drawRect(
            Rect.fromLTWH(0, 0, size.width, fillHeight),
            rowPaint,
          );
          if (fillHeight < size.height) {
            canvas.drawRect(
              Rect.fromLTWH(
                0,
                fillHeight,
                size.width,
                size.height - fillHeight,
              ),
              Paint()..color = normalColor,
            );
          }
        } else {
          canvas.drawRect(
            Rect.fromLTWH(0, 0, size.width, fillHeight),
            rowPaint,
          );
          if (fillHeight < size.height) {
            canvas.drawRect(
              Rect.fromLTWH(
                0,
                fillHeight,
                size.width,
                size.height - fillHeight,
              ),
              Paint()..color = normalColor,
            );
          }
        }
      }
      return;
    }

    if (colProgress > 0) {
      double fillWidth = size.width * colProgress;
      Paint colPaint = Paint()..color = colHighlightColor;

      if (isHoveredColumn) {
        if (colMoveDirection == 1) {
          canvas.drawRect(
            Rect.fromLTWH(0, 0, fillWidth, size.height),
            colPaint,
          );
          if (fillWidth < size.width) {
            canvas.drawRect(
              Rect.fromLTWH(fillWidth, 0, size.width - fillWidth, size.height),
              Paint()..color = normalColor,
            );
          }
        } else if (colMoveDirection == -1) {
          canvas.drawRect(
            Rect.fromLTWH(size.width - fillWidth, 0, fillWidth, size.height),
            colPaint,
          );
          if (fillWidth < size.width) {
            canvas.drawRect(
              Rect.fromLTWH(0, 0, size.width - fillWidth, size.height),
              Paint()..color = normalColor,
            );
          }
        } else {
          canvas.drawRect(
            Rect.fromLTWH(size.width - fillWidth, 0, fillWidth, size.height),
            colPaint,
          );
          if (fillWidth < size.width) {
            canvas.drawRect(
              Rect.fromLTWH(0, 0, size.width - fillWidth, size.height),
              Paint()..color = normalColor,
            );
          }
        }
      } else {
        if (colMoveDirection == 1) {
          canvas.drawRect(
            Rect.fromLTWH(size.width - fillWidth, 0, fillWidth, size.height),
            colPaint,
          );
          if (fillWidth < size.width) {
            canvas.drawRect(
              Rect.fromLTWH(0, 0, size.width - fillWidth, size.height),
              Paint()..color = normalColor,
            );
          }
        } else if (colMoveDirection == -1) {
          canvas.drawRect(
            Rect.fromLTWH(0, 0, fillWidth, size.height),
            colPaint,
          );
          if (fillWidth < size.width) {
            canvas.drawRect(
              Rect.fromLTWH(fillWidth, 0, size.width - fillWidth, size.height),
              Paint()..color = normalColor,
            );
          }
        } else {
          canvas.drawRect(
            Rect.fromLTWH(0, 0, fillWidth, size.height),
            colPaint,
          );
          if (fillWidth < size.width) {
            canvas.drawRect(
              Rect.fromLTWH(fillWidth, 0, size.width - fillWidth, size.height),
              Paint()..color = normalColor,
            );
          }
        }
      }
      return;
    }

    canvas.drawRect(Offset.zero & size, Paint()..color = normalColor);
  }

  @override
  bool shouldRepaint(covariant CellBackgroundPainter oldDelegate) {
    return oldDelegate.rowProgress != rowProgress ||
        oldDelegate.colProgress != colProgress ||
        oldDelegate.cellWidth != cellWidth ||
        oldDelegate.cellHeight != cellHeight ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.rowHighlightColor != rowHighlightColor ||
        oldDelegate.colHighlightColor != colHighlightColor ||
        oldDelegate.normalColor != normalColor ||
        oldDelegate.isHoveredRow != isHoveredRow ||
        oldDelegate.isHoveredColumn != isHoveredColumn ||
        oldDelegate.rowMoveDirection != rowMoveDirection ||
        oldDelegate.colMoveDirection != colMoveDirection;
  }
}
