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
/// - [paneKey] 换人 = `ValueKey` 变 = 全新 Navigator（路由栈天然重置，不用手写 pop 逻辑）。
///
/// ⚠ 2026-10-09 五轮：面板不只服务**目录条目**了 —— 侧栏底部固定区的「我的 / 设置」
/// 也要在这里显示（用户原话：「我们目前『侧边栏』模式下，设置和我的页都不是在右侧
/// 内容区显示，而是进入一个子页面，我希望与其他功能页统一」）。所以本类改成收
/// [paneKey] + [builder]，目录条目走 [HomeDetailPane.entry] 那个便捷构造。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

/// 把一个功能页内嵌在右侧面板里。
class HomeDetailPane extends StatelessWidget {
  /// 面板 id：换 id 即换一个全新的面板 Navigator（路由栈重置）。
  final String paneKey;

  /// 面板首路由要显示的功能页。
  final Widget Function() builder;

  /// 本面板是不是**侧栏视图右栏**的那一个（见 [PaneScope.sidebarPane]）。
  ///
  /// `home_screen._paneSwitcher` 建的时候传 true —— 那一格上**任何**路由都算
  /// "面板首路由"（不画导航栏）；其余调用点不传，保持"只有首路由才不画"的老判据。
  final bool sidebarPane;

  /// 侧栏右栏这一格的宿主回调（见 [PaneScope.sidebarHost]）。
  final void Function(String entryTitle)? sidebarHost;

  const HomeDetailPane({
    super.key,
    required this.paneKey,
    required this.builder,
    this.sidebarPane = false,
    this.sidebarHost,
  });

  /// 目录条目版（面板 id = 条目标题）。
  HomeDetailPane.entry(HomeServiceEntry entry, {super.key})
    : paneKey = entry.title,
      sidebarPane = false,
      sidebarHost = null,
      builder = entry.builder;

  /// 面板内 Navigator 的 Key（按 [paneKey] 区分 = 切换条目即重置路由栈）。
  static Key navKeyOfId(String paneKey) =>
      ValueKey<String>('homeDetailNav-$paneKey');

  /// 目录条目版的 [navKeyOfId]（沿用旧签名，测试里有引用）。
  static Key navKeyOf(HomeServiceEntry entry) => navKeyOfId(entry.title);

  @override
  Widget build(BuildContext context) {
    // `PaneScope` 必须包在 Navigator **外面**：面板内所有路由（含二级页、含
    // `pushReplacement` 换上去的那一页）都要查得到它，`paneEmbedded` 才是 true。
    return PaneScope(
      embedded: true,
      sidebarPane: sidebarPane,
      sidebarHost: sidebarHost,
      child: Navigator(
        key: navKeyOfId(paneKey),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => builder(),
        ),
      ),
    );
  }
}
