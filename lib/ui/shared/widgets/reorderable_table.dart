import 'package:flutter/material.dart';

import 'package:smarter_jxufe/ui/shared/gestures/custom_long_press_recognizer.dart';

enum DragType { row, column }

class ReorderableTable extends StatefulWidget {
  final List<String> rowHeaders;
  final List<String> colHeaders;
  final List<List<Widget>> cells;
  final double cellWidth;
  final double cellHeight;

  const ReorderableTable({
    super.key,
    required this.rowHeaders,
    required this.colHeaders,
    required this.cells,
    required this.cellWidth,
    required this.cellHeight,
  });

  @override
  State<ReorderableTable> createState() => _ReorderableTableState();
}

class _ReorderableTableState extends State<ReorderableTable>
    with TickerProviderStateMixin {
  late List<int> _rowOrder;
  late List<int> _colOrder;

  bool _isDragging = false;
  DragType? _dragType;
  int _dragOriginalIndex = -1;
  int _targetLogicalIndex = -1;

  Offset _dragOffset = Offset.zero;
  Offset _dragPointerLocalPosition = Offset.zero;

  bool _isReturning = false;
  late AnimationController _returnAnimController;
  Animation<Offset>? _returnAnim;
  Offset _returnStartOffset = Offset.zero;
  Offset _returnEndOffset = Offset.zero;

  late AnimationController _highlightController;
  late Animation<double> _highlightAnimation;

  final GlobalKey _tableKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _rowOrder = List.generate(widget.rowHeaders.length, (i) => i);
    _colOrder = List.generate(widget.colHeaders.length, (i) => i);

    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _highlightAnimation = CurvedAnimation(
      parent: _highlightController,
      curve: Curves.easeOut,
    );

    _returnAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _returnAnimController.addListener(() {
      if (_isReturning) setState(() {});
    });
    _returnAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed && _isReturning) {
        setState(() {
          if (_dragType == DragType.row) {
            _rowOrder.insert(_targetLogicalIndex, _dragOriginalIndex);
          } else {
            _colOrder.insert(_targetLogicalIndex, _dragOriginalIndex);
          }
          _isDragging = false;
          _isReturning = false;
          _dragType = null;
          _dragOriginalIndex = -1;
          _targetLogicalIndex = -1;
        });
        _returnAnimController.reset();
      }
    });
  }

  @override
  void dispose() {
    _highlightController.dispose();
    _returnAnimController.dispose();
    super.dispose();
  }

  int _calculateTargetIndex(Offset point, DragType type) {
    if (type == DragType.row) {
      double y = point.dy;
      int rowIndex = ((y - widget.cellHeight) / widget.cellHeight).floor();
      if (rowIndex < 0) return 0;
      if (rowIndex >= _rowOrder.length) return _rowOrder.length;
      return rowIndex;
    } else {
      double x = point.dx;
      int colIndex = ((x - widget.cellWidth) / widget.cellWidth).floor();
      if (colIndex < 0) return 0;
      if (colIndex >= _colOrder.length) return _colOrder.length;
      return colIndex;
    }
  }

  void _onLongPressStart(
    DragType type,
    int logicalIndex,
    LongPressStartDetails details,
  ) {
    final RenderBox box =
        _tableKey.currentContext!.findRenderObject() as RenderBox;
    final localPos = box.globalToLocal(details.globalPosition);

    Rect originalRect;
    if (type == DragType.row) {
      originalRect = Rect.fromLTWH(
        0,
        (logicalIndex + 1) * widget.cellHeight,
        (widget.colHeaders.length + 1) * widget.cellWidth,
        widget.cellHeight,
      );
    } else {
      originalRect = Rect.fromLTWH(
        (logicalIndex + 1) * widget.cellWidth,
        0,
        widget.cellWidth,
        (widget.rowHeaders.length + 1) * widget.cellHeight,
      );
    }

    final int originalIndex = type == DragType.row
        ? _rowOrder[logicalIndex]
        : _colOrder[logicalIndex];

    setState(() {
      _isDragging = true;
      _dragType = type;
      _dragPointerLocalPosition = localPos;
      _dragOffset = localPos - originalRect.topLeft;
      _dragOriginalIndex = originalIndex;
      _targetLogicalIndex = logicalIndex;

      if (type == DragType.row) {
        _rowOrder.removeAt(logicalIndex);
      } else {
        _colOrder.removeAt(logicalIndex);
      }
    });

    _highlightController.forward(from: 0.0);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isDragging || _isReturning) return;

    final RenderBox box =
        _tableKey.currentContext!.findRenderObject() as RenderBox;
    final Size tableSize = box.size;
    final localPosition = box.globalToLocal(event.position);

    Offset rawTopLeft = localPosition - _dragOffset;
    Offset clampedTopLeft;
    if (_dragType == DragType.row) {
      clampedTopLeft = Offset(
        0,
        rawTopLeft.dy.clamp(0.0, tableSize.height - widget.cellHeight),
      );
    } else {
      clampedTopLeft = Offset(
        rawTopLeft.dx.clamp(0.0, tableSize.width - widget.cellWidth),
        0,
      );
    }

    Offset center;
    if (_dragType == DragType.row) {
      center = Offset(0, clampedTopLeft.dy + widget.cellHeight / 2);
    } else {
      center = Offset(clampedTopLeft.dx + widget.cellWidth / 2, 0);
    }

    int newTarget = _calculateTargetIndex(center, _dragType!);

    setState(() {
      _dragPointerLocalPosition = localPosition;
      if (newTarget != _targetLogicalIndex) {
        _targetLogicalIndex = newTarget;
      }
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_isDragging || _isReturning) return;

    _highlightController.reverse();

    Offset currentTopLeft = _dragPointerLocalPosition - _dragOffset;
    Offset targetTopLeft;
    if (_dragType == DragType.row) {
      targetTopLeft = Offset(0, (_targetLogicalIndex + 1) * widget.cellHeight);
    } else {
      targetTopLeft = Offset((_targetLogicalIndex + 1) * widget.cellWidth, 0);
    }

    final RenderBox box =
        _tableKey.currentContext!.findRenderObject() as RenderBox;
    final Size tableSize = box.size;
    if (_dragType == DragType.row) {
      targetTopLeft = Offset(
        0,
        targetTopLeft.dy.clamp(0.0, tableSize.height - widget.cellHeight),
      );
    } else {
      targetTopLeft = Offset(
        targetTopLeft.dx.clamp(0.0, tableSize.width - widget.cellWidth),
        0,
      );
    }

    setState(() {
      _isReturning = true;
      _returnStartOffset = currentTopLeft;
      _returnEndOffset = targetTopLeft;
    });

    _returnAnim =
        Tween<Offset>(begin: _returnStartOffset, end: _returnEndOffset).animate(
          CurvedAnimation(
            parent: _returnAnimController,
            curve: Curves.easeOutBack,
          ),
        );

    _returnAnimController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: Container(
        key: _tableKey,
        width: (widget.colHeaders.length + 1) * widget.cellWidth,
        height: (widget.rowHeaders.length + 1) * widget.cellHeight,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Stack(
          children: [
            // 左上角占位
            Positioned(
              left: 0,
              top: 0,
              width: widget.cellWidth,
              height: widget.cellHeight,
              child: Container(color: Colors.grey.shade200),
            ),
            ..._buildColHeaders(),
            ..._buildRowHeaders(),
            ..._buildDataCells(),
            if (_isDragging) _buildFloatingRowOrColumn(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildColHeaders() {
    if (_isDragging && _dragType == DragType.column) {
      return List.generate(_colOrder.length, (logicIdx) {
        final originalCol = _colOrder[logicIdx];
        int screenColIdx = logicIdx < _targetLogicalIndex
            ? logicIdx
            : logicIdx + 1;
        return AnimatedPositioned(
          key: ValueKey('col-regular-$originalCol'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          left: (screenColIdx + 1) * widget.cellWidth,
          top: 0,
          width: widget.cellWidth,
          height: widget.cellHeight,
          child: _buildHeaderCell(
            text: widget.colHeaders[originalCol],
            color: Colors.green[50]!,
          ),
        );
      });
    } else {
      return List.generate(_colOrder.length, (logicIdx) {
        final originalCol = _colOrder[logicIdx];
        return AnimatedPositioned(
          key: ValueKey('col-$originalCol'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          left: (logicIdx + 1) * widget.cellWidth,
          top: 0,
          width: widget.cellWidth,
          height: widget.cellHeight,
          child: RawGestureDetector(
            gestures: {
              ShortLongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    ShortLongPressGestureRecognizer
                  >(
                    () => ShortLongPressGestureRecognizer(
                      duration: const Duration(milliseconds: 200),
                    ),
                    (instance) {
                      instance.onLongPressStart = (details) =>
                          _onLongPressStart(DragType.column, logicIdx, details);
                    },
                  ),
            },
            child: _buildHeaderCell(
              text: widget.colHeaders[originalCol],
              color: Colors.green[50]!,
            ),
          ),
        );
      });
    }
  }

  List<Widget> _buildRowHeaders() {
    if (_isDragging && _dragType == DragType.row) {
      return List.generate(_rowOrder.length, (logicIdx) {
        final originalRow = _rowOrder[logicIdx];
        int screenRowIdx = logicIdx < _targetLogicalIndex
            ? logicIdx
            : logicIdx + 1;
        return AnimatedPositioned(
          key: ValueKey('row-regular-$originalRow'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          left: 0,
          top: (screenRowIdx + 1) * widget.cellHeight,
          width: widget.cellWidth,
          height: widget.cellHeight,
          child: _buildHeaderCell(
            text: widget.rowHeaders[originalRow],
            color: Colors.orange[50]!,
          ),
        );
      });
    } else {
      return List.generate(_rowOrder.length, (logicIdx) {
        final originalRow = _rowOrder[logicIdx];
        return AnimatedPositioned(
          key: ValueKey('row-$originalRow'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          left: 0,
          top: (logicIdx + 1) * widget.cellHeight,
          width: widget.cellWidth,
          height: widget.cellHeight,
          child: GestureDetector(
            onLongPressStart: (details) =>
                _onLongPressStart(DragType.row, logicIdx, details),
            child: _buildHeaderCell(
              text: widget.rowHeaders[originalRow],
              color: Colors.orange[50]!,
            ),
          ),
        );
      });
    }
  }

  List<Widget> _buildDataCells() {
    final cells = <Widget>[];
    for (int logicRow = 0; logicRow < _rowOrder.length; logicRow++) {
      final originalRow = _rowOrder[logicRow];
      int screenRowIdx = logicRow;
      if (_isDragging && _dragType == DragType.row) {
        screenRowIdx = logicRow < _targetLogicalIndex ? logicRow : logicRow + 1;
      }

      for (int logicCol = 0; logicCol < _colOrder.length; logicCol++) {
        final originalCol = _colOrder[logicCol];
        int screenColIdx = logicCol;
        if (_isDragging && _dragType == DragType.column) {
          screenColIdx = logicCol < _targetLogicalIndex
              ? logicCol
              : logicCol + 1;
        }

        cells.add(
          AnimatedPositioned(
            key: ValueKey('data-$originalRow-$originalCol'),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            left: (screenColIdx + 1) * widget.cellWidth,
            top: (screenRowIdx + 1) * widget.cellHeight,
            width: widget.cellWidth,
            height: widget.cellHeight,
            child: widget.cells[originalRow][originalCol],
          ),
        );
      }
    }
    return cells;
  }

  Widget _buildFloatingRowOrColumn() {
    Offset topLeft;
    if (_isReturning) {
      topLeft = _returnAnim!.value;
    } else {
      topLeft = _dragPointerLocalPosition - _dragOffset;
      final RenderBox box =
          _tableKey.currentContext!.findRenderObject() as RenderBox;
      final Size tableSize = box.size;
      if (_dragType == DragType.row) {
        topLeft = Offset(
          0,
          topLeft.dy.clamp(0.0, tableSize.height - widget.cellHeight),
        );
      } else {
        topLeft = Offset(
          topLeft.dx.clamp(0.0, tableSize.width - widget.cellWidth),
          0,
        );
      }
    }

    return AnimatedBuilder(
      animation: _highlightController,
      builder: (context, child) {
        double highlight = _highlightAnimation.value;
        double elevation = 2 + highlight * 10;
        Color baseColor = _dragType == DragType.column
            ? Colors.green[200]!
            : Colors.orange[200]!;
        Color highlightColor = _dragType == DragType.column
            ? Colors.green[400]!
            : Colors.orange[400]!;
        Color headerColor = Color.lerp(baseColor, highlightColor, highlight)!;

        if (_dragType == DragType.column) {
          final children = <Widget>[
            Container(
              width: widget.cellWidth,
              height: widget.cellHeight,
              color: headerColor,
              alignment: Alignment.center,
              child: Text(
                widget.colHeaders[_dragOriginalIndex],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...List.generate(_rowOrder.length, (logicRow) {
              final originalRow = _rowOrder[logicRow];
              return Container(
                width: widget.cellWidth,
                height: widget.cellHeight,
                child: widget.cells[originalRow][_dragOriginalIndex],
              );
            }),
          ];

          return Positioned(
            left: topLeft.dx,
            top: 0,
            width: widget.cellWidth,
            height: (widget.rowHeaders.length + 1) * widget.cellHeight,
            child: Material(
              elevation: elevation,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          );
        } else {
          final children = <Widget>[
            Container(
              width: widget.cellWidth,
              height: widget.cellHeight,
              color: headerColor,
              alignment: Alignment.center,
              child: Text(
                widget.rowHeaders[_dragOriginalIndex],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ...List.generate(_colOrder.length, (logicCol) {
              final originalCol = _colOrder[logicCol];
              return Container(
                width: widget.cellWidth,
                height: widget.cellHeight,
                child: widget.cells[_dragOriginalIndex][originalCol],
              );
            }),
          ];

          return Positioned(
            left: 0,
            top: topLeft.dy,
            width: (widget.colHeaders.length + 1) * widget.cellWidth,
            height: widget.cellHeight,
            child: Material(
              elevation: elevation,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildHeaderCell({required String text, required Color color}) {
    return Container(
      decoration: BoxDecoration(color: color),
      alignment: Alignment.center,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
