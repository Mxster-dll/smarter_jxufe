// 本文件是 `lib/design/window_chrome/` 拆分件之一 —— 文件地图见 docs/agents/43 的 §43.5。
// 公开入口仍是 `package:smarter_jxufe/design/window_title_bar.dart`（桶文件，对外零改动）。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 标题栏里的一个「交互区」：量到自己的矩形就交给原生（客户区，原生不接管）。
///
/// ⚠ 上报放在 `paint` 里：`AnimatedAlign` / `AnimatedContainer` 只驱动 RenderObject、
/// **不重建 State** —— 若只在 `build` 里量，动画期间原生拿的还是旧矩形（按钮滑走了、
/// 点到旧位置才响应；实测踩过）。这里发现矩形变了就回调一次 `onMeasured` 补上报。
class TitleBarRegion extends SingleChildRenderObjectWidget {
  const TitleBarRegion({
    super.key,
    required this.barKey,
    required this.token,
    required this.sink,
    required this.enabled,
    required this.onMeasured,
    super.child,
  });

  /// 标题栏根节点的 key —— 上报矩形时以**它的坐标系**为准（见 `paint` 里的注释）。
  final GlobalKey barKey;

  final Object token;
  final Map<Object, Rect> sink;
  final bool enabled;
  final VoidCallback onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderTitleBarRegion(
        barKey: barKey,
        token: token,
        sink: sink,
        enabled: enabled,
        onMeasured: onMeasured,
      );

  @override
  void updateRenderObject(BuildContext context, RenderTitleBarRegion renderObject) {
    renderObject
      ..barKey = barKey
      ..token = token
      ..sink = sink
      ..enabled = enabled
      ..onMeasured = onMeasured;
  }
}

class RenderTitleBarRegion extends RenderProxyBox {
  RenderTitleBarRegion({
    required this.barKey,
    required this.token,
    required this.sink,
    required this.enabled,
    required this.onMeasured,
  });

  GlobalKey barKey;
  Object token;
  Map<Object, Rect> sink;
  bool enabled;
  VoidCallback onMeasured;
  Rect? _last;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (enabled) {
      // ⚠ 一律折算到**标题栏的坐标系**再上报：各区挂在不同的父级（`AnimatedAlign`）下，
      // 父级相对坐标彼此不同源、全局坐标在测试里又会被窗口原点带偏 ✗ —— 而原生按这份
      // 名单判命中，必须**同一个坐标系**（2026-10-10 重构后实测：两个交互区被报成完全重叠）。
      final barBox = barKey.currentContext?.findRenderObject() as RenderBox?;
      final rect = barBox == null
          ? (offset & size)
          : (localToGlobal(Offset.zero, ancestor: barBox) & size);
      if (rect != _last) {
        _last = rect;
        sink[token] = rect;
        onMeasured();
      }
    } else if (_last != null) {
      _last = null;
      sink.remove(token);
      onMeasured();
    }
    super.paint(context, offset);
  }

  @override
  void detach() {
    sink.remove(token);
    super.detach();
  }
}
