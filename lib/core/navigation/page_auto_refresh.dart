/// 页面「进入 / 从别的页面返回 / App 回前台」自动刷新。
///
/// 背景（用户 2026-09-14 反馈）：畅想之星总览卡与蛟湖阅读的进度卡都**不会自己更新**
/// —— 前者要手动点「重新获取令牌 / 统一身份认证」、后者要从头重进页面。根因是这些
/// 数据都挂在缓存型 `FutureProvider`（`cxstarOverviewProvider` /
/// `readCreditProgressProvider` / `jhReadRecordsProvider` …）上：provider 只要不被
/// 失效就一直返回同一份缓存，页面重建也不会重新取数。
///
/// 所以约定：**凡是展示这类缓存数据的页面，都挂一个 [PageAutoRefresher]**，
/// 在 [`PageAutoRefresher.onRefresh`] 里 `ref.invalidate(...)` 自己关心的 provider。
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全局路由观察者：在 `lib/main.dart` 的 `MaterialApp.navigatorObservers` 注册。
///
/// 这是「从子页面返回时刷新」的机制来源 —— 页面无需 await 每一个 `Navigator.push`，
/// 只要订阅本观察者，上层路由被弹出时会收到 `RouteAware.didPopNext()`。
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// 页面自动刷新的挂件（组合式，**不用 mixin**）。
///
/// 为什么不用 mixin：`RouteAware` 与 `WidgetsBindingObserver` 都被声明成接口形态，
/// mixin 里的 `this` 无法传给 `RouteObserver.subscribe(...)` / `addObserver(...)`；
/// 而用 `implements` 又会被迫实现它们那几十个回调（且随 Flutter 版本增加）。
/// 组合一个真正同时实现两者的类最省事：谁需要就在自己的 State 里持有一个。
///
/// ```dart
/// class _FooState extends ConsumerState<Foo> {
///   late final PageAutoRefresher _autoRefresh =
///       PageAutoRefresher(onRefresh: _refresh);
///
///   @override
///   void initState() { super.initState(); _autoRefresh.start(); }
///
///   @override
///   void didChangeDependencies() {
///     super.didChangeDependencies();
///     _autoRefresh.subscribeRoute(context);
///   }
///
///   @override
///   void dispose() { _autoRefresh.dispose(); super.dispose(); }
///
///   void _refresh() {
///     if (!mounted) return;
///     invalidateIfLoaded(ref, someProvider);
///   }
/// }
/// ```
class PageAutoRefresher with RouteAware, WidgetsBindingObserver {
  PageAutoRefresher({required this.onRefresh});

  /// 刷新动作（页面里通常是若干 [invalidateIfLoaded]）。
  final VoidCallback onRefresh;

  bool _started = false;
  bool _routeSubscribed = false;
  bool _disposed = false;

  /// 在 `initState` 里调用：注册前后台观察者，并在首帧后刷新一次。
  ///
  /// 首帧也要刷：首次进入时 provider 可能还带着上个会话的缓存值。
  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fire());
  }

  /// 在 `didChangeDependencies` 里调用：订阅本页所在路由。
  ///
  /// （不能在 `initState` 里取 `ModalRoute.of(context)`，那时还读不到 InheritedWidget。）
  void subscribeRoute(BuildContext context) {
    if (_disposed) return;
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) {
      // RouteObserver 内部用 Set 存监听者 → 重复 subscribe 不会重复回调。
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
  }

  /// 在 `dispose` 里调用。
  void dispose() {
    _disposed = true;
    if (_routeSubscribed) appRouteObserver.unsubscribe(this);
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
    _routeSubscribed = false;
  }

  void _fire() {
    if (_disposed) return;
    onRefresh();
  }

  /// 上层路由被弹出 → 本页重新可见（从阅读器 / 书架 / 明细页返回）。
  @override
  void didPopNext() => _fire();

  /// App 回到前台（可能隔了很久，缓存早已过期）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _fire();
  }
}

/// 失效一个异步 provider，但**跳过它首次加载尚未完成**的场合。
///
/// 原因：页面 `build` 里的 `ref.watch` 已经发起了第一次请求，此时再 `invalidate`
/// 只会把同一个请求重发一遍（白耗流量、还多一次 loading 闪烁）。只有**已有缓存值**
/// （再次进入页面 / 从子页面返回 / 回前台）才需要强制重取。
void invalidateIfLoaded<T>(WidgetRef ref, FutureProvider<T> provider) {
  final current = ref.read(provider);
  if (current.isLoading && !current.hasValue) return;
  ref.invalidate(provider);
}
