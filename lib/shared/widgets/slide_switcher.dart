import 'package:flutter/material.dart';

/// IMS 标题栏同款多内容切换动画。
///
/// 当 [index] 变化时，新旧内容按滑动方向切换：
/// index 增大 = 向右/下走（新从右下进入，旧向左上退出），
/// index 减小 = 向左/上走（新从左上进入，旧向右下退出）。
/// 首尾循环时方向自然反转。
///
/// [isHorizontal] 决定运动轴，[distanceScale] 控制位移强弱。
class SlideSwitcher extends StatefulWidget {
  final Widget child;
  final int index;
  final bool isHorizontal;
  final double distanceScale;

  const SlideSwitcher({
    super.key,
    required this.child,
    required this.index,
    this.isHorizontal = false,
    this.distanceScale = 0.6,
  });

  @override
  State<SlideSwitcher> createState() => _SlideSwitcherState();
}

class _SlideSwitcherState extends State<SlideSwitcher> {
  int _prevIndex = 0;
  bool _initialized = false;

  @override
  void didUpdateWidget(covariant SlideSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_initialized) {
      _prevIndex = oldWidget.index;
      _initialized = true;
    }
    if (oldWidget.index != widget.index) {
      _prevIndex = oldWidget.index;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final currentIndex = (child.key as ValueKey<int>).value;
        final isCurrent = currentIndex == widget.index;
        final goingRight = widget.index > _prevIndex;
        final sign = (isCurrent == goingRight) ? 1.0 : -1.0;
        final dist = (widget.index - _prevIndex).abs().clamp(1, 10);
        final offset = dist * widget.distanceScale;
        return SlideTransition(
          position: Tween<Offset>(
            begin: widget.isHorizontal
                ? Offset(sign * offset, 0)
                : Offset(0, sign * offset),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey(widget.index), child: widget.child),
    );
  }
}
