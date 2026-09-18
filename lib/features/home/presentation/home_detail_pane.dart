/// 主页左侧导航栏视图的**右侧内嵌面板**。
///
/// 用户 2026-09-15 裁定（第 2 条）：「点击左侧导航栏后，不是跳转页面，而是直接
/// 在右侧显示原跳转页面，并取消原页面的返回按钮」。
///
/// 实现要点：面板里放**一个独立的 [Navigator]**，把服务页当它的首路由：
/// - `ImsSplashScreen` 的 `pushReplacement`（会话闸门 → 功能页）落在面板自己的
///   路由栈里，不会把整个主页替换掉；
/// - 页面内部的二级跳转（如成绩 → 课程详情）也留在面板内，侧栏不消失；
/// - 首路由 `canPop == false` → 内嵌页**整条导航栏都不画**（2026-09-16 用户裁定：
///   侧栏已高亮当前服务，再写一遍名字是重复信息；原导航栏里的按钮下沉到内容首行，
///   见 `lib/design/pane_chrome.dart` 与 AGENTS.md §19）；二级页面照常显示完整导航栏
///   与返回按钮（那时它确实有上一页）；
/// - [entry] 换人 = `ValueKey` 变 = 全新 Navigator（路由栈天然重置，不用手写 pop 逻辑）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

/// 把 [entry] 的功能页内嵌在右侧面板里。
class HomeDetailPane extends StatelessWidget {
  final HomeServiceEntry entry;

  const HomeDetailPane({super.key, required this.entry});

  /// 面板内 Navigator 的 Key（按条目区分 = 切换条目即重置路由栈）。
  static Key navKeyOf(HomeServiceEntry entry) =>
      ValueKey('homeDetailNav-${entry.title}');

  @override
  Widget build(BuildContext context) {
    // `PaneScope` 必须包在 Navigator **外面**：面板内所有路由（含二级页、含
    // `pushReplacement` 换上去的那一页）都要查得到它，`paneEmbedded` 才是 true。
    return PaneScope(
      embedded: true,
      child: Navigator(
        key: navKeyOf(entry),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => entry.builder(),
        ),
      ),
    );
  }
}
