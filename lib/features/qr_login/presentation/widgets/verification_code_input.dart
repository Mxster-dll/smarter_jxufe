import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smarter_jxufe/design/JxufeTheme.dart';

/// 通用验证码输入组件。
///
/// 支持：数字输入、多选、Ctrl 操作、剪贴板、`disabled`/`readOnly` 模式、
/// 自动左移填充（带动画）。
class VerificationCodeInput extends StatefulWidget {
  final int length;
  final bool disabled;
  final bool readOnly;
  final double cellSize;
  final double gap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  const VerificationCodeInput({
    super.key,
    this.length = 6,
    this.disabled = false,
    this.readOnly = false,
    this.cellSize = 48,
    this.gap = 10,
    this.onChanged,
    this.onCompleted,
  });

  @override
  State<VerificationCodeInput> createState() => VerificationCodeInputState();
}

class VerificationCodeInputState extends State<VerificationCodeInput>
    with SingleTickerProviderStateMixin {
  List<String?> _digits = [];
  final Set<int> _selected = {};
  int _cursor = 0;
  final FocusNode _focus = FocusNode();
  bool _ctrlDown = false;
  String _prev = '';

  final List<_Snapshot> _history = [];
  final List<_Snapshot> _redoStack = [];
  static const _maxHistory = 50;

  late final AnimationController _blinkCtrl;

  @override
  void initState() {
    super.initState();
    _digits = List.filled(widget.length, null);
    _selected.add(0);
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _blinkCtrl.dispose();
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      if (_selected.isEmpty) _selectOnly(_cursor);
    } else {
      _selected.clear();
    }
    setState(() {});
  }

  // ── 撤销/重做 ──

  void _pushHistory() {
    _history.add(
      _Snapshot(
        digits: List.from(_digits),
        cursor: _cursor,
        selected: Set.from(_selected),
      ),
    );
    if (_history.length > _maxHistory) _history.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_history.isEmpty) return;
    _redoStack.add(
      _Snapshot(
        digits: List.from(_digits),
        cursor: _cursor,
        selected: Set.from(_selected),
      ),
    );
    final snap = _history.removeLast();
    _digits = snap.digits;
    _cursor = snap.cursor;
    _selected
      ..clear()
      ..addAll(snap.selected);
    _notify();
    setState(() {});
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _history.add(
      _Snapshot(
        digits: List.from(_digits),
        cursor: _cursor,
        selected: Set.from(_selected),
      ),
    );
    final snap = _redoStack.removeLast();
    _digits = snap.digits;
    _cursor = snap.cursor;
    _selected
      ..clear()
      ..addAll(snap.selected);
    _notify();
    setState(() {});
  }

  // ── 选择 ──

  void _selectOnly(int i) {
    _selected.clear();
    _selected.add(i.clamp(0, widget.length - 1));
    _cursor = i.clamp(0, widget.length - 1);
  }

  void _selectRange(int a, int b) {
    _selected.clear();
    for (int i = math.min(a, b); i <= math.max(a, b); i++) {
      _selected.add(i);
    }
    _cursor = b;
  }

  void _toggle(int i) {
    if (_selected.contains(i)) {
      _selected.remove(i);
    } else {
      _selected.add(i);
    }
    _cursor = i;
  }

  void _all() {
    _selected.clear();
    for (int i = 0; i < widget.length; i++) {
      _selected.add(i);
    }
  }

  // ── 数据操作 ──

  void _leftAlign() {
    final nonNull = _digits.where((d) => d != null).toList();
    while (nonNull.length < widget.length) {
      nonNull.add(null);
    }
    _digits = nonNull;
  }

  void _notify() {
    final val = _digits.map((d) => d ?? '').join();
    if (val != _prev) {
      _prev = val;
      widget.onChanged?.call(val);
      if (!val.contains('') && val.isNotEmpty) {
        widget.onCompleted?.call(val);
      }
    }
  }

  int get _firstEmpty => _digits.indexWhere((d) => d == null);
  int get _minSel => _selected.isEmpty ? 0 : _selected.reduce(math.min);
  bool get _isContiguous =>
      _selected.length <= 1 ||
      (_selected.reduce(math.max) - _minSel + 1 == _selected.length);

  // ── 数字输入 ──

  void _putDigit(String digit) {
    _pushHistory();
    _digits = List.from(_digits);
    if (_selected.length > 1) {
      for (final i in _selected) {
        _digits[i] = null;
      }
      _digits[_minSel] = digit;
      _leftAlign();
      final fe = _firstEmpty;
      _selectOnly(fe == -1 ? widget.length - 1 : fe);
    } else {
      _digits[_cursor] = digit;
      if (_cursor < widget.length - 1) _selectOnly(_cursor + 1);
    }
    _notify();
    setState(() {});
  }

  void _handleBackspace() {
    _pushHistory();
    if (_selected.length > 1) {
      _digits = List.from(_digits);
      for (final i in _selected) {
        _digits[i] = null;
      }
      _leftAlign();
      final fe = _firstEmpty;
      _selectOnly(fe == -1 ? widget.length - 1 : fe);
      _notify();
      setState(() {});
      return;
    }
    if (_digits[_cursor] != null) {
      _digits = List.from(_digits);
      _digits[_cursor] = null;
      _leftAlign();
      final prev = math.max(_cursor - 1, 0);
      _selectOnly(prev);
      _notify();
      setState(() {});
    } else if (_cursor > 0) {
      // 空格按 Backspace：删除前一格
      _digits = List.from(_digits);
      _digits[_cursor - 1] = null;
      _leftAlign();
      _selectOnly(_cursor - 1);
      _notify();
      setState(() {});
    }
  }

  void _handleDelete() {
    _pushHistory();
    if (_selected.length > 1) {
      _digits = List.from(_digits);
      for (final i in _selected) {
        _digits[i] = null;
      }
      _leftAlign();
      final fe = _firstEmpty;
      _selectOnly(fe == -1 ? widget.length - 1 : fe);
      _notify();
      setState(() {});
      return;
    }
    if (_cursor < widget.length - 1 && _digits[_cursor + 1] != null) {
      _digits = List.from(_digits);
      _digits[_cursor + 1] = null;
      _leftAlign();
      _notify();
      setState(() {});
    }
  }

  void _copy() {
    final sorted = _selected.toList()..sort();
    final indices = _selected.isNotEmpty
        ? sorted
        : List.generate(widget.length, (i) => i);
    final text = indices.map((i) => _digits[i] ?? '').join();
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
    }
  }

  void _cut() {
    _pushHistory();
    _copy();
    if (_selected.isNotEmpty) {
      _digits = List.from(_digits);
      for (final i in _selected) {
        _digits[i] = null;
      }
      _leftAlign();
      _selectOnly(_firstEmpty == -1 ? widget.length - 1 : _firstEmpty);
      _notify();
    } else {
      _digits = List.filled(widget.length, null);
      _selectOnly(0);
      _notify();
    }
    setState(() {});
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    final digits = data!.text!.replaceAll(RegExp(r'\D'), '').split('');
    if (digits.isEmpty) return;

    _pushHistory();
    _digits = List.from(_digits);
    int idx = _minSel;
    for (final d in digits) {
      if (idx >= widget.length) break;
      _digits[idx] = d;
      idx++;
    }
    _leftAlign();
    final fe = _firstEmpty;
    _selectOnly(fe == -1 ? widget.length - 1 : fe);
    _notify();
    setState(() {});
  }

  // ── 键盘 ──

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.disabled) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      final key = event.logicalKey;

      if (key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        _ctrlDown = true;
        return KeyEventResult.handled;
      }

      final digit = _digitFromKey(key);
      if (digit != null) {
        if (widget.readOnly) return KeyEventResult.handled;
        _putDigit(digit);
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.backspace) {
        if (widget.readOnly) return KeyEventResult.handled;
        _handleBackspace();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.delete) {
        if (widget.readOnly) return KeyEventResult.handled;
        _handleDelete();
        return KeyEventResult.handled;
      }

      if (_ctrlDown) {
        switch (key) {
          case LogicalKeyboardKey.keyA:
            _all();
            setState(() {});
            return KeyEventResult.handled;
          case LogicalKeyboardKey.keyC:
            _copy();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.keyX:
            if (widget.readOnly) return KeyEventResult.handled;
            _cut();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.keyV:
            if (widget.readOnly) return KeyEventResult.handled;
            _paste();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.keyZ:
            _undo();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.keyY:
            _redo();
            return KeyEventResult.handled;
        }
      }

      if (key == LogicalKeyboardKey.arrowLeft) {
        if (_cursor > 0) _selectOnly(_cursor - 1);
        setState(() {});
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        if (_cursor < widget.length - 1) _selectOnly(_cursor + 1);
        setState(() {});
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.home) {
        _selectOnly(0);
        setState(() {});
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.end) {
        _selectOnly(widget.length - 1);
        setState(() {});
        return KeyEventResult.handled;
      }

      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        _ctrlDown = false;
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String? _digitFromKey(LogicalKeyboardKey key) {
    final id = key.keyId;
    if (id >= LogicalKeyboardKey.digit0.keyId &&
        id <= LogicalKeyboardKey.digit9.keyId) {
      return key.keyLabel;
    }
    if (id >= LogicalKeyboardKey.numpad0.keyId &&
        id <= LogicalKeyboardKey.numpad9.keyId) {
      return String.fromCharCode(id - LogicalKeyboardKey.numpad0.keyId + 0x30);
    }
    return null;
  }

  // ── 触摸 ──

  int? _dragStart;

  void _onCellTapDown(int i) {
    if (widget.disabled) return;
    _focus.requestFocus();
    if (_ctrlDown) {
      _toggle(i);
    } else if (_digits[i] != null) {
      _selectOnly(i);
    } else {
      _selectOnly(_firstEmpty == -1 ? widget.length - 1 : _firstEmpty);
    }
    _dragStart = i;
    setState(() {});
  }

  void _onCellPointerMove(int i) {
    if (widget.disabled || _dragStart == null) return;
    if (_ctrlDown) return; // Ctrl+拖动简化为已处理（toggle 在按下时处理）
    _selectRange(_dragStart!, i);
    setState(() {});
  }

  void _onCellPointerUp() {
    _dragStart = null;
  }

  // ── UI ──

  @override
  Widget build(BuildContext context) {
    final showCursor =
        _focus.hasFocus &&
        !widget.disabled &&
        !widget.readOnly &&
        _selected.length == 1 &&
        _digits[_cursor] == null;

    const r = 12.0;
    final selC = JxufeTheme.primaryColor;
    final normC = JxufeTheme.borderColor;
    final w = widget.cellSize;
    final n = widget.length;

    Widget mkVer(Color color, int col, double t, double b, {double w2 = 1}) {
      return Positioned(
        left: col * w - (w2 - 1) / 2,
        top: t,
        bottom: b,
        child: Container(width: w2, color: color),
      );
    }

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: SizedBox(
        width: n * w,
        height: w,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── 格子背景（无边框，仅圆角背景）──
            ...List.generate(n, (i) {
              BorderRadiusGeometry br;
              if (n == 1) {
                br = BorderRadius.circular(r);
              } else if (i == 0) {
                br = const BorderRadius.only(
                  topLeft: Radius.circular(r),
                  bottomLeft: Radius.circular(r),
                );
              } else if (i == n - 1) {
                br = const BorderRadius.only(
                  topRight: Radius.circular(r),
                  bottomRight: Radius.circular(r),
                );
              } else {
                br = BorderRadius.zero;
              }
              return Positioned(
                left: i * w,
                child: IgnorePointer(
                  child: Container(
                    width: w,
                    height: w,
                    decoration: BoxDecoration(
                      color: widget.disabled
                          ? JxufeTheme.inputBgColor
                          : Colors.white,
                      borderRadius: br,
                    ),
                  ),
                ),
              );
            }),
            // ── 数字 + 光标 ──
            ...List.generate(n, (i) {
              final digit = _digits[i];
              final isCursor = showCursor && i == _cursor;
              return Positioned(
                left: i * w,
                top: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => _onCellTapDown(i),
                  onPanUpdate: (_) => _onCellPointerMove(i),
                  onPanEnd: (_) => _onCellPointerUp(),
                  child: SizedBox(
                    width: w,
                    height: w,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (digit != null)
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, animation) {
                              return SlideTransition(
                                position:
                                    Tween<Offset>(
                                      begin: const Offset(0.3, 0),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOut,
                                      ),
                                    ),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              );
                            },
                            child: Text(
                              digit,
                              key: ValueKey('$i-$digit'),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: widget.disabled
                                    ? JxufeTheme.hintColor
                                    : JxufeTheme.textColor,
                              ),
                            ),
                          ),
                        if (isCursor)
                          AnimatedBuilder(
                            animation: _blinkCtrl,
                            builder: (_, child) => Opacity(
                              opacity: _blinkCtrl.value,
                              child: child,
                            ),
                            child: Container(width: 2, height: 24, color: selC),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            // ── 外框圆角 border（替代 mkHor + 外侧竖线）──
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(r),
                    border: Border.all(color: normC),
                  ),
                ),
              ),
            ),
            // ── 内部竖线：仅连续多选时相邻格之间蓝色加粗 ──
            for (int col = 1; col < n; col++)
              mkVer(
                _isContiguous &&
                        _selected.length > 1 &&
                        _selected.contains(col - 1) &&
                        _selected.contains(col)
                    ? selC
                    : normC,
                col,
                0,
                0,
                w2:
                    _isContiguous &&
                        _selected.length > 1 &&
                        _selected.contains(col - 1) &&
                        _selected.contains(col)
                    ? 2.0
                    : 1.0,
              ),
            // ── 高亮覆盖 (单选同时动画：位置 + 圆角形状) ──
            if (_selected.length == 1)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                left: _selected.first * w,
                top: 0,
                width: w,
                height: w,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      borderRadius: _selected.first == 0
                          ? const BorderRadius.only(
                              topLeft: Radius.circular(r),
                              bottomLeft: Radius.circular(r),
                            )
                          : _selected.first == n - 1
                          ? const BorderRadius.only(
                              topRight: Radius.circular(r),
                              bottomRight: Radius.circular(r),
                            )
                          : BorderRadius.zero,
                      border: Border.all(color: selC, width: 2),
                    ),
                  ),
                ),
              )
            else if (_selected.length > 1) ...[
              if (_isContiguous)
                // 连续选中：单个合并框
                Positioned(
                  left: _minSel * w,
                  top: 0,
                  width: (_selected.reduce(math.max) - _minSel + 1) * w,
                  height: w,
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.only(
                          topLeft: _minSel == 0
                              ? const Radius.circular(r)
                              : Radius.zero,
                          bottomLeft: _minSel == 0
                              ? const Radius.circular(r)
                              : Radius.zero,
                          topRight: _selected.contains(n - 1)
                              ? const Radius.circular(r)
                              : Radius.zero,
                          bottomRight: _selected.contains(n - 1)
                              ? const Radius.circular(r)
                              : Radius.zero,
                        ),
                        border: Border.all(color: selC, width: 2),
                      ),
                    ),
                  ),
                )
              else
                // 非连续：逐格高亮，相邻格不重复画共享边
                for (final i in _selected)
                  Positioned(
                    left: i * w,
                    top: 0,
                    width: w,
                    height: w,
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.only(
                            topLeft: i == 0
                                ? const Radius.circular(r)
                                : Radius.zero,
                            bottomLeft: i == 0
                                ? const Radius.circular(r)
                                : Radius.zero,
                            topRight: i == n - 1
                                ? const Radius.circular(r)
                                : Radius.zero,
                            bottomRight: i == n - 1
                                ? const Radius.circular(r)
                                : Radius.zero,
                          ),
                          border: Border(
                            top: BorderSide(color: selC, width: 2),
                            bottom: BorderSide(color: selC, width: 2),
                            left: i == 0 || !_selected.contains(i - 1)
                                ? BorderSide(color: selC, width: 2)
                                : BorderSide.none,
                            right: BorderSide(color: selC, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  String get code => _digits.map((d) => d ?? '').join();

  void clear() {
    _digits = List.filled(widget.length, null);
    _selectOnly(0);
    _notify();
    setState(() {});
  }
}

class _Snapshot {
  final List<String?> digits;
  final int cursor;
  final Set<int> selected;
  const _Snapshot({
    required this.digits,
    required this.cursor,
    required this.selected,
  });
}
