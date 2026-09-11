import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/home_widget/data/home_widget_sync.dart';
import 'package:smarter_jxufe/features/home_widget/presentation/home_widget_launcher.dart';

/// 桌面小组件同步触发点（包在首页外层）。
///
/// 首页与仪表盘都是无状态 Widget，挂不了生命周期回调，因此单独做一层
/// 极薄的有状态包装：
/// - 首帧后：消费「点小组件唤起」的待处理路由，并推一次快照；
/// - 每次回到前台（含解锁后打开 App）：重推快照（电费余额与成绩都可能变了）。
///
/// 真正的实时刷新由原生侧负责（解锁广播 + 周期任务 → headless 引擎），
/// 这里只保证「用户看得见 App 的时刻」数据是最新的。
class HomeWidgetSyncScope extends ConsumerStatefulWidget {
  const HomeWidgetSyncScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<HomeWidgetSyncScope> createState() =>
      _HomeWidgetSyncScopeState();
}

class _HomeWidgetSyncScopeState extends ConsumerState<HomeWidgetSyncScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(initial: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  Future<void> _sync({bool initial = false}) async {
    if (!mounted) return;
    // 冷启动由小组件唤起时，先把目标页面推上去，再同步数据。
    if (initial) {
      await HomeWidgetLauncher.consumePendingRoute();
      if (!mounted) return;
    }
    final sync = ref.read(homeWidgetSyncProvider);
    await sync.pushAuthSnapshot();
    await sync.syncAll(force: initial);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
