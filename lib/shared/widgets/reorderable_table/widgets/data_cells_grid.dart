// lib/shared/widgets/reorderable_table/widgets/data_cells_grid.dart

import 'package:flutter/material.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/reorderable_table.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/collapse_controller.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/reorder_controller.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/highlight_animation_controller.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/painters/cell_background_painter.dart';

class DataCellsGrid extends StatelessWidget {
  final CollapseController collapseCtrl;
  final ReorderController reorderCtrl;
  final HighlightAnimationController highlightCtrl;
  final List<List<Widget>> cells;
  final Color cellHighlight;
  final Color cellRowHighlight;
  final Color cellColHighlight;
  final Color cellNormal;

  const DataCellsGrid({
    super.key,
    required this.collapseCtrl,
    required this.reorderCtrl,
    required this.highlightCtrl,
    required this.cells,
    required this.cellHighlight,
    required this.cellRowHighlight,
    required this.cellColHighlight,
    required this.cellNormal,
  });

  @override
  Widget build(BuildContext context) {
    final widget = collapseCtrl.widget;
    final rowOrder = reorderCtrl.rowOrder;
    final colOrder = reorderCtrl.colOrder;
    final isDragging = reorderCtrl.isDragging;
    final dragType = reorderCtrl.dragType;
    final targetIdx = reorderCtrl.targetLogicalIndex;

    final List<Widget> positionedCells = [];
    for (int logicRow = 0; logicRow < rowOrder.length; logicRow++) {
      final originalRow = rowOrder[logicRow];
      int screenRow = logicRow;
      if (isDragging && dragType == DragType.row) {
        screenRow = logicRow < targetIdx ? logicRow : logicRow + 1;
      }

      for (int logicCol = 0; logicCol < colOrder.length; logicCol++) {
        final originalCol = colOrder[logicCol];
        int screenCol = logicCol;
        if (isDragging && dragType == DragType.column) {
          screenCol = logicCol < targetIdx ? logicCol : logicCol + 1;
        }

        positionedCells.add(
          AnimatedPositioned(
            key: ValueKey('data-$originalRow-$originalCol'),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            left: widget.cellWidth + screenCol * widget.cellWidth,
            top: widget.cellHeight + screenRow * widget.cellHeight,
            width: widget.cellWidth,
            height: widget.cellHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final rowProgress =
                    logicRow < highlightCtrl.rowProgresses.length
                    ? highlightCtrl.rowProgresses[logicRow]
                    : 0.0;
                final colProgress =
                    logicCol < highlightCtrl.colProgresses.length
                    ? highlightCtrl.colProgresses[logicCol]
                    : 0.0;

                return CustomPaint(
                  painter: CellBackgroundPainter(
                    rowProgress: rowProgress,
                    colProgress: colProgress,
                    cellWidth: constraints.maxWidth,
                    cellHeight: constraints.maxHeight,
                    highlightColor: cellHighlight,
                    rowHighlightColor: cellRowHighlight,
                    colHighlightColor: cellColHighlight,
                    normalColor: cellNormal,
                    isHoveredRow: collapseCtrl.hoveredRow == logicRow,
                    isHoveredColumn: collapseCtrl.hoveredCol == logicCol,
                    rowMoveDirection: reorderCtrl.lastRowMoveDirection,
                    colMoveDirection: reorderCtrl.lastColMoveDirection,
                  ),
                  child: cells[originalRow][originalCol],
                );
              },
            ),
          ),
        );
      }
    }
    return Stack(children: positionedCells);
  }
}
