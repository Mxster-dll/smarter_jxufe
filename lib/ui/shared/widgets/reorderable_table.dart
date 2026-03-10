// lib/ui/shared/widgets/reorderable_table.dart

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:smarter_jxufe/ui/shared/gestures/custom_long_press_recognizer.dart';

enum DragType { row, column }

class ReorderableTable extends StatefulWidget {
  final List<String> rowHeaders;
  final List<String> colHeaders;
  final List<List<Widget>> cells;
  final double cellWidth;
  final double cellHeight;
  final bool enableScrolling;

  // 八种颜色（可选）
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
    required this.rowHeaders,
    required this.colHeaders,
    required this.cells,
    required this.cellWidth,
    required this.cellHeight,
    this.enableScrolling = false,
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

  int _hoveredRow = -1;
  int _hoveredCol = -1;

  final GlobalKey _tableKey = GlobalKey();

  // 记录松开时的局部坐标，用于动画完成后恢复悬停
  Offset? _lastUpLocalPos;

  static const _animationDuration = Duration(milliseconds: 150);

  // 实际使用的颜色（非空）
  late final Color _rowHeaderNormal;
  late final Color _rowHeaderHighlight;
  late final Color _colHeaderNormal;
  late final Color _colHeaderHighlight;
  late final Color _cellHighlight;
  late final Color _cellRowHighlight;
  late final Color _cellColHighlight;
  late final Color _cellNormal;

  @override
  void initState() {
    super.initState();
    _initColors();
    _rowOrder = List.generate(widget.rowHeaders.length, (i) => i);
    _colOrder = List.generate(widget.colHeaders.length, (i) => i);

    _highlightController = AnimationController(
      vsync: this,
      duration: _animationDuration,
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
        // 动画完成后恢复悬停（根据松开时的鼠标位置）
        if (_lastUpLocalPos != null) {
          _updateHoverFromLocalOffset(_lastUpLocalPos!);
          _lastUpLocalPos = null;
        }
        _returnAnimController.reset();
      }
    });
  }

  void _initColors() {
    _rowHeaderNormal = widget.rowHeaderNormal ?? Colors.orange[50]!;
    _rowHeaderHighlight = widget.rowHeaderHighlight ?? Colors.orange[200]!;
    _colHeaderNormal = widget.colHeaderNormal ?? Colors.green[50]!;
    _colHeaderHighlight = widget.colHeaderHighlight ?? Colors.green[200]!;
    _cellHighlight = widget.cellHighlight ?? Colors.grey.shade200;
    _cellRowHighlight = widget.cellRowHighlight ?? _cellHighlight;
    _cellColHighlight = widget.cellColHighlight ?? _cellHighlight;
    _cellNormal = widget.cellNormal ?? Colors.transparent;
  }

  @override
  void didUpdateWidget(covariant ReorderableTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initColors();
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
    final RenderBox? box =
        _tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
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

      _hoveredRow = -1;
      _hoveredCol = -1;
    });

    _highlightController.forward(from: 0.0);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isDragging && !_isReturning) {
      final RenderBox? box =
          _tableKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return;
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
  }

  void _onHover(PointerHoverEvent event) {
    if (!_isDragging && !_isReturning) {
      _updateHoverFromEvent(event);
    }
  }

  void _onPointerEnter(PointerEnterEvent event) {
    if (!_isDragging && !_isReturning) {
      _updateHoverFromEvent(event);
    }
  }

  void _onPointerExit(PointerExitEvent event) {
    if (!_isDragging && !_isReturning) {
      setState(() {
        _hoveredRow = -1;
        _hoveredCol = -1;
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_isDragging || _isReturning) return;

    // 记录松开时的局部坐标，用于动画完成后恢复悬停
    final RenderBox? box =
        _tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      _lastUpLocalPos = box.globalToLocal(event.position);
    }

    _highlightController.reverse();

    Offset currentTopLeft = _dragPointerLocalPosition - _dragOffset;
    Offset targetTopLeft;
    if (_dragType == DragType.row) {
      targetTopLeft = Offset(0, (_targetLogicalIndex + 1) * widget.cellHeight);
    } else {
      targetTopLeft = Offset((_targetLogicalIndex + 1) * widget.cellWidth, 0);
    }

    final RenderBox? box2 =
        _tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box2 == null) return;
    final Size tableSize = box2.size;
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

  void _updateHoverFromEvent(PointerEvent event) {
    final RenderBox? box =
        _tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(event.position);
    _updateHoverFromLocalOffset(localPos);
  }

  void _updateHoverFromLocalOffset(Offset localPos) {
    final double x = localPos.dx;
    final double y = localPos.dy;

    final double totalWidth = (widget.colHeaders.length + 1) * widget.cellWidth;
    final double totalHeight =
        (widget.rowHeaders.length + 1) * widget.cellHeight;

    // 如果鼠标移出表格，清除悬停
    if (x < 0 || x > totalWidth || y < 0 || y > totalHeight) {
      if (_hoveredRow != -1 || _hoveredCol != -1) {
        setState(() {
          _hoveredRow = -1;
          _hoveredCol = -1;
        });
      }
      return;
    }

    // 左上角空白区域
    if (x < widget.cellWidth && y < widget.cellHeight) {
      if (_hoveredRow != -1 || _hoveredCol != -1) {
        setState(() {
          _hoveredRow = -1;
          _hoveredCol = -1;
        });
      }
      return;
    }

    // 行表头区域（第一列，排除左上角）
    if (x < widget.cellWidth) {
      int row = ((y - widget.cellHeight) / widget.cellHeight).floor();
      if (row >= 0 && row < _rowOrder.length) {
        setState(() {
          _hoveredRow = row;
          _hoveredCol = -1;
        });
      } else if (_hoveredRow != -1 || _hoveredCol != -1) {
        setState(() {
          _hoveredRow = -1;
          _hoveredCol = -1;
        });
      }
      return;
    }

    // 列表头区域（第一行，排除左上角）
    if (y < widget.cellHeight) {
      int col = ((x - widget.cellWidth) / widget.cellWidth).floor();
      if (col >= 0 && col < _colOrder.length) {
        setState(() {
          _hoveredCol = col;
          _hoveredRow = -1;
        });
      } else if (_hoveredRow != -1 || _hoveredCol != -1) {
        setState(() {
          _hoveredRow = -1;
          _hoveredCol = -1;
        });
      }
      return;
    }

    // 数据单元格区域
    int row = ((y - widget.cellHeight) / widget.cellHeight).floor();
    int col = ((x - widget.cellWidth) / widget.cellWidth).floor();
    if (row >= 0 &&
        row < _rowOrder.length &&
        col >= 0 &&
        col < _colOrder.length) {
      setState(() {
        _hoveredRow = row;
        _hoveredCol = col;
      });
    } else {
      if (_hoveredRow != -1 || _hoveredCol != -1) {
        setState(() {
          _hoveredRow = -1;
          _hoveredCol = -1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tableContent = MouseRegion(
      onEnter: _onPointerEnter,
      onHover: _onHover,
      onExit: _onPointerExit,
      child: Listener(
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

  Color _getDataCellColor(int rowLogicIdx, int colLogicIdx) {
    if (rowLogicIdx == _hoveredRow && colLogicIdx == _hoveredCol) {
      return _cellHighlight;
    } else if (rowLogicIdx == _hoveredRow) {
      return _cellRowHighlight;
    } else if (colLogicIdx == _hoveredCol) {
      return _cellColHighlight;
    }
    return _cellNormal;
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
          duration: _animationDuration,
          curve: Curves.easeInOut,
          left: (screenColIdx + 1) * widget.cellWidth,
          top: 0,
          width: widget.cellWidth,
          height: widget.cellHeight,
          child: _buildHeaderCell(
            text: widget.colHeaders[originalCol],
            color: _hoveredCol == logicIdx
                ? _colHeaderHighlight
                : _colHeaderNormal,
          ),
        );
      });
    } else {
      return List.generate(_colOrder.length, (logicIdx) {
        final originalCol = _colOrder[logicIdx];
        return AnimatedPositioned(
          key: ValueKey('col-$originalCol'),
          duration: _animationDuration,
          curve: Curves.easeInOut,
          left: (logicIdx + 1) * widget.cellWidth,
          top: 0,
          width: widget.cellWidth,
          height: widget.cellHeight,
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
                      instance.onLongPressStart = (details) =>
                          _onLongPressStart(DragType.column, logicIdx, details);
                    },
                  ),
            },
            child: _buildHeaderCell(
              text: widget.colHeaders[originalCol],
              color: _hoveredCol == logicIdx
                  ? _colHeaderHighlight
                  : _colHeaderNormal,
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
          duration: _animationDuration,
          curve: Curves.easeInOut,
          left: 0,
          top: (screenRowIdx + 1) * widget.cellHeight,
          width: widget.cellWidth,
          height: widget.cellHeight,
          child: _buildHeaderCell(
            text: widget.rowHeaders[originalRow],
            color: _hoveredRow == logicIdx
                ? _rowHeaderHighlight
                : _rowHeaderNormal,
          ),
        );
      });
    } else {
      return List.generate(_rowOrder.length, (logicIdx) {
        final originalRow = _rowOrder[logicIdx];
        return AnimatedPositioned(
          key: ValueKey('row-$originalRow'),
          duration: _animationDuration,
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
              color: _hoveredRow == logicIdx
                  ? _rowHeaderHighlight
                  : _rowHeaderNormal,
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
            duration: _animationDuration,
            curve: Curves.easeInOut,
            left: (screenColIdx + 1) * widget.cellWidth,
            top: (screenRowIdx + 1) * widget.cellHeight,
            width: widget.cellWidth,
            height: widget.cellHeight,
            child: AnimatedContainer(
              duration: _animationDuration,
              curve: Curves.easeInOut,
              color: _getDataCellColor(logicRow, logicCol),
              child: widget.cells[originalRow][originalCol],
            ),
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
      final RenderBox? box =
          _tableKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null) {
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
    }

    return AnimatedBuilder(
      animation: _highlightController,
      builder: (context, child) {
        double highlight = _highlightAnimation.value;
        double elevation = 2 + highlight * 10;

        if (_dragType == DragType.column) {
          // 拖拽列：整列由表头 + 所有行该列的数据单元格组成
          final List<Widget> columnCells = [
            // 表头（使用高亮色，并随动画渐变）
            AnimatedContainer(
              duration: _animationDuration,
              curve: Curves.easeInOut,
              width: widget.cellWidth,
              height: widget.cellHeight,
              color: _colHeaderHighlight,
              alignment: Alignment.center,
              child: Text(
                widget.colHeaders[_dragOriginalIndex],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            // 数据单元格（使用列高亮色 _cellColHighlight）
            ...List.generate(_rowOrder.length, (logicRow) {
              final originalRow = _rowOrder[logicRow];
              return Container(
                width: widget.cellWidth,
                height: widget.cellHeight,
                color: _cellColHighlight,
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
                  children: columnCells,
                ),
              ),
            ),
          );
        } else {
          // 拖拽行：整行由表头 + 所有列该行的数据单元格组成
          final List<Widget> rowCells = [
            // 表头
            AnimatedContainer(
              duration: _animationDuration,
              curve: Curves.easeInOut,
              width: widget.cellWidth,
              height: widget.cellHeight,
              color: _rowHeaderHighlight,
              alignment: Alignment.center,
              child: Text(
                widget.rowHeaders[_dragOriginalIndex],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            // 数据单元格（使用行高亮色 _cellRowHighlight）
            ...List.generate(_colOrder.length, (logicCol) {
              final originalCol = _colOrder[logicCol];
              return Container(
                width: widget.cellWidth,
                height: widget.cellHeight,
                color: _cellRowHighlight,
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
                child: Row(mainAxisSize: MainAxisSize.min, children: rowCells),
              ),
            ),
          );
        }
      },
    );
  }

  Widget _buildHeaderCell({required String text, required Color color}) {
    return AnimatedContainer(
      duration: _animationDuration,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(color: color),
      alignment: Alignment.center,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
