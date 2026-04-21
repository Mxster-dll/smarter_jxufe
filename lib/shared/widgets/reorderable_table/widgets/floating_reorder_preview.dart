import 'package:flutter/material.dart';

import 'package:smarter_jxufe/shared/widgets/reorderable_table/reorderable_table.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/collapse_controller.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/reorder_controller.dart';

class FloatingReorderPreview extends StatelessWidget {
  final ReorderController reorderCtrl;
  final CollapseController collapseCtrl;
  final List<String> defaultRowHeaders;
  final List<String> defaultColHeaders;
  final List<List<Widget>> cells;
  final Color rowHeaderHighlight;
  final Color colHeaderHighlight;
  final Color cellRowHighlight;
  final Color cellColHighlight;

  const FloatingReorderPreview({
    super.key,
    required this.reorderCtrl,
    required this.collapseCtrl,
    required this.defaultRowHeaders,
    required this.defaultColHeaders,
    required this.cells,
    required this.rowHeaderHighlight,
    required this.colHeaderHighlight,
    required this.cellRowHighlight,
    required this.cellColHighlight,
  });

  Offset _computeTopLeft() {
    if (reorderCtrl.isReturning && reorderCtrl.returnAnim != null) {
      return reorderCtrl.returnAnim!.value;
    }
    Offset raw = reorderCtrl.dragPointerLocalPosition - reorderCtrl.dragOffset;
    final box =
        reorderCtrl.tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      final size = box.size;
      if (reorderCtrl.dragType == DragType.row) {
        return Offset(
          0,
          raw.dy.clamp(
            reorderCtrl.cornerHeight,
            size.height - reorderCtrl.cellHeight,
          ),
        );
      } else {
        return Offset(
          raw.dx.clamp(
            reorderCtrl.cornerWidth,
            size.width - reorderCtrl.cellWidth,
          ),
          0,
        );
      }
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final widget = collapseCtrl.widget;
    final dragType = reorderCtrl.dragType!;
    final originalIdx = reorderCtrl.dragOriginalIndex;
    final topLeft = _computeTopLeft();

    final tableWidth =
        widget.cellWidth + reorderCtrl.colOrder.length * widget.cellWidth;
    final tableHeight =
        widget.cellHeight + reorderCtrl.rowOrder.length * widget.cellHeight;

    final useRowRoundCorners =
        widget.enableRowHeaderCollapse && widget.rowHeadersCollapsed;
    final useColRoundCorners =
        widget.enableColHeaderCollapse && widget.colHeadersCollapsed;

    return AnimatedBuilder(
      animation: reorderCtrl.highlightAnimation,
      builder: (context, child) {
        final elevation = 2 + reorderCtrl.highlightAnimation.value * 10;

        if (dragType == DragType.column) {
          final columnHeight =
              widget.cellHeight +
              reorderCtrl.rowOrder.length * widget.cellHeight;
          final List<Widget> columnCells = [
            if (widget.showColHeaders)
              Container(
                width: widget.cellWidth,
                height: widget.cellHeight,
                decoration: BoxDecoration(
                  color: colHeaderHighlight,
                  borderRadius: useColRoundCorners
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.colHeaders?[originalIdx] ??
                      defaultColHeaders[originalIdx],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ...List.generate(reorderCtrl.rowOrder.length, (i) {
              final originalRow = reorderCtrl.rowOrder[i];
              return Container(
                width: widget.cellWidth,
                height: widget.cellHeight,
                color: cellColHighlight,
                child: cells[originalRow][originalIdx],
              );
            }),
          ];

          return Positioned(
            left: topLeft.dx,
            top: tableHeight - columnHeight,
            width: widget.cellWidth,
            height: columnHeight,
            child: Material(
              elevation: elevation,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: columnCells,
              ),
            ),
          );
        } else {
          final rowWidth =
              widget.cellWidth + reorderCtrl.colOrder.length * widget.cellWidth;
          final List<Widget> rowCells = [
            if (widget.showRowHeaders)
              Container(
                width: widget.cellWidth,
                height: widget.cellHeight,
                decoration: BoxDecoration(
                  color: rowHeaderHighlight,
                  borderRadius: useRowRoundCorners
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.rowHeaders?[originalIdx] ??
                      defaultRowHeaders[originalIdx],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ...List.generate(reorderCtrl.colOrder.length, (i) {
              final originalCol = reorderCtrl.colOrder[i];
              return Container(
                width: widget.cellWidth,
                height: widget.cellHeight,
                color: cellRowHighlight,
                child: cells[originalIdx][originalCol],
              );
            }),
          ];

          return Positioned(
            left: tableWidth - rowWidth,
            top: topLeft.dy,
            width: rowWidth,
            height: widget.cellHeight,
            child: Material(
              elevation: elevation,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: rowCells),
            ),
          );
        }
      },
    );
  }
}
