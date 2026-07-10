import 'package:flutter/material.dart';

/// 转场方向
enum CarouselDirection { forward, backward }

/// 切换模式
enum TransitionMode {
  fullChainAuto,
  shortestPath,
  forwardOnly,
  backwardOnly,
  endpoints,
}

/// 外部控制器，命令式 API
class SlideCarouselController {
  final int totalItems;
  final TransitionMode mode;
  void Function(int target, CarouselDirection dir)? _onAnimate;

  SlideCarouselController({
    required this.totalItems,
    this.mode = TransitionMode.fullChainAuto,
  });

  int _index = 0;
  int get currentIndex => _index;

  void jumpTo(int index) => _index = index.clamp(0, totalItems - 1);

  void animateTo(int target) {
    target = target.clamp(0, totalItems - 1);
    _onAnimate?.call(target, _resolve(_index, target));
    _index = target;
  }

  void forward(int n) =>
      _direct((_index + n) % totalItems, CarouselDirection.forward);
  void backward(int n) => _direct(
    (_index - n % totalItems + totalItems) % totalItems,
    CarouselDirection.backward,
  );
  void next() => forward(1);
  void previous() => backward(1);

  void _direct(int target, CarouselDirection dir) {
    target = target.clamp(0, totalItems - 1);
    _onAnimate?.call(target, dir);
    _index = target;
  }

  CarouselDirection _resolve(int from, int to) {
    if (from == to) return CarouselDirection.forward;
    switch (mode) {
      case TransitionMode.endpoints:
        return from < to
            ? CarouselDirection.forward
            : CarouselDirection.backward;
      case TransitionMode.forwardOnly:
        return CarouselDirection.forward;
      case TransitionMode.backwardOnly:
        return CarouselDirection.backward;
      case TransitionMode.shortestPath:
        final f = (to - from + totalItems) % totalItems;
        final b = (from - to + totalItems) % totalItems;
        return f <= b ? CarouselDirection.forward : CarouselDirection.backward;
      case TransitionMode.fullChainAuto:
        return from < to
            ? CarouselDirection.forward
            : CarouselDirection.backward;
    }
  }
}

/// 转场动画组件
class CarouselSwitcher extends StatefulWidget {
  final int totalItems;
  final SlideCarouselController? controller;
  final Widget Function(BuildContext, int) itemBuilder;
  final bool isHorizontal;
  final double distanceScale;

  const CarouselSwitcher({
    super.key,
    required this.totalItems,
    this.controller,
    required this.itemBuilder,
    this.isHorizontal = false,
    this.distanceScale = 0.6,
  });

  @override
  State<CarouselSwitcher> createState() => _CarouselSwitcherState();
}

class _CarouselSwitcherState extends State<CarouselSwitcher> {
  int _display = 0;
  int _prev = 0;
  CarouselDirection _dir = CarouselDirection.forward;

  @override
  void initState() {
    super.initState();
    final c =
        widget.controller ??
        SlideCarouselController(totalItems: widget.totalItems);
    c._onAnimate = (target, dir) {
      _prev = _display;
      _dir = dir;
      _display = target;
      setState(() {});
    };
    _display = c.currentIndex;
    _prev = _display;
  }

  @override
  Widget build(BuildContext context) {
    final goingRight = _dir == CarouselDirection.forward;
    final dist = ((_display - _prev).abs() % widget.totalItems).clamp(1, 10);
    final offset = dist * widget.distanceScale;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final isCurrent = (child.key as ValueKey<int>).value == _display;
        final sig = (isCurrent == goingRight) ? 1.0 : -1.0;
        return SlideTransition(
          position: Tween<Offset>(
            begin: widget.isHorizontal
                ? Offset(sig * offset, 0)
                : Offset(0, sig * offset),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(_display),
        child: widget.itemBuilder(context, _display),
      ),
    );
  }
}
