/// **页面 → 全局标题栏**的动作插槽（2026-10-09 立）。
///
/// 背景：隐藏系统标题栏之后，应用顶部那一条标题栏是**全局**的（挂在
/// `MaterialApp.builder` 上、在 Navigator 之上），所以它**不知道当前是哪一页**；
/// 而首页宫格视图的设置 / 头像必须画在标题栏右侧（用户 2026-10-09 裁定：
/// 「首页品牌栏并入标题栏」）。两边就用这个控制器对接：页面说自己要不要出现在
/// 标题栏里、以及怎么画。
///
/// 为什么不是 Riverpod 的 state：标题栏是页面的**祖先**（在 Navigator 之上），
/// 页面在自己的 `build` 里改 provider 状态 = 「build 期间改祖先状态」→ 框架报错。
/// 这里用 `ChangeNotifier` + **构建后再通知**（页面在 post-frame 里调 [update]），
/// 代价是最多晚一帧出现，肉眼不可见（第一帧本来也在开屏动画里）。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 标题栏右侧动作区的状态：显不显示 + 怎么画。
class WindowTitleBarActions extends ChangeNotifier {
  bool _visible = false;
  WidgetBuilder? _builder;
  bool _leadingVisible = false;
  WidgetBuilder? _leadingBuilder;

  /// 是否显示（`true` 且给过 builder 才画）。
  bool get visible => _visible && _builder != null;

  /// 画法；由调用页提供（标题栏只负责摆位置）。
  WidgetBuilder? get builder => _builder;

  /// 页面发布自己的动作。
  ///
  /// [visible] 没变就**不通知**（页面每帧都会调一次，通知了就等于每帧重建标题栏）；
  /// builder 仍然换新 —— 它的闭包引用的是页面自己的 state，页面重建时它本来就该是新的。
  /// 品牌组**最前面**那一枚（2026-10-09 · 用户：「我希望展开/收起侧边栏的按钮放在标题栏」）。
  ///
  /// 与 [visible] 那组分开：这一组紧贴品牌、画在 logo 左边 —— 侧栏在左时它就落在侧栏
  /// 正上方（跟着品牌一起换边，见 `window_title_bar.dart` 的两组 `AnimatedAlign`）。
  bool get leadingVisible => _leadingVisible && _leadingBuilder != null;

  /// 品牌组前面那一枚的画法。
  WidgetBuilder? get leadingBuilder => _leadingBuilder;

  void update({
    required bool visible,
    WidgetBuilder? builder,
    bool leadingVisible = false,
    WidgetBuilder? leadingBuilder,
  }) {
    _builder = builder;
    _leadingBuilder = leadingBuilder;
    if (_visible == visible && _leadingVisible == leadingVisible) return;
    _visible = visible;
    _leadingVisible = leadingVisible;
    notifyListeners();
  }

  /// 页面退出 / 不再是当前页时收回动作。
  void clear() =>
      update(visible: false, builder: null, leadingVisible: false, leadingBuilder: null);
}

/// 全局唯一实例（`main()` 的组装根与首页共用）。
final windowTitleBarActionsProvider = ChangeNotifierProvider<WindowTitleBarActions>(
  (ref) => WindowTitleBarActions(),
);
