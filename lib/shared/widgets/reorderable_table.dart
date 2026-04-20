// lib/ui/shared/widgets/reorderable_table.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:smarter_jxufe/ui/shared/gestures/custom_long_press_recognizer.dart';

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

  // 折叠相关
  final bool enableRowHeaderCollapse;
  final bool enableColHeaderCollapse;
  final bool rowHeadersCollapsed;
  final bool colHeadersCollapsed;
  final double collapsedRowHeaderWidth;
  final double collapsedColHeaderHeight;
  final bool expandRowHeadersOutward;
  final bool expandColHeadersOutward;

  // 单元格悬停时是否展开同行/列表头（独立控制）
  final bool expandRowOnCellHover;
  final bool expandColOnCellHover;

  // 固定行/列号
  final bool fixedRowHeaders;
  final bool fixedColHeaders;

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
  late List<int> _rowOrder;
  late List<int> _colOrder;

  // 默认自然数列
  late List<String> _defaultRowHeaders;
  late List<String> _defaultColHeaders;

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

  int _lastRowMoveDirection = 0; // 1向下，-1向上，0未知
  int _lastColMoveDirection = 0; // 1向右，-1向左，0未知

  final GlobalKey _tableKey = GlobalKey();

  Offset? _lastUpGlobalPosition; // 鼠标松开时的全局坐标
  Offset? _lastHoverLocalPos;
  int _enterMask = 0; // 1左，2右，4上，8下

  // 拖拽结束时的信息，用于强制悬停
  DragType? _dragEndDragType;
  int _dragEndOriginalIndex = -1;
  bool _postDragCollapseScheduled = false;
  Timer? _postDragCollapseTimer;
  static const Duration _postDragCollapseDelay = Duration(milliseconds: 150);

  static const _animationDuration = Duration(milliseconds: 150);
  static const _highlightAnimDuration = Duration(milliseconds: 200);

  List<AnimationController> _rowHighlightControllers = [];
  List<AnimationController> _colHighlightControllers = [];
  List<Animation<double>> _rowHighlightAnimations = [];
  List<Animation<double>> _colHighlightAnimations = [];

  late List<GlobalKey> _rowHeaderKeys;
  late List<GlobalKey> _colHeaderKeys;

  // ---------- 颜色 Getter（直接从 widget 取值，无需存储状态） ----------
  Color get _rowHeaderNormal => widget.rowHeaderNormal ?? Colors.orange[50]!;
  Color get _rowHeaderHighlight =>
      widget.rowHeaderHighlight ?? Colors.orange[200]!;
  Color get _colHeaderNormal => widget.colHeaderNormal ?? Colors.green[50]!;
  Color get _colHeaderHighlight =>
      widget.colHeaderHighlight ?? Colors.green[200]!;
  Color get _cellHighlight => widget.cellHighlight ?? Colors.grey.shade200;
  Color get _cellRowHighlight => widget.cellRowHighlight ?? _cellHighlight;
  Color get _cellColHighlight => widget.cellColHighlight ?? _cellHighlight;
  Color get _cellNormal => widget.cellNormal ?? Colors.transparent;
  // -------------------------------------------------------------------

  // 固定左上角占位格尺寸
  double get _cornerWidth => widget.cellWidth;
  double get _cornerHeight => widget.cellHeight;

  // 根据悬停状态计算每个行表头的宽度
  double _rowHeaderWidth(int logicIdx) {
    if (!widget.showRowHeaders) return 0.0;
    if (!widget.enableRowHeaderCollapse || !widget.rowHeadersCollapsed) {
      return widget.cellWidth;
    }
    if (_hoveredRow == logicIdx) {
      // 如果当前行被悬停，判断是表头悬停还是单元格悬停
      if (_hoveredCol == -1) {
        return widget.cellWidth; // 表头悬停：总是展开
      } else if (widget.expandRowOnCellHover) {
        return widget.cellWidth; // 单元格悬停且允许展开
      }
    }
    return widget.collapsedRowHeaderWidth;
  }

  // 根据悬停状态计算每个列表头的高度
  double _colHeaderHeight(int logicIdx) {
    if (!widget.showColHeaders) return 0.0;
    if (!widget.enableColHeaderCollapse || !widget.colHeadersCollapsed) {
      return widget.cellHeight;
    }
    if (_hoveredCol == logicIdx) {
      if (_hoveredRow == -1) {
        return widget.cellHeight;
      } else if (widget.expandColOnCellHover) {
        return widget.cellHeight;
      }
    }
    return widget.collapsedColHeaderHeight;
  }

  // 左上角占位格是否显示
  bool get _showCornerPlaceholder =>
      widget.showRowHeaders && widget.showColHeaders;

  @override
  void initState() {
    super.initState();
    _rowOrder = List.generate(widget.rowHeaders?.length ?? 0, (i) => i);
    _colOrder = List.generate(widget.colHeaders?.length ?? 0, (i) => i);
    _initDefaultHeaders();
    _initKeys();
    _initHighlightAnimations();

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

        // 重新初始化高亮动画控制器（因为行/列顺序可能改变）
        _initHighlightAnimations();

        // 拖拽结束后，根据最新的鼠标位置恢复悬停状态（使用全局坐标转换）
        if (_lastUpGlobalPosition != null && _dragEndDragType != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final RenderBox? box =
                _tableKey.currentContext?.findRenderObject() as RenderBox?;
            if (box != null) {
              final localPos = box.globalToLocal(_lastUpGlobalPosition!);
              _handleDragEndHover(
                localPos,
                _dragEndDragType!,
                _dragEndOriginalIndex,
              );
            }
            _lastUpGlobalPosition = null;
          });
        }

        _returnAnimController.reset();
      }
    });
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

  void _initHighlightAnimations() {
    for (var c in _rowHighlightControllers) {
      c.removeListener(_onHighlightAnimationUpdate);
      c.dispose();
    }
    for (var c in _colHighlightControllers) {
      c.removeListener(_onHighlightAnimationUpdate);
      c.dispose();
    }

    _rowHighlightControllers = List.generate(
      _rowOrder.length,
      (index) =>
          AnimationController(vsync: this, duration: _highlightAnimDuration)
            ..value = 0.0,
    );
    _rowHighlightAnimations = _rowHighlightControllers
        .map((c) => c.drive(CurveTween(curve: Curves.easeOut)))
        .toList();

    _colHighlightControllers = List.generate(
      _colOrder.length,
      (index) =>
          AnimationController(vsync: this, duration: _highlightAnimDuration)
            ..value = 0.0,
    );
    _colHighlightAnimations = _colHighlightControllers
        .map((c) => c.drive(CurveTween(curve: Curves.easeOut)))
        .toList();

    for (var c in _rowHighlightControllers) {
      c.addListener(_onHighlightAnimationUpdate);
    }
    for (var c in _colHighlightControllers) {
      c.addListener(_onHighlightAnimationUpdate);
    }
  }

  void _onHighlightAnimationUpdate() {
    setState(() {});
  }

  void _animateRowHighlight(int newRow, int oldRow, [int direction = 0]) {
    if (oldRow != -1 && oldRow < _rowHighlightControllers.length) {
      _rowHighlightControllers[oldRow].animateTo(0.0);
    }
    if (newRow != -1 && newRow < _rowHighlightControllers.length) {
      _rowHighlightControllers[newRow].animateTo(1.0);
    }
    if (direction != 0) _lastRowMoveDirection = direction;
  }

  void _animateColHighlight(int newCol, int oldCol, [int direction = 0]) {
    if (oldCol != -1 && oldCol < _colHighlightControllers.length) {
      _colHighlightControllers[oldCol].animateTo(0.0);
    }
    if (newCol != -1 && newCol < _colHighlightControllers.length) {
      _colHighlightControllers[newCol].animateTo(1.0);
    }
    if (direction != 0) _lastColMoveDirection = direction;
  }

  @override
  void didUpdateWidget(covariant ReorderableTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 注意：颜色值通过 getter 获取，无需手动更新
    if ((widget.rowHeaders?.length ?? 0) !=
            (oldWidget.rowHeaders?.length ?? 0) ||
        (widget.colHeaders?.length ?? 0) !=
            (oldWidget.colHeaders?.length ?? 0) ||
        widget.showRowHeaders != oldWidget.showRowHeaders ||
        widget.showColHeaders != oldWidget.showColHeaders) {
      _initKeys();
      _initHighlightAnimations();
    }
  }

  @override
  void dispose() {
    _postDragCollapseTimer?.cancel();
    for (var c in _rowHighlightControllers) {
      c.removeListener(_onHighlightAnimationUpdate);
      c.dispose();
    }
    for (var c in _colHighlightControllers) {
      c.removeListener(_onHighlightAnimationUpdate);
      c.dispose();
    }
    _highlightController.dispose();
    _returnAnimController.dispose();
    super.dispose();
  }

  int _calculateTargetIndex(Offset point, DragType type) {
    if (type == DragType.row) {
      double y = point.dy - _cornerHeight;
      int rowIndex = (y / widget.cellHeight).floor();
      if (rowIndex < 0) return 0;
      if (rowIndex >= _rowOrder.length) return _rowOrder.length;
      return rowIndex;
    } else {
      double x = point.dx - _cornerWidth;
      int colIndex = (x / widget.cellWidth).floor();
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
    if (type == DragType.row && !widget.showRowHeaders) return;
    if (type == DragType.column && !widget.showColHeaders) return;

    final RenderBox? box =
        _tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(details.globalPosition);

    // 计算当前表头的实际位置（基于修正后的对齐方式）
    double left, top, width, height;
    if (type == DragType.row) {
      width = _rowHeaderWidth(logicalIndex);
      left = _cornerWidth - width; // 右对齐：左侧随宽度变化，右侧固定在 _cornerWidth
      top = _cornerHeight + logicalIndex * widget.cellHeight;
      height = widget.cellHeight;
    } else {
      width = widget.cellWidth;
      left = _cornerWidth + logicalIndex * widget.cellWidth;
      height = _colHeaderHeight(logicalIndex);
      top = _cornerHeight - height; // 底部对齐：顶部随高度变化，底部固定在 _cornerHeight
    }
    Rect originalRect = Rect.fromLTWH(left, top, width, height);

    final int originalIndex = type == DragType.row
        ? _rowOrder[logicalIndex]
        : _colOrder[logicalIndex];

    setState(() {
      _postDragCollapseTimer?.cancel();
      _postDragCollapseScheduled = false;

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
      for (var c in _rowHighlightControllers) c.value = 0.0;
      for (var c in _colHighlightControllers) c.value = 0.0;
      _lastRowMoveDirection = 0;
      _lastColMoveDirection = 0;
      _enterMask = 0;
    });

    // 重置拖拽结束信息
    _dragEndDragType = null;
    _dragEndOriginalIndex = -1;

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
          rawTopLeft.dy.clamp(
            _cornerHeight,
            tableSize.height - widget.cellHeight,
          ),
        );
      } else {
        clampedTopLeft = Offset(
          rawTopLeft.dx.clamp(_cornerWidth, tableSize.width - widget.cellWidth),
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
    if (_isDragging || _isReturning) return;
    final RenderBox? box =
        _tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(event.position);
    Offset? moveDelta;
    if (_lastHoverLocalPos != null) {
      moveDelta = localPos - _lastHoverLocalPos!;
    }
    _lastHoverLocalPos = localPos;
    _updateHoverFromLocalOffset(localPos, moveDelta: moveDelta);
  }

  void _onPointerEnter(PointerEnterEvent event) {
    if (_isDragging || _isReturning) return;
    final RenderBox? box =
        _tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(event.position);
    final Size size = box.size;
    _enterMask = 0;
    if (localPos.dx < 0) _enterMask |= 1;
    if (localPos.dx > size.width) _enterMask |= 2;
    if (localPos.dy < 0) _enterMask |= 4;
    if (localPos.dy > size.height) _enterMask |= 8;
    _updateHoverFromLocalOffset(localPos);
  }

  void _onPointerExit(PointerExitEvent event) {
    if (_isDragging || _isReturning) return;
    setState(() {
      _hoveredRow = -1;
      _hoveredCol = -1;
      for (var c in _rowHighlightControllers) c.animateTo(0.0);
      for (var c in _colHighlightControllers) c.animateTo(0.0);
      _lastRowMoveDirection = 0;
      _lastColMoveDirection = 0;
      _enterMask = 0;
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_isDragging || _isReturning) return;

    _postDragCollapseTimer?.cancel();
    _postDragCollapseScheduled = false;

    final RenderBox? box =
        _tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      _lastUpGlobalPosition = event.position; // 记录全局坐标
    }

    // 记录拖拽结束信息
    _dragEndDragType = _dragType;
    _dragEndOriginalIndex = _dragOriginalIndex;

    Offset rawTopLeft = _dragPointerLocalPosition - _dragOffset;
    final Size tableSize = box?.size ?? Size.zero;
    Offset currentTopLeft;
    if (_dragType == DragType.row) {
      currentTopLeft = Offset(
        0,
        rawTopLeft.dy.clamp(
          _cornerHeight,
          tableSize.height - widget.cellHeight,
        ),
      );
    } else {
      currentTopLeft = Offset(
        rawTopLeft.dx.clamp(_cornerWidth, tableSize.width - widget.cellWidth),
        0,
      );
    }

    _highlightController.reverse();

    final double tableWidth =
        _cornerWidth + (widget.colHeaders?.length ?? 0) * widget.cellWidth;
    final double tableHeight =
        _cornerHeight + (widget.rowHeaders?.length ?? 0) * widget.cellHeight;

    Offset targetTopLeft;
    if (_dragType == DragType.row) {
      final double rowWidth =
          _cornerWidth + _colOrder.length * widget.cellWidth;
      targetTopLeft = Offset(
        tableWidth - rowWidth, // 右对齐
        _cornerHeight + _targetLogicalIndex * widget.cellHeight,
      );
    } else {
      final double columnHeight =
          _cornerHeight + _rowOrder.length * widget.cellHeight;
      targetTopLeft = Offset(
        _cornerWidth + _targetLogicalIndex * widget.cellWidth,
        tableHeight - columnHeight, // 底部对齐
      );
    }

    if (_dragType == DragType.row) {
      targetTopLeft = Offset(
        targetTopLeft.dx,
        targetTopLeft.dy.clamp(
          _cornerHeight,
          tableSize.height - widget.cellHeight,
        ),
      );
    } else {
      targetTopLeft = Offset(
        targetTopLeft.dx.clamp(
          _cornerWidth,
          tableSize.width - widget.cellWidth,
        ),
        targetTopLeft.dy,
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

  void _handleDragEndHover(
    Offset localPos,
    DragType dragType,
    int originalIndex,
  ) {
    _postDragCollapseTimer?.cancel();
    _postDragCollapseScheduled = true;

    // 延迟折叠动画，然后应用最终悬停
    _postDragCollapseTimer = Timer(_postDragCollapseDelay, _postDragCollapse);

    // 立即执行悬停检测作为最终状态（延迟后会覆盖）
    _updateHoverFromLocalOffset(localPos);
  }

  void _postDragCollapse() {
    if (_postDragCollapseScheduled) {
      _animateRowHighlight(-1, _hoveredRow);
      _animateColHighlight(-1, _hoveredCol);
      setState(() {
        _hoveredRow = -1;
        _hoveredCol = -1;
      });
      _postDragCollapseScheduled = false;
    }
    _postDragCollapseTimer?.cancel();
    _postDragCollapseTimer = null;
  }

  void _updateHoverFromLocalOffset(Offset localPos, {Offset? moveDelta}) {
    final double x = localPos.dx;
    final double y = localPos.dy;

    final double totalWidth =
        _cornerWidth + (widget.colHeaders?.length ?? 0) * widget.cellWidth;
    final double totalHeight =
        _cornerHeight + (widget.rowHeaders?.length ?? 0) * widget.cellHeight;

    if (x < 0 || x > totalWidth || y < 0 || y > totalHeight) {
      if (_hoveredRow != -1 || _hoveredCol != -1) {
        _animateRowHighlight(-1, _hoveredRow);
        _animateColHighlight(-1, _hoveredCol);
        setState(() {
          _hoveredRow = -1;
          _hoveredCol = -1;
        });
      }
      _enterMask = 0;
      return;
    }

    if (_showCornerPlaceholder && x < _cornerWidth && y < _cornerHeight) {
      if (_hoveredRow != -1 || _hoveredCol != -1) {
        if (_hoveredRow != -1 && _hoveredCol == -1) {
          _animateRowHighlight(-1, _hoveredRow, -1);
        } else if (_hoveredCol != -1 && _hoveredRow == -1) {
          _animateColHighlight(-1, _hoveredCol, -1);
        } else {
          _animateRowHighlight(-1, _hoveredRow);
          _animateColHighlight(-1, _hoveredCol);
        }
        setState(() {
          _hoveredRow = -1;
          _hoveredCol = -1;
        });
      }
      _enterMask = 0;
      return;
    }

    // 行表头区域：遍历所有行，检查点是否落在某个行表头内
    if (widget.showRowHeaders) {
      for (int logicIdx = 0; logicIdx < _rowOrder.length; logicIdx++) {
        double width = _rowHeaderWidth(logicIdx);
        double left = _cornerWidth - width; // 修正后的左侧
        double top = _cornerHeight + logicIdx * widget.cellHeight;
        double right = left + width;
        double bottom = top + widget.cellHeight;
        if (x >= left && x < right && y >= top && y < bottom) {
          if (logicIdx != _hoveredRow || _hoveredCol != -1) {
            int rowDirection = 0;
            if (_hoveredRow == -1 && _hoveredCol == -1) {
              rowDirection = 1;
            } else if (_hoveredRow == -1) {
              if (_enterMask != 0) {
                if (_enterMask & 4 != 0)
                  rowDirection = 1;
                else if (_enterMask & 8 != 0)
                  rowDirection = -1;
              } else if (moveDelta != null) {
                rowDirection = moveDelta.dy > 0
                    ? 1
                    : (moveDelta.dy < 0 ? -1 : 0);
              }
            } else {
              rowDirection = logicIdx > _hoveredRow ? 1 : -1;
            }
            if (_hoveredCol != -1) {
              int colDirection = 0;
              if (_hoveredRow != -1 && _hoveredCol != -1) colDirection = -1;
              _animateColHighlight(-1, _hoveredCol, colDirection);
            }
            _animateRowHighlight(logicIdx, _hoveredRow, rowDirection);
            setState(() {
              _hoveredRow = logicIdx;
              _hoveredCol = -1;
            });
          }
          _enterMask = 0;
          return;
        }
      }
    }

    // 列表头区域：遍历所有列
    if (widget.showColHeaders) {
      for (int logicIdx = 0; logicIdx < _colOrder.length; logicIdx++) {
        double height = _colHeaderHeight(logicIdx);
        double left = _cornerWidth + logicIdx * widget.cellWidth;
        double top = _cornerHeight - height; // 修正后的顶部
        double right = left + widget.cellWidth;
        double bottom = top + height;
        if (x >= left && x < right && y >= top && y < bottom) {
          if (logicIdx != _hoveredCol || _hoveredRow != -1) {
            int colDirection = 0;
            if (_hoveredCol == -1 && _hoveredRow == -1) {
              colDirection = 1;
            } else if (_hoveredCol == -1) {
              if (_enterMask != 0) {
                if (_enterMask & 1 != 0)
                  colDirection = 1;
                else if (_enterMask & 2 != 0)
                  colDirection = -1;
              } else if (moveDelta != null) {
                colDirection = moveDelta.dx > 0
                    ? 1
                    : (moveDelta.dx < 0 ? -1 : 0);
              }
            } else {
              colDirection = logicIdx > _hoveredCol ? 1 : -1;
            }
            if (_hoveredRow != -1) {
              int rowDirection = 0;
              if (_hoveredRow != -1 && _hoveredCol != -1) rowDirection = -1;
              _animateRowHighlight(-1, _hoveredRow, rowDirection);
            }
            _animateColHighlight(logicIdx, _hoveredCol, colDirection);
            setState(() {
              _hoveredCol = logicIdx;
              _hoveredRow = -1;
            });
          }
          _enterMask = 0;
          return;
        }
      }
    }

    // 数据单元格区域
    int row = ((y - _cornerHeight) / widget.cellHeight).floor();
    int col = ((x - _cornerWidth) / widget.cellWidth).floor();
    if (row >= 0 &&
        row < _rowOrder.length &&
        col >= 0 &&
        col < _colOrder.length) {
      bool changed = false;
      if (row != _hoveredRow) {
        int rowDirection = 0;
        if (_hoveredRow == -1) {
          if (_hoveredCol != -1 && _hoveredRow == -1) {
            rowDirection = 1;
          } else {
            if (_enterMask != 0) {
              if (_enterMask & 4 != 0)
                rowDirection = 1;
              else if (_enterMask & 8 != 0)
                rowDirection = -1;
            } else if (moveDelta != null) {
              rowDirection = moveDelta.dy > 0 ? 1 : (moveDelta.dy < 0 ? -1 : 0);
            }
          }
        } else {
          rowDirection = row > _hoveredRow ? 1 : -1;
        }
        _animateRowHighlight(row, _hoveredRow, rowDirection);
        _hoveredRow = row;
        changed = true;
      }
      if (col != _hoveredCol) {
        int colDirection = 0;
        if (_hoveredCol == -1) {
          if (_hoveredRow != -1 && _hoveredCol == -1) {
            colDirection = 1;
          } else {
            if (_enterMask != 0) {
              if (_enterMask & 1 != 0)
                colDirection = 1;
              else if (_enterMask & 2 != 0)
                colDirection = -1;
            } else if (moveDelta != null) {
              colDirection = moveDelta.dx > 0 ? 1 : (moveDelta.dx < 0 ? -1 : 0);
            }
          }
        } else {
          colDirection = col > _hoveredCol ? 1 : -1;
        }
        _animateColHighlight(col, _hoveredCol, colDirection);
        _hoveredCol = col;
        changed = true;
      }
      if (changed) setState(() {});
    } else {
      if (_hoveredRow != -1 || _hoveredCol != -1) {
        _animateRowHighlight(-1, _hoveredRow);
        _animateColHighlight(-1, _hoveredCol);
        setState(() {
          _hoveredRow = -1;
          _hoveredCol = -1;
        });
      }
    }
    _enterMask = 0;
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
          width:
              _cornerWidth +
              (widget.colHeaders?.length ?? 0) * widget.cellWidth,
          height:
              _cornerHeight +
              (widget.rowHeaders?.length ?? 0) * widget.cellHeight,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 左上角固定占位格（透明）
              if (_showCornerPlaceholder)
                Positioned(
                  left: 0,
                  top: 0,
                  width: _cornerWidth,
                  height: _cornerHeight,
                  child: Container(color: Colors.transparent),
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

  List<Widget> _buildColHeaders() {
    if (!widget.showColHeaders) return [];

    // 判断是否应该应用圆角：启用了列折叠且当前处于折叠模式
    final bool useColHeaderRoundCorners =
        widget.enableColHeaderCollapse && widget.colHeadersCollapsed;

    if (_isDragging && _dragType == DragType.column) {
      // 拖拽状态：所有列头随拖拽目标移动，根据高度决定是否显示文本，并添加淡入淡出
      return List.generate(_colOrder.length, (logicIdx) {
        final originalCol = _colOrder[logicIdx];
        int screenColIdx = logicIdx < _targetLogicalIndex
            ? logicIdx
            : logicIdx + 1;
        final double height = _colHeaderHeight(logicIdx);
        final double top = _cornerHeight - height;
        return AnimatedPositioned(
          key: ValueKey('col-regular-$originalCol'),
          duration: _animationDuration,
          curve: Curves.easeInOut,
          left: _cornerWidth + screenColIdx * widget.cellWidth,
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
                      instance.onLongPressStart = (details) =>
                          _onLongPressStart(DragType.column, logicIdx, details);
                    },
                  ),
            },
            child: AnimatedContainer(
              duration: _animationDuration,
              curve: Curves.easeInOut,
              width: widget.cellWidth,
              height: height,
              decoration: BoxDecoration(
                color: _colHeaderNormal, // 拖拽时不高亮
                borderRadius: useColHeaderRoundCorners
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      )
                    : null,
              ),
              child: AnimatedOpacity(
                opacity: (height == widget.cellHeight) ? 1.0 : 0.0,
                duration: _animationDuration,
                curve: Curves.easeOut,
                child: Center(
                  child: Text(
                    widget.colHeaders?[originalCol] ??
                        _defaultColHeaders[originalCol],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        );
      });
    } else {
      // 非拖拽状态：支持悬停高亮，只要该列被悬停就高亮
      return List.generate(_colOrder.length, (logicIdx) {
        final originalCol = _colOrder[logicIdx];
        final double height = _colHeaderHeight(logicIdx);
        final double top = _cornerHeight - height;
        return AnimatedPositioned(
          key: _colHeaderKeys.isNotEmpty ? _colHeaderKeys[logicIdx] : null,
          duration: _animationDuration,
          curve: Curves.easeInOut,
          left: _cornerWidth + logicIdx * widget.cellWidth,
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
                      instance.onLongPressStart = (details) =>
                          _onLongPressStart(DragType.column, logicIdx, details);
                    },
                  ),
            },
            child: AnimatedContainer(
              duration: _animationDuration,
              curve: Curves.easeInOut,
              width: widget.cellWidth,
              height: height,
              decoration: BoxDecoration(
                color:
                    _hoveredCol ==
                        logicIdx // 只要该列被悬停就高亮
                    ? _colHeaderHighlight
                    : _colHeaderNormal,
                borderRadius: useColHeaderRoundCorners
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      )
                    : null,
              ),
              child: AnimatedOpacity(
                opacity: (height == widget.cellHeight) ? 1.0 : 0.0,
                duration: _animationDuration,
                curve: Curves.easeOut,
                child: Center(
                  child: Text(
                    widget.colHeaders?[originalCol] ??
                        _defaultColHeaders[originalCol],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        );
      });
    }
  }

  List<Widget> _buildRowHeaders() {
    if (!widget.showRowHeaders) return [];

    // 判断是否应该应用圆角：启用了行折叠且当前处于折叠模式
    final bool useRowHeaderRoundCorners =
        widget.enableRowHeaderCollapse && widget.rowHeadersCollapsed;

    if (_isDragging && _dragType == DragType.row) {
      // 拖拽状态：所有行头随拖拽目标移动，根据宽度决定是否显示文本，并添加淡入淡出
      return List.generate(_rowOrder.length, (logicIdx) {
        final originalRow = _rowOrder[logicIdx];
        int screenRowIdx = logicIdx < _targetLogicalIndex
            ? logicIdx
            : logicIdx + 1;
        final double width = _rowHeaderWidth(logicIdx);
        final double left = _cornerWidth - width;
        return AnimatedPositioned(
          key: ValueKey('row-regular-$originalRow'),
          duration: _animationDuration,
          curve: Curves.easeInOut,
          left: left,
          top: _cornerHeight + screenRowIdx * widget.cellHeight,
          width: width,
          height: widget.cellHeight,
          child: GestureDetector(
            onLongPressStart: (details) =>
                _onLongPressStart(DragType.row, logicIdx, details),
            child: AnimatedContainer(
              duration: _animationDuration,
              curve: Curves.easeInOut,
              width: width,
              height: widget.cellHeight,
              decoration: BoxDecoration(
                color: _rowHeaderNormal, // 拖拽时不高亮
                borderRadius: useRowHeaderRoundCorners
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomLeft: Radius.circular(8),
                      )
                    : null,
              ),
              child: AnimatedOpacity(
                opacity: (width == widget.cellWidth) ? 1.0 : 0.0,
                duration: _animationDuration,
                curve: Curves.easeOut,
                child: Center(
                  child: Text(
                    widget.rowHeaders?[originalRow] ??
                        _defaultRowHeaders[originalRow],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        );
      });
    } else {
      // 非拖拽状态：支持悬停高亮，只要该行被悬停就高亮
      return List.generate(_rowOrder.length, (logicIdx) {
        final originalRow = _rowOrder[logicIdx];
        final double width = _rowHeaderWidth(logicIdx);
        final double left = _cornerWidth - width;
        return AnimatedPositioned(
          key: _rowHeaderKeys.isNotEmpty ? _rowHeaderKeys[logicIdx] : null,
          duration: _animationDuration,
          curve: Curves.easeInOut,
          left: left,
          top: _cornerHeight + logicIdx * widget.cellHeight,
          width: width,
          height: widget.cellHeight,
          child: GestureDetector(
            onLongPressStart: (details) =>
                _onLongPressStart(DragType.row, logicIdx, details),
            child: AnimatedContainer(
              duration: _animationDuration,
              curve: Curves.easeInOut,
              width: width,
              height: widget.cellHeight,
              decoration: BoxDecoration(
                color:
                    _hoveredRow ==
                        logicIdx // 只要该行被悬停就高亮
                    ? _rowHeaderHighlight
                    : _rowHeaderNormal,
                borderRadius: useRowHeaderRoundCorners
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomLeft: Radius.circular(8),
                      )
                    : null,
              ),
              child: AnimatedOpacity(
                opacity: (width == widget.cellWidth) ? 1.0 : 0.0,
                duration: _animationDuration,
                curve: Curves.easeOut,
                child: Center(
                  child: Text(
                    widget.rowHeaders?[originalRow] ??
                        _defaultRowHeaders[originalRow],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
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
            left: _cornerWidth + screenColIdx * widget.cellWidth,
            top: _cornerHeight + screenRowIdx * widget.cellHeight,
            width: widget.cellWidth,
            height: widget.cellHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  painter: _CellBackgroundPainter(
                    rowProgress: logicRow < _rowHighlightAnimations.length
                        ? _rowHighlightAnimations[logicRow].value
                        : 0.0,
                    colProgress: logicCol < _colHighlightAnimations.length
                        ? _colHighlightAnimations[logicCol].value
                        : 0.0,
                    cellWidth: constraints.maxWidth,
                    cellHeight: constraints.maxHeight,
                    highlightColor: _cellHighlight,
                    rowHighlightColor: _cellRowHighlight,
                    colHighlightColor: _cellColHighlight,
                    normalColor: _cellNormal,
                    isHoveredRow: _hoveredRow == logicRow,
                    isHoveredColumn: _hoveredCol == logicCol,
                    rowMoveDirection: _lastRowMoveDirection,
                    colMoveDirection: _lastColMoveDirection,
                  ),
                  child: widget.cells[originalRow][originalCol],
                );
              },
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
            topLeft.dy.clamp(
              _cornerHeight,
              tableSize.height - widget.cellHeight,
            ),
          );
        } else {
          topLeft = Offset(
            topLeft.dx.clamp(_cornerWidth, tableSize.width - widget.cellWidth),
            0,
          );
        }
      }
    }

    final double tableWidth =
        _cornerWidth + (widget.colHeaders?.length ?? 0) * widget.cellWidth;
    final double tableHeight =
        _cornerHeight + (widget.rowHeaders?.length ?? 0) * widget.cellHeight;

    final bool useRowHeaderRoundCorners =
        widget.enableRowHeaderCollapse && widget.rowHeadersCollapsed;
    final bool useColHeaderRoundCorners =
        widget.enableColHeaderCollapse && widget.colHeadersCollapsed;

    return AnimatedBuilder(
      animation: _highlightController,
      builder: (context, child) {
        double highlight = _highlightAnimation.value;
        double elevation = 2 + highlight * 10;

        if (_dragType == DragType.column) {
          final double columnHeight =
              _cornerHeight + _rowOrder.length * widget.cellHeight;
          final List<Widget> columnCells = [
            if (widget.showColHeaders)
              AnimatedContainer(
                duration: _animationDuration,
                curve: Curves.easeInOut,
                width: widget.cellWidth,
                height: widget.cellHeight,
                decoration: BoxDecoration(
                  color: _colHeaderHighlight,
                  borderRadius: useColHeaderRoundCorners
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.colHeaders?[_dragOriginalIndex] ??
                      _defaultColHeaders[_dragOriginalIndex],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
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
            top: tableHeight - columnHeight, // 底部对齐
            width: widget.cellWidth,
            height: columnHeight,
            child: Material(
              elevation: elevation,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: columnCells,
                ),
              ),
            ),
          );
        } else {
          final double rowWidth =
              _cornerWidth + _colOrder.length * widget.cellWidth;
          final List<Widget> rowCells = [
            if (widget.showRowHeaders)
              AnimatedContainer(
                duration: _animationDuration,
                curve: Curves.easeInOut,
                width: widget.cellWidth,
                height: widget.cellHeight,
                decoration: BoxDecoration(
                  color: _rowHeaderHighlight,
                  borderRadius: useRowHeaderRoundCorners
                      ? const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  widget.rowHeaders?[_dragOriginalIndex] ??
                      _defaultRowHeaders[_dragOriginalIndex],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
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
            left: tableWidth - rowWidth, // 右对齐
            top: topLeft.dy,
            width: rowWidth,
            height: widget.cellHeight,
            child: Material(
              elevation: elevation,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: rowCells),
              ),
            ),
          );
        }
      },
    );
  }
}

// 自定义单元格背景绘制器（无圆角）
class _CellBackgroundPainter extends CustomPainter {
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

  _CellBackgroundPainter({
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
  bool shouldRepaint(covariant _CellBackgroundPainter oldDelegate) {
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
