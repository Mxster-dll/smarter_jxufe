// lib/shared/widgets/reorderable_table/controllers/reorder_controller.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:smarter_jxufe/shared/gestures/custom_long_press_recognizer.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/reorderable_table.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/collapse_controller.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/highlight_animation_controller.dart';

class ReorderController {
  ReorderableTable widget;
  final CollapseController collapseCtrl;
  final HighlightAnimationController highlightCtrl;
  final GlobalKey tableKey;
  final VoidCallback onStateChanged;

  ReorderController({
    required this.widget,
    required this.collapseCtrl,
    required this.highlightCtrl,
    required this.tableKey,
    required this.onStateChanged,
  }) {
    _initOrders();
  }

  late List<int> rowOrder;
  late List<int> colOrder;

  bool isDragging = false;
  DragType? dragType;
  int dragOriginalIndex = -1;
  int targetLogicalIndex = -1;

  Offset dragOffset = Offset.zero;
  Offset dragPointerLocalPosition = Offset.zero;

  bool isReturning = false;
  late AnimationController returnAnimController;
  Animation<Offset>? returnAnim;
  Offset returnStartOffset = Offset.zero;
  Offset returnEndOffset = Offset.zero;

  late AnimationController highlightController;
  late Animation<double> highlightAnimation;

  int lastRowMoveDirection = 0;
  int lastColMoveDirection = 0;

  Offset? lastUpGlobalPosition;
  Offset? lastHoverLocalPos;
  int enterMask = 0;

  DragType? dragEndDragType;
  int dragEndOriginalIndex = -1;
  bool postDragCollapseScheduled = false;
  Timer? postDragCollapseTimer;
  static const _postDragCollapseDelay = Duration(milliseconds: 150);

  int get rowCount => widget.rowHeaders?.length ?? 0;
  int get colCount => widget.colHeaders?.length ?? 0;
  double get cellWidth => widget.cellWidth;
  double get cellHeight => widget.cellHeight;
  double get cornerWidth => widget.cellWidth;
  double get cornerHeight => widget.cellHeight;
  bool get showRowHeaders => widget.showRowHeaders;
  bool get showColHeaders => widget.showColHeaders;

  void updateWidget(ReorderableTable newWidget) {
    widget = newWidget;
  }

  void _initOrders() {
    rowOrder = List.generate(rowCount, (i) => i);
    colOrder = List.generate(colCount, (i) => i);
  }

  void initAnimations(TickerProvider vsync) {
    highlightController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 150),
    );
    highlightAnimation = CurvedAnimation(
      parent: highlightController,
      curve: Curves.easeOut,
    );
    returnAnimController =
        AnimationController(
            vsync: vsync,
            duration: const Duration(milliseconds: 400),
          )
          ..addListener(() {
            if (isReturning) onStateChanged();
          })
          ..addStatusListener(_onReturnStatusChanged);
  }

  void _onReturnStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && isReturning) {
      if (dragType == DragType.row) {
        rowOrder.insert(targetLogicalIndex, dragOriginalIndex);
      } else {
        colOrder.insert(targetLogicalIndex, dragOriginalIndex);
      }
      isDragging = false;
      isReturning = false;
      dragType = null;
      dragOriginalIndex = -1;
      targetLogicalIndex = -1;
      onStateChanged();

      highlightCtrl.updateDimensions(rowCount, colCount);

      if (lastUpGlobalPosition != null && dragEndDragType != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final box = tableKey.currentContext?.findRenderObject() as RenderBox?;
          if (box != null) {
            final localPos = box.globalToLocal(lastUpGlobalPosition!);
            _handleDragEndHover(
              localPos,
              dragEndDragType!,
              dragEndOriginalIndex,
            );
          }
          lastUpGlobalPosition = null;
        });
      }
      returnAnimController.reset();
    }
  }

  int calculateTargetIndex(Offset point, DragType type) {
    if (type == DragType.row) {
      double y = point.dy - cornerHeight;
      int idx = (y / cellHeight).floor();
      return idx.clamp(0, rowOrder.length);
    } else {
      double x = point.dx - cornerWidth;
      int idx = (x / cellWidth).floor();
      return idx.clamp(0, colOrder.length);
    }
  }

  void startDrag(DragType type, int logicalIdx, LongPressStartDetails details) {
    if (type == DragType.row && !showRowHeaders) return;
    if (type == DragType.column && !showColHeaders) return;

    final box = tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(details.globalPosition);

    double left, top, width, height;
    if (type == DragType.row) {
      width = collapseCtrl.rowHeaderWidth(logicalIdx);
      left = cornerWidth - width;
      top = cornerHeight + logicalIdx * cellHeight;
      height = cellHeight;
    } else {
      width = cellWidth;
      left = cornerWidth + logicalIdx * cellWidth;
      height = collapseCtrl.colHeaderHeight(logicalIdx);
      top = cornerHeight - height;
    }
    final originalRect = Rect.fromLTWH(left, top, width, height);
    final originalIndex = type == DragType.row
        ? rowOrder[logicalIdx]
        : colOrder[logicalIdx];

    postDragCollapseTimer?.cancel();
    postDragCollapseScheduled = false;

    isDragging = true;
    dragType = type;
    dragPointerLocalPosition = localPos;
    dragOffset = localPos - originalRect.topLeft;
    dragOriginalIndex = originalIndex;
    targetLogicalIndex = logicalIdx;

    if (type == DragType.row) {
      rowOrder.removeAt(logicalIdx);
    } else {
      colOrder.removeAt(logicalIdx);
    }

    collapseCtrl.hoveredRow = -1;
    collapseCtrl.hoveredCol = -1;
    highlightCtrl.reset();
    lastRowMoveDirection = 0;
    lastColMoveDirection = 0;
    enterMask = 0;

    dragEndDragType = null;
    dragEndOriginalIndex = -1;
    highlightController.forward(from: 0.0);
    onStateChanged();
  }

  void handlePointerMove(PointerMoveEvent event) {
    if (!isDragging || isReturning) return;
    final box = tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final tableSize = box.size;
    final localPos = box.globalToLocal(event.position);
    Offset raw = localPos - dragOffset;
    Offset clamped;
    if (dragType == DragType.row) {
      clamped = Offset(
        0,
        raw.dy.clamp(cornerHeight, tableSize.height - cellHeight),
      );
    } else {
      clamped = Offset(
        raw.dx.clamp(cornerWidth, tableSize.width - cellWidth),
        0,
      );
    }
    Offset center = dragType == DragType.row
        ? Offset(0, clamped.dy + cellHeight / 2)
        : Offset(clamped.dx + cellWidth / 2, 0);
    int newTarget = calculateTargetIndex(center, dragType!);

    dragPointerLocalPosition = localPos;
    if (newTarget != targetLogicalIndex) {
      targetLogicalIndex = newTarget;
    }
    onStateChanged();
  }

  void handlePointerUp(PointerUpEvent event) {
    if (!isDragging || isReturning) return;
    postDragCollapseTimer?.cancel();
    postDragCollapseScheduled = false;

    final box = tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) lastUpGlobalPosition = event.position;
    dragEndDragType = dragType;
    dragEndOriginalIndex = dragOriginalIndex;

    Offset raw = dragPointerLocalPosition - dragOffset;
    final tableSize = box?.size ?? Size.zero;
    Offset currentTopLeft;
    if (dragType == DragType.row) {
      currentTopLeft = Offset(
        0,
        raw.dy.clamp(cornerHeight, tableSize.height - cellHeight),
      );
    } else {
      currentTopLeft = Offset(
        raw.dx.clamp(cornerWidth, tableSize.width - cellWidth),
        0,
      );
    }
    highlightController.reverse();

    final tableWidth = cornerWidth + colCount * cellWidth;
    final tableHeight = cornerHeight + rowCount * cellHeight;
    Offset targetTopLeft;
    if (dragType == DragType.row) {
      final rowWidth = cornerWidth + colOrder.length * cellWidth;
      targetTopLeft = Offset(
        tableWidth - rowWidth,
        (cornerHeight + targetLogicalIndex * cellHeight).clamp(
          cornerHeight,
          tableSize.height - cellHeight,
        ),
      );
    } else {
      final columnHeight = cornerHeight + rowOrder.length * cellHeight;
      targetTopLeft = Offset(
        (cornerWidth + targetLogicalIndex * cellWidth).clamp(
          cornerWidth,
          tableSize.width - cellWidth,
        ),
        tableHeight - columnHeight,
      );
    }

    isReturning = true;
    returnStartOffset = currentTopLeft;
    returnEndOffset = targetTopLeft;
    returnAnim = Tween<Offset>(begin: returnStartOffset, end: returnEndOffset)
        .animate(
          CurvedAnimation(
            parent: returnAnimController,
            curve: Curves.easeOutBack,
          ),
        );
    returnAnimController.forward(from: 0.0);
    onStateChanged();
  }

  void handleHover(PointerHoverEvent event) {
    if (isDragging || isReturning) return;
    final box = tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(event.position);
    Offset? delta;
    if (lastHoverLocalPos != null) {
      delta = localPos - lastHoverLocalPos!;
    }
    lastHoverLocalPos = localPos;
    _updateHover(localPos, delta);
  }

  void handlePointerEnter(PointerEnterEvent event) {
    if (isDragging || isReturning) return;
    final box = tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(event.position);
    final size = box.size;
    enterMask = 0;
    if (localPos.dx < 0) enterMask |= 1;
    if (localPos.dx > size.width) enterMask |= 2;
    if (localPos.dy < 0) enterMask |= 4;
    if (localPos.dy > size.height) enterMask |= 8;
    _updateHover(localPos, null);
  }

  void handlePointerExit(PointerExitEvent event) {
    if (isDragging || isReturning) return;
    collapseCtrl.hoveredRow = -1;
    collapseCtrl.hoveredCol = -1;
    highlightCtrl.reset();
    lastRowMoveDirection = 0;
    lastColMoveDirection = 0;
    enterMask = 0;
    onStateChanged();
  }

  void _updateHover(Offset localPos, Offset? delta) {
    final double x = localPos.dx;
    final double y = localPos.dy;
    final double totalWidth = cornerWidth + colCount * cellWidth;
    final double totalHeight = cornerHeight + rowCount * cellHeight;

    if (x < 0 || x > totalWidth || y < 0 || y > totalHeight) {
      if (collapseCtrl.hoveredRow != -1 || collapseCtrl.hoveredCol != -1) {
        highlightCtrl.animateRow(-1, collapseCtrl.hoveredRow);
        highlightCtrl.animateCol(-1, collapseCtrl.hoveredCol);
        collapseCtrl.hoveredRow = -1;
        collapseCtrl.hoveredCol = -1;
      }
      enterMask = 0;
      return;
    }

    if (widget.showRowHeaders &&
        widget.showColHeaders &&
        x < cornerWidth &&
        y < cornerHeight) {
      if (collapseCtrl.hoveredRow != -1 || collapseCtrl.hoveredCol != -1) {
        if (collapseCtrl.hoveredRow != -1 && collapseCtrl.hoveredCol == -1) {
          highlightCtrl.animateRow(-1, collapseCtrl.hoveredRow);
        } else if (collapseCtrl.hoveredCol != -1 &&
            collapseCtrl.hoveredRow == -1) {
          highlightCtrl.animateCol(-1, collapseCtrl.hoveredCol);
        } else {
          highlightCtrl.animateRow(-1, collapseCtrl.hoveredRow);
          highlightCtrl.animateCol(-1, collapseCtrl.hoveredCol);
        }
        collapseCtrl.hoveredRow = -1;
        collapseCtrl.hoveredCol = -1;
      }
      enterMask = 0;
      return;
    }

    // 行表头检测
    if (widget.showRowHeaders) {
      for (int i = 0; i < rowOrder.length; i++) {
        double w = collapseCtrl.rowHeaderWidth(i);
        double left = cornerWidth - w;
        double top = cornerHeight + i * cellHeight;
        if (x >= left && x < left + w && y >= top && y < top + cellHeight) {
          if (i != collapseCtrl.hoveredRow || collapseCtrl.hoveredCol != -1) {
            int dir = 0;
            if (collapseCtrl.hoveredRow == -1 &&
                collapseCtrl.hoveredCol == -1) {
              dir = 1;
            } else if (collapseCtrl.hoveredRow == -1) {
              if (enterMask != 0) {
                dir = (enterMask & 4) != 0
                    ? 1
                    : (enterMask & 8) != 0
                    ? -1
                    : 0;
              } else if (delta != null) {
                dir = delta.dy > 0 ? 1 : (delta.dy < 0 ? -1 : 0);
              }
            } else {
              dir = i > collapseCtrl.hoveredRow ? 1 : -1;
            }
            if (collapseCtrl.hoveredCol != -1) {
              highlightCtrl.animateCol(-1, collapseCtrl.hoveredCol);
            }
            highlightCtrl.animateRow(i, collapseCtrl.hoveredRow);
            lastRowMoveDirection = dir;
            collapseCtrl.hoveredRow = i;
            collapseCtrl.hoveredCol = -1;
          }
          enterMask = 0;
          return;
        }
      }
    }

    // 列表头检测
    if (widget.showColHeaders) {
      for (int i = 0; i < colOrder.length; i++) {
        double h = collapseCtrl.colHeaderHeight(i);
        double left = cornerWidth + i * cellWidth;
        double top = cornerHeight - h;
        if (x >= left && x < left + cellWidth && y >= top && y < top + h) {
          if (i != collapseCtrl.hoveredCol || collapseCtrl.hoveredRow != -1) {
            int dir = 0;
            if (collapseCtrl.hoveredCol == -1 &&
                collapseCtrl.hoveredRow == -1) {
              dir = 1;
            } else if (collapseCtrl.hoveredCol == -1) {
              if (enterMask != 0) {
                dir = (enterMask & 1) != 0
                    ? 1
                    : (enterMask & 2) != 0
                    ? -1
                    : 0;
              } else if (delta != null) {
                dir = delta.dx > 0 ? 1 : (delta.dx < 0 ? -1 : 0);
              }
            } else {
              dir = i > collapseCtrl.hoveredCol ? 1 : -1;
            }
            if (collapseCtrl.hoveredRow != -1) {
              highlightCtrl.animateRow(-1, collapseCtrl.hoveredRow);
            }
            highlightCtrl.animateCol(i, collapseCtrl.hoveredCol);
            lastColMoveDirection = dir;
            collapseCtrl.hoveredCol = i;
            collapseCtrl.hoveredRow = -1;
          }
          enterMask = 0;
          return;
        }
      }
    }

    // 单元格区域
    int row = ((y - cornerHeight) / cellHeight).floor();
    int col = ((x - cornerWidth) / cellWidth).floor();
    if (row >= 0 &&
        row < rowOrder.length &&
        col >= 0 &&
        col < colOrder.length) {
      if (row != collapseCtrl.hoveredRow) {
        int dir = 0;
        if (collapseCtrl.hoveredRow == -1) {
          if (enterMask != 0) {
            dir = (enterMask & 4) != 0
                ? 1
                : (enterMask & 8) != 0
                ? -1
                : 0;
          } else if (delta != null) {
            dir = delta.dy > 0 ? 1 : (delta.dy < 0 ? -1 : 0);
          }
        } else {
          dir = row > collapseCtrl.hoveredRow ? 1 : -1;
        }
        highlightCtrl.animateRow(row, collapseCtrl.hoveredRow);
        lastRowMoveDirection = dir;
        collapseCtrl.hoveredRow = row;
      }
      if (col != collapseCtrl.hoveredCol) {
        int dir = 0;
        if (collapseCtrl.hoveredCol == -1) {
          if (enterMask != 0) {
            dir = (enterMask & 1) != 0
                ? 1
                : (enterMask & 2) != 0
                ? -1
                : 0;
          } else if (delta != null) {
            dir = delta.dx > 0 ? 1 : (delta.dx < 0 ? -1 : 0);
          }
        } else {
          dir = col > collapseCtrl.hoveredCol ? 1 : -1;
        }
        highlightCtrl.animateCol(col, collapseCtrl.hoveredCol);
        lastColMoveDirection = dir;
        collapseCtrl.hoveredCol = col;
      }
    } else {
      if (collapseCtrl.hoveredRow != -1 || collapseCtrl.hoveredCol != -1) {
        highlightCtrl.animateRow(-1, collapseCtrl.hoveredRow);
        highlightCtrl.animateCol(-1, collapseCtrl.hoveredCol);
        collapseCtrl.hoveredRow = -1;
        collapseCtrl.hoveredCol = -1;
      }
    }
    enterMask = 0;
    onStateChanged();
  }

  void _handleDragEndHover(Offset localPos, DragType type, int originalIdx) {
    postDragCollapseTimer?.cancel();
    postDragCollapseScheduled = true;
    postDragCollapseTimer = Timer(_postDragCollapseDelay, _postDragCollapse);
    _updateHover(localPos, null);
  }

  void _postDragCollapse() {
    if (postDragCollapseScheduled) {
      highlightCtrl.animateRow(-1, collapseCtrl.hoveredRow);
      highlightCtrl.animateCol(-1, collapseCtrl.hoveredCol);
      collapseCtrl.hoveredRow = -1;
      collapseCtrl.hoveredCol = -1;
      postDragCollapseScheduled = false;
    }
    postDragCollapseTimer?.cancel();
    postDragCollapseTimer = null;
    onStateChanged();
  }

  void dispose() {
    postDragCollapseTimer?.cancel();
    highlightController.dispose();
    returnAnimController.dispose();
  }
}
