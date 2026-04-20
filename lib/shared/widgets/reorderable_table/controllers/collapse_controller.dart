// lib/shared/widgets/reorderable_table/controllers/collapse_controller.dart

import 'package:flutter/material.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/reorderable_table.dart';

class CollapseController extends ChangeNotifier {
  ReorderableTable widget;
  final TickerProvider vsync;

  int _hoveredRow = -1;
  int _hoveredCol = -1;

  CollapseController({required this.widget, required this.vsync});

  int get hoveredRow => _hoveredRow;
  int get hoveredCol => _hoveredCol;

  set hoveredRow(int value) {
    if (_hoveredRow != value) {
      _hoveredRow = value;
      notifyListeners();
    }
  }

  set hoveredCol(int value) {
    if (_hoveredCol != value) {
      _hoveredCol = value;
      notifyListeners();
    }
  }

  void updateWidget(ReorderableTable newWidget) {
    widget = newWidget;
  }

  double rowHeaderWidth(int logicIdx) {
    if (!widget.showRowHeaders) return 0.0;
    if (!widget.enableRowHeaderCollapse || !widget.rowHeadersCollapsed) {
      return widget.cellWidth;
    }
    if (_hoveredRow == logicIdx) {
      if (_hoveredCol == -1) return widget.cellWidth;
      if (widget.expandRowOnCellHover) return widget.cellWidth;
    }
    return widget.collapsedRowHeaderWidth;
  }

  double colHeaderHeight(int logicIdx) {
    if (!widget.showColHeaders) return 0.0;
    if (!widget.enableColHeaderCollapse || !widget.colHeadersCollapsed) {
      return widget.cellHeight;
    }
    if (_hoveredCol == logicIdx) {
      if (_hoveredRow == -1) return widget.cellHeight;
      if (widget.expandColOnCellHover) return widget.cellHeight;
    }
    return widget.collapsedColHeaderHeight;
  }

  @override
  void dispose() {
    super.dispose();
  }
}
