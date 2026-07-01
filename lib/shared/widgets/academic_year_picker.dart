import 'package:flutter/material.dart';

/// 横向滑动学年选择器。
///
/// 拖动年份条后松手自动吸附到视窗中央的学年对。
/// [onChanged] 返回选中学年的起始年份，如选中 2022-2023 学年则返回 2022。
class AcademicYearPicker extends StatefulWidget {
  final int startYear;
  final int endYear;
  final int initialYear;
  final ValueChanged<int>? onChanged;

  const AcademicYearPicker({
    super.key,
    required this.startYear,
    required this.endYear,
    this.initialYear = 2025,
    this.onChanged,
  });

  @override
  State<AcademicYearPicker> createState() => _AcademicYearPickerState();
}

class _AcademicYearPickerState extends State<AcademicYearPicker> {
  static const double _yearW = 56.0;
  static const double _dashW = 10.0;
  double get _step => _yearW + _dashW;

  double _offset = 0.0;
  double _dragStartX = 0.0;
  double _dragStartOffset = 0.0;
  int _selected = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialYear.clamp(widget.startYear, widget.endYear);
  }

  double _offsetOf(int y) => (y - widget.startYear) * _step;

  int _yearAt(double offset) {
    final i = (offset / _step).round();
    return (widget.startYear + i).clamp(widget.startYear, widget.endYear);
  }

  double get _maxOffset =>
      _offsetOf(widget.endYear - 1).clamp(0.0, double.infinity);

  void _updateSelected() {
    final y = _yearAt(_offset);
    if (y != _selected) {
      _selected = y;
    }
  }

  void _snap() {
    final clamped = _offset.clamp(0.0, _maxOffset);
    final y = _yearAt(clamped);
    _selected = y;
    widget.onChanged?.call(y);
    _animateTo(_offsetOf(y));
  }

  void _animateTo(double target) {
    const duration = Duration(milliseconds: 200);
    const steps = 10;
    final start = _offset;
    final delta = target - start;
    int tick = 0;
    Future.doWhile(() async {
      await Future.delayed(duration ~/ steps);
      if (!mounted) return false;
      tick++;
      setState(() => _offset = start + delta * (tick / steps));
      return tick < steps;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final n = widget.endYear - widget.startYear + 1;
    final highlightW = _yearW * 2 + _dashW; // 年 - 年

    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (context, c) {
          final viewW = c.maxWidth;
          final pad = ((viewW - highlightW) / 2).clamp(0.0, double.infinity);

          if (!_initialized && viewW > 0) {
            _initialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _offset = _offsetOf(_selected));
            });
          }

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (d) {
              _dragStartX = d.localPosition.dx;
              _dragStartOffset = _offset;
            },
            onHorizontalDragUpdate: (d) {
              setState(() {
                _offset = _dragStartOffset - (d.localPosition.dx - _dragStartX);
                _updateSelected();
              });
            },
            onHorizontalDragEnd: (_) => _snap(),
            child: ClipRect(
              child: Stack(
                children: [
                  // 中央高亮框
                  Positioned(
                    left: pad,
                    top: 2,
                    bottom: 2,
                    child: IgnorePointer(
                      child: Container(
                        width: highlightW,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: t.colorScheme.error.withValues(alpha: 0.5),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  // 年份 + 连字符列表
                  Positioned(
                    left: pad - _offset,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      children: [
                        for (int i = 0; i < n; i++) ...[
                          SizedBox(
                            width: _yearW,
                            child: _yearItem(
                              widget.startYear + i,
                              t,
                              highlight:
                                  widget.startYear + i == _selected ||
                                  widget.startYear + i == _selected + 1,
                            ),
                          ),
                          if (i < n - 1)
                            SizedBox(
                              width: _dashW,
                              child: _dashItem(
                                t,
                                highlight: widget.startYear + i == _selected,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  // 左右渐变遮罩
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: _fade(t.scaffoldBackgroundColor, true),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: _fade(t.scaffoldBackgroundColor, false),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _yearItem(int y, ThemeData t, {required bool highlight}) {
    return Center(
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 150),
        style: TextStyle(
          fontSize: highlight ? 18 : 13,
          fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
          color: highlight
              ? t.colorScheme.error
              : t.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
        child: Text('$y'),
      ),
    );
  }

  Widget _dashItem(ThemeData t, {required bool highlight}) {
    return Center(
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 150),
        style: TextStyle(
          fontSize: highlight ? 18 : 13,
          fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
          color: highlight
              ? t.colorScheme.error
              : t.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
        child: const Text('-'),
      ),
    );
  }

  Widget _fade(Color bg, bool left) => Container(
    width: 32,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: left ? Alignment.centerLeft : Alignment.centerRight,
        end: left ? Alignment.centerRight : Alignment.centerLeft,
        colors: [bg, bg.withValues(alpha: 0)],
      ),
    ),
  );
}
