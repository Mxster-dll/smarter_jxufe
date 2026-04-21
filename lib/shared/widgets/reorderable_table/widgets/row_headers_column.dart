import 'package:flutter/material.dart';

import 'package:smarter_jxufe/shared/widgets/reorderable_table/reorderable_table.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/collapse_controller.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/reorder_controller.dart';

class RowHeadersColumn extends StatelessWidget {
  final CollapseController collapseCtrl;
  final ReorderController reorderCtrl;
  final List<GlobalKey> rowHeaderKeys;
  final List<String> defaultRowHeaders;
  final Color rowHeaderNormal;
  final Color rowHeaderHighlight;

  const RowHeadersColumn({
    super.key,
    required this.collapseCtrl,
    required this.reorderCtrl,
    required this.rowHeaderKeys,
    required this.defaultRowHeaders,
    required this.rowHeaderNormal,
    required this.rowHeaderHighlight,
  });

  @override
  Widget build(BuildContext context) {
    final widget = collapseCtrl.widget;
    if (!widget.showRowHeaders) return const SizedBox.shrink();

    final useRoundCorners =
        widget.enableRowHeaderCollapse && widget.rowHeadersCollapsed;
    final isDragging = reorderCtrl.isDragging;
    final dragType = reorderCtrl.dragType;

    return Stack(
      children: List.generate(reorderCtrl.rowOrder.length, (logicIdx) {
        final originalRow = reorderCtrl.rowOrder[logicIdx];
        int screenIdx = logicIdx;
        if (isDragging && dragType == DragType.row) {
          screenIdx = logicIdx < reorderCtrl.targetLogicalIndex
              ? logicIdx
              : logicIdx + 1;
        }
        final width = collapseCtrl.rowHeaderWidth(logicIdx);
        final left = widget.cellWidth - width;

        return AnimatedPositioned(
          key: isDragging
              ? ValueKey('row-regular-$originalRow')
              : (rowHeaderKeys.isNotEmpty ? rowHeaderKeys[logicIdx] : null),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          left: left,
          top: widget.cellHeight + screenIdx * widget.cellHeight,
          width: width,
          height: widget.cellHeight,
          child: GestureDetector(
            onLongPressStart: (details) =>
                reorderCtrl.startDrag(DragType.row, logicIdx, details),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: isDragging
                    ? rowHeaderNormal
                    : (collapseCtrl.hoveredRow == logicIdx
                          ? rowHeaderHighlight
                          : rowHeaderNormal),
                borderRadius: useRoundCorners
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomLeft: Radius.circular(8),
                      )
                    : null,
              ),
              child: AnimatedOpacity(
                opacity: width == widget.cellWidth ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Center(
                  child: Text(
                    widget.rowHeaders?[originalRow] ??
                        defaultRowHeaders[originalRow],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
