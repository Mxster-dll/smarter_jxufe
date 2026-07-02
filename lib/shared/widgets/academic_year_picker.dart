import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 横向滑动学年选择器。
///
/// 组件尺寸等于高亮框尺寸（122×44），年份溢出到组件外。
/// [hovered] 由父级注入，控制是否展开完整交互。
class AcademicYearPicker extends StatefulWidget {
  final int startYear;
  final int endYear;
  final int initialYear;
  final ValueChanged<int>? onChanged;
  final ValueChanged<bool>? onHoverChanged;

  const AcademicYearPicker({
    super.key,
    required this.startYear,
    required this.endYear,
    this.initialYear = 2025,
    this.onChanged,
    this.onHoverChanged,
  });

  @override
  State<AcademicYearPicker> createState() => _AcademicYearPickerState();
}

class _AcademicYearPickerState extends State<AcademicYearPicker> {
  static const double _yearW = 56.0;
  static const double _dashW = 10.0;
  double get _step => _yearW + _dashW;
  double get _highlightW => _yearW * 2 + _dashW;

  double _offset = 0.0;
  double _dragStartX = 0.0;
  double _dragStartOffset = 0.0;
  int _selected = 0;
  bool _hovered = false;
  bool _dragging = false;
  bool _mouseLeft = false;

  bool get _expanded => _hovered || _dragging;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialYear.clamp(widget.startYear, widget.endYear);
    _offset = _offsetOf(_selected);
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
      setState(() => _selected = y);
    }
  }

  void _snap() {
    final y = _yearAt(_offset.clamp(0.0, _maxOffset));
    _selected = y;
    widget.onChanged?.call(y);
    _animateTo(_offsetOf(y));
  }

  void _animateTo(double target) {
    const d = Duration(milliseconds: 200);
    const steps = 10;
    final start = _offset;
    final delta = target - start;
    int tick = 0;
    Future.doWhile(() async {
      await Future.delayed(d ~/ steps);
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

    return Listener(
      onPointerSignal: _hovered && !_dragging
          ? (e) {
              if (e is PointerScrollEvent) {
                final dir = e.scrollDelta.dy > 0 ? 1 : -1;
                final targetYear = (_selected + dir).clamp(
                  widget.startYear,
                  widget.endYear,
                );
                if (targetYear != _selected) {
                  _selected = targetYear;
                  widget.onChanged?.call(targetYear);
                  _animateTo(_offsetOf(targetYear));
                }
              }
            }
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _expanded
            ? (d) {
                _dragStartX = d.localPosition.dx;
                _dragStartOffset = _offset;
                _dragging = true;
              }
            : null,
        onHorizontalDragUpdate: _expanded
            ? (d) {
                setState(() {
                  _offset =
                      _dragStartOffset - (d.localPosition.dx - _dragStartX);
                  _updateSelected();
                });
              }
            : null,
        onHorizontalDragEnd: _expanded
            ? (_) {
                _dragging = false;
                _snap();
                if (_mouseLeft) {
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted && _mouseLeft && !_dragging) {
                      setState(() => _hovered = false);
                      widget.onHoverChanged?.call(false);
                    }
                  });
                }
              }
            : null,
        child: SizedBox(
          width: _highlightW + 4,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 年份 + 连字符列表（溢出组件外）
              Positioned(
                left: -_offset + 2,
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
                          dimmed: !_expanded,
                        ),
                      ),
                      if (i < n - 1)
                        SizedBox(
                          width: _dashW,
                          child: _dashItem(
                            t,
                            highlight: widget.startYear + i == _selected,
                            dimmed: !_expanded,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              // 高亮框 + hover 检测
              MouseRegion(
                onEnter: (_) {
                  _mouseLeft = false;
                  setState(() => _hovered = true);
                  widget.onHoverChanged?.call(true);
                },
                onExit: (_) {
                  _mouseLeft = true;
                  if (!_dragging) {
                    setState(() => _hovered = false);
                    widget.onHoverChanged?.call(false);
                  }
                },
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _expanded ? 1.0 : 0.0,
                  child: IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _yearItem(
    int y,
    ThemeData t, {
    required bool highlight,
    bool dimmed = false,
  }) {
    final visible = highlight || !dimmed;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: visible ? 1.0 : 0.0,
      child: Center(
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
      ),
    );
  }

  Widget _dashItem(
    ThemeData t, {
    required bool highlight,
    bool dimmed = false,
  }) {
    final visible = highlight || !dimmed;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: visible ? 1.0 : 0.0,
      child: Center(
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
      ),
    );
  }
}
