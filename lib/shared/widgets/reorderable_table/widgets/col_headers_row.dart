// lib/shared/widgets/reorderable_table/widgets/col_headers_row.dart

import 'package:flutter/material.dart';
import 'package:smarter_jxufe/shared/gestures/custom_long_press_recognizer.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/reorderable_table.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/collapse_controller.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/reorder_controller.dart';

class ColHeadersRow extends StatelessWidget {
  final CollapseController collapseCtrl;
  final ReorderController reorderCtrl;
  final List<GlobalKey> colHeaderKeys;
  final List<String> defaultColHeaders;
  final Color colHeaderNormal;
  final Color colHeaderHighlight;

  const ColHeadersRow({
    super.key,
    required this.collapseCtrl,
    required this.reorderCtrl,
    required this.colHeaderKeys,
    required this.defaultColHeaders,
    required this.colHeaderNormal,
    required this.colHeaderHighlight,
  });

  @override
  Widget build(BuildContext context) {
    final widget = collapseCtrl.widget;
    if (!widget.showColHeaders) return const SizedBox.shrink();

    final useRoundCorners =
        widget.enableColHeaderCollapse && widget.colHeadersCollapsed;
    final isDragging = reorderCtrl.isDragging;
    final dragType = reorderCtrl.dragType;

    return Stack(
      children: List.generate(reorderCtrl.colOrder.length, (logicIdx) {
        final originalCol = reorderCtrl.colOrder[logicIdx];
        int screenIdx = logicIdx;
        if (isDragging && dragType == DragType.column) {
          screenIdx = logicIdx < reorderCtrl.targetLogicalIndex
              ? logicIdx
              : logicIdx + 1;
        }
        final height = collapseCtrl.colHeaderHeight(logicIdx);
        final top = widget.cellHeight - height;

        return AnimatedPositioned(
          key: isDragging
              ? ValueKey('col-regular-$originalCol')
              : (colHeaderKeys.isNotEmpty ? colHeaderKeys[logicIdx] : null),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          left: widget.cellWidth + screenIdx * widget.cellWidth,
          top: top,
          width: widget.cellWidth,
          height: height,
          child: RawGestureDetector(
            gestures: {
              CustomLongPressRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    CustomLongPressRecognizer
                  >(
                    () => CustomLongPressRecognizer(
                      duration: const Duration(milliseconds: 200),
                    ),
                    (instance) {
                      instance.onLongPressStart = (details) => reorderCtrl
                          .startDrag(DragType.column, logicIdx, details);
                    },
                  ),
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: isDragging
                    ? colHeaderNormal
                    : (collapseCtrl.hoveredCol == logicIdx
                          ? colHeaderHighlight
                          : colHeaderNormal),
                borderRadius: useRoundCorners
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      )
                    : null,
              ),
              child: AnimatedOpacity(
                opacity: height == widget.cellHeight ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Center(
                  child: Text(
                    widget.colHeaders?[originalCol] ??
                        defaultColHeaders[originalCol],
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
