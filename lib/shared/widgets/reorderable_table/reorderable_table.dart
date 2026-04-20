// lib/shared/widgets/reorderable_table/reorderable_table.dart

import 'package:flutter/material.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/collapse_controller.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/highlight_animation_controller.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/controllers/reorder_controller.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/widgets/col_headers_row.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/widgets/row_headers_column.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/widgets/data_cells_grid.dart';
import 'package:smarter_jxufe/shared/widgets/reorderable_table/widgets/floating_reorder_preview.dart';

export 'package:smarter_jxufe/shared/widgets/reorderable_table/reorderable_table.dart'
    show ReorderableTable;

enum DragType { row, column }

class ReorderableTable extends StatefulWidget {
  final List<String>? rowHeaders;
  final List<String>? colHeaders;
  final List<List<Widget>> cells;
  final double cellWidth;
  final double cellHeight;
  final bool enableScrolling;
  final bool showRowHeaders;
  final bool showColHeaders;
  final bool enableRowHeaderCollapse;
  final bool enableColHeaderCollapse;
  final bool rowHeadersCollapsed;
  final bool colHeadersCollapsed;
  final double collapsedRowHeaderWidth;
  final double collapsedColHeaderHeight;
  final bool expandRowHeadersOutward;
  final bool expandColHeadersOutward;
  final bool expandRowOnCellHover;
  final bool expandColOnCellHover;
  final bool fixedRowHeaders;
  final bool fixedColHeaders;
  final Color? rowHeaderNormal;
  final Color? rowHeaderHighlight;
  final Color? colHeaderNormal;
  final Color? colHeaderHighlight;
  final Color? cellHighlight;
  final Color? cellRowHighlight;
  final Color? cellColHighlight;
  final Color? cellNormal;

  const ReorderableTable({
    super.key,
    this.rowHeaders,
    this.colHeaders,
    required this.cells,
    required this.cellWidth,
    required this.cellHeight,
    this.enableScrolling = false,
    this.showRowHeaders = true,
    this.showColHeaders = true,
    this.enableRowHeaderCollapse = true,
    this.enableColHeaderCollapse = true,
    this.rowHeadersCollapsed = false,
    this.colHeadersCollapsed = false,
    this.collapsedRowHeaderWidth = 10.0,
    this.collapsedColHeaderHeight = 10.0,
    this.expandRowHeadersOutward = true,
    this.expandColHeadersOutward = true,
    this.expandRowOnCellHover = true,
    this.expandColOnCellHover = true,
    this.fixedRowHeaders = false,
    this.fixedColHeaders = false,
    this.rowHeaderNormal,
    this.rowHeaderHighlight,
    this.colHeaderNormal,
    this.colHeaderHighlight,
    this.cellHighlight,
    this.cellRowHighlight,
    this.cellColHighlight,
    this.cellNormal,
  });

  @override
  State<ReorderableTable> createState() => _ReorderableTableState();
}

class _ReorderableTableState extends State<ReorderableTable>
    with TickerProviderStateMixin {
  final GlobalKey _tableKey = GlobalKey();

  late final CollapseController _collapseCtrl;
  late final HighlightAnimationController _highlightCtrl;
  late final ReorderController _reorderCtrl;

  late List<String> _defaultRowHeaders;
  late List<String> _defaultColHeaders;
  late List<GlobalKey> _rowHeaderKeys;
  late List<GlobalKey> _colHeaderKeys;

  @override
  void initState() {
    super.initState();
    _initDefaultHeaders();
    _initKeys();

    _collapseCtrl = CollapseController(widget: widget, vsync: this);
    _highlightCtrl = HighlightAnimationController(
      vsync: this,
      rowCount: rowCount,
      colCount: colCount,
      onUpdate: () => setState(() {}),
    );
    _reorderCtrl = ReorderController(
      widget: widget,
      collapseCtrl: _collapseCtrl,
      highlightCtrl: _highlightCtrl,
      tableKey: _tableKey,
      onStateChanged: () => setState(() {}),
    );

    // 初始化拖拽动画（需要 TickerProvider）
    _reorderCtrl.initAnimations(this);

    // 监听折叠状态变化
    _collapseCtrl.addListener(() => setState(() {}));
  }

  void _initDefaultHeaders() {
    _defaultRowHeaders = List.generate(
      widget.rowHeaders?.length ?? 0,
      (i) => (i + 1).toString(),
    );
    _defaultColHeaders = List.generate(
      widget.colHeaders?.length ?? 0,
      (i) => (i + 1).toString(),
    );
  }

  void _initKeys() {
    _rowHeaderKeys = List.generate(
      widget.showRowHeaders ? (widget.rowHeaders?.length ?? 0) : 0,
      (i) => GlobalKey(),
    );
    _colHeaderKeys = List.generate(
      widget.showColHeaders ? (widget.colHeaders?.length ?? 0) : 0,
      (i) => GlobalKey(),
    );
  }

  @override
  void didUpdateWidget(covariant ReorderableTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _collapseCtrl.updateWidget(widget);
    _reorderCtrl.updateWidget(widget);

    if (rowCount != (oldWidget.rowHeaders?.length ?? 0) ||
        colCount != (oldWidget.colHeaders?.length ?? 0) ||
        widget.showRowHeaders != oldWidget.showRowHeaders ||
        widget.showColHeaders != oldWidget.showColHeaders) {
      _initKeys();
      _highlightCtrl.updateDimensions(rowCount, colCount);
    }
  }

  @override
  void dispose() {
    _collapseCtrl.dispose();
    _highlightCtrl.dispose();
    _reorderCtrl.dispose();
    super.dispose();
  }

  int get rowCount => widget.rowHeaders?.length ?? 0;
  int get colCount => widget.colHeaders?.length ?? 0;
  double get cornerWidth => widget.cellWidth;
  double get cornerHeight => widget.cellHeight;
  bool get showCornerPlaceholder =>
      widget.showRowHeaders && widget.showColHeaders;

  Color get rowHeaderNormal => widget.rowHeaderNormal ?? Colors.orange[50]!;
  Color get rowHeaderHighlight =>
      widget.rowHeaderHighlight ?? Colors.orange[200]!;
  Color get colHeaderNormal => widget.colHeaderNormal ?? Colors.green[50]!;
  Color get colHeaderHighlight =>
      widget.colHeaderHighlight ?? Colors.green[200]!;
  Color get cellHighlight => widget.cellHighlight ?? Colors.grey.shade200;
  Color get cellRowHighlight => widget.cellRowHighlight ?? cellHighlight;
  Color get cellColHighlight => widget.cellColHighlight ?? cellHighlight;
  Color get cellNormal => widget.cellNormal ?? Colors.transparent;

  @override
  Widget build(BuildContext context) {
    Widget tableContent = MouseRegion(
      onEnter: _reorderCtrl.handlePointerEnter,
      onHover: _reorderCtrl.handleHover,
      onExit: _reorderCtrl.handlePointerExit,
      child: Listener(
        onPointerMove: _reorderCtrl.handlePointerMove,
        onPointerUp: _reorderCtrl.handlePointerUp,
        child: Container(
          key: _tableKey,
          width: cornerWidth + colCount * widget.cellWidth,
          height: cornerHeight + rowCount * widget.cellHeight,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (showCornerPlaceholder)
                Positioned(
                  left: 0,
                  top: 0,
                  width: cornerWidth,
                  height: cornerHeight,
                  child: Container(color: Colors.transparent),
                ),
              ColHeadersRow(
                collapseCtrl: _collapseCtrl,
                reorderCtrl: _reorderCtrl,
                colHeaderKeys: _colHeaderKeys,
                defaultColHeaders: _defaultColHeaders,
                colHeaderNormal: colHeaderNormal,
                colHeaderHighlight: colHeaderHighlight,
              ),
              RowHeadersColumn(
                collapseCtrl: _collapseCtrl,
                reorderCtrl: _reorderCtrl,
                rowHeaderKeys: _rowHeaderKeys,
                defaultRowHeaders: _defaultRowHeaders,
                rowHeaderNormal: rowHeaderNormal,
                rowHeaderHighlight: rowHeaderHighlight,
              ),
              DataCellsGrid(
                collapseCtrl: _collapseCtrl,
                reorderCtrl: _reorderCtrl,
                highlightCtrl: _highlightCtrl,
                cells: widget.cells,
                cellHighlight: cellHighlight,
                cellRowHighlight: cellRowHighlight,
                cellColHighlight: cellColHighlight,
                cellNormal: cellNormal,
              ),
              if (_reorderCtrl.isDragging)
                FloatingReorderPreview(
                  reorderCtrl: _reorderCtrl,
                  collapseCtrl: _collapseCtrl,
                  defaultRowHeaders: _defaultRowHeaders,
                  defaultColHeaders: _defaultColHeaders,
                  cells: widget.cells,
                  rowHeaderHighlight: rowHeaderHighlight,
                  colHeaderHighlight: colHeaderHighlight,
                  cellRowHighlight: cellRowHighlight,
                  cellColHighlight: cellColHighlight,
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.enableScrolling) {
      tableContent = Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: tableContent,
          ),
        ),
      );
    }
    return tableContent;
  }
}
