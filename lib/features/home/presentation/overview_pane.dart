/// 右栏（侧栏视图）默认那一格：**数据一览概览**。
///
/// 从 `home_screen.dart` 的 `_buildOverviewPane()` 提出来（用户 2026-10-09 二十四轮）。
///
/// ⚠ **为什么必须是一个独立的、能在跳转缝里注册的页面**：
/// 右栏的「数据一览」从前是 `home_screen` 直接渲染的一块内容，**不是面板的一条路由** ——
/// 于是它里面的卡片拿到的 `context` 上**没有 `PaneScope`**（那个标记由
/// `HomeDetailPane` 注入，而概览根本不经过它）→ `dashboardPush` 里的
/// `paneEmbedded(context)` 恒为 false → **退回整页 push → 页面占满整个窗口**
/// （用户原话：「点击主页卡片后，页面会占满整个窗口，而不是显示在右侧内容区」）。
///
/// 提出来之后：`lib/main.dart` 把它注册成 `kServiceHome`，`home_screen` 的
/// `_buildPaneContent` 用 `serviceScreenBuilder(kServiceHome)` 取它并交给
/// `HomeDetailPane` —— 概览于是成了**面板的首路由**，`PaneScope` 有了，
/// 里面的卡片点开就落在右栏（压在同一个面板 Navigator 上，卡片框与左栏一概不动）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/home/presentation/dashboard_panel.dart';
import 'package:smarter_jxufe/features/home_widget/presentation/home_widget_sync_scope.dart';

/// 概览列表里那块仪表盘的 Key（**跨文件口径**：`home_screen` 与测试都按它找）。
const Key homeOverviewPaneKey = Key('homeOverviewPane');

/// 右栏默认内容：数据一览概览（支持下拉刷新所有卡片）。
class HomeOverviewPane extends ConsumerWidget {
  const HomeOverviewPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () => refreshDashboard(ref),
      child: ListView(
        key: homeOverviewPaneKey,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
        children: const [HomeWidgetSyncScope(child: DashboardPanel())],
      ),
    );
  }
}
