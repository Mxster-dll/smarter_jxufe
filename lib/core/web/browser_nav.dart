/// 内嵌网页（WebView）的**浏览器原生前进 / 后退**接口 —— 给顶部的全局后退/前进按钮用。
///
/// 用户 2026-10-10 二十九轮：「我不希望你手动记录，我只希望把浏览器原生的前进回退融合进来」。
///
/// **为什么不记进 `route_history`**：网页内部跳转是一棵很深的树（门户点几层就七八个地址），
/// 手动把每个 URL 记成一笔会把顶部那份"访问过的位置"冲垮；而且 WebView **自己就有**
/// 前进/后退（`canGoBack` / `goBack` / `canGoForward` / `goForward`），本就不该由我们再存一遍。
///
/// **做法**：当前可见的内嵌网页在挂载时把自己登记成 [_active]，顶部那两枚按钮在动手之前
/// 先问一句 [browserNavService]：
/// - 能回网页 → 回网页（**不碰** `route_history`）；
/// - 回不了了 → 才走原来的位置回退。
///
/// 于是一个后退键只有一种读法：「先退网页、退到底再退应用」—— 与手机浏览器一致。
library;

import 'package:flutter/foundation.dart';

/// 内嵌网页此刻的前进 / 后退能力。
@immutable
class BrowserNavState {
  const BrowserNavState({
    required this.canGoBack,
    required this.canGoForward,
    this.backLabel,
    this.forwardLabel,
  });

  static const BrowserNavState none = BrowserNavState(
    canGoBack: false,
    canGoForward: false,
  );

  final bool canGoBack;
  final bool canGoForward;

  /// 目标页标题（拿得到就给，用来给顶部按钮挂提示；拿不到就 null）。
  final String? backLabel;
  final String? forwardLabel;

  bool get any => canGoBack || canGoForward;

  @override
  bool operator ==(Object other) =>
      other is BrowserNavState &&
      other.canGoBack == canGoBack &&
      other.canGoForward == canGoForward &&
      other.backLabel == backLabel &&
      other.forwardLabel == forwardLabel;

  @override
  int get hashCode => Object.hash(canGoBack, canGoForward, backLabel, forwardLabel);

  @override
  String toString() =>
      'BrowserNavState(back: $canGoBack, forward: $canGoForward)';
}

/// 当前可见内嵌网页的浏览器导航口子（全局单例）。
///
/// ⚠ **同一时刻只登记一个**：页面在 `didChangeDependencies` 里按
/// `ModalRoute.of(context)?.isCurrent` 判自己是不是**可见的那一层**，可见才登记；
/// 被别的页面盖住时 `isCurrent` 变假 → 自动让位（否则被盖住的那层会继续抢顶部按钮）。
class BrowserNavService extends ChangeNotifier {
  VoidCallback? _onBack;
  VoidCallback? _onForward;
  BrowserNavState _state = BrowserNavState.none;

  /// 此刻有没有内嵌网页在管顶部的前进/后退。
  bool get isActive => _onBack != null || _onForward != null;

  BrowserNavState get state => _state;

  /// 内嵌网页挂上自己（[onBack] / [onForward] 至少要给一个）。
  void attach({
    VoidCallback? onBack,
    VoidCallback? onForward,
    BrowserNavState state = BrowserNavState.none,
  }) {
    _onBack = onBack;
    _onForward = onForward;
    _setState(state);
  }

  /// 内嵌网页更新自己此刻的能力（每次导航事件后调一次）。
  void update(BrowserNavState state) => _setState(state);

  /// 内嵌网页离场（dispose / 被盖住）。
  void detach() {
    _onBack = null;
    _onForward = null;
    _setState(BrowserNavState.none);
  }

  void _setState(BrowserNavState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  /// 顶部「后退」：能回网页就回网页，返回 true = **已经处理掉了**，调用方别再动
  /// `route_history`。回不了返回 false（调用方照旧走位置回退）。
  bool goBack() {
    final action = _onBack;
    if (action == null || !_state.canGoBack) return false;
    action();
    return true;
  }

  /// 顶部「前进」：同上（能往网页里前进就先前进）。
  bool goForward() {
    final action = _onForward;
    if (action == null || !_state.canGoForward) return false;
    action();
    return true;
  }
}

/// 全局单例。
///
/// **刻意用 `ChangeNotifier` + 全局单例而不是 Riverpod provider**：页面的
/// `dispose` 里要能可靠地 `detach()`，而 provider 在页面销毁时机上不比这个更稳；
/// 顶部那两枚按钮本来也只需要"变了自己重建"这一件事（`ListenableBuilder` 就够）。
final BrowserNavService browserNavService = BrowserNavService();
