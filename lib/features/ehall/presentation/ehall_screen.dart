/// 智慧江财（ehall 综合服务门户）· 内嵌页（2026-10-08 立 · AGENTS.md §40）。
///
/// **为什么是内嵌而不是跳系统浏览器**：系统浏览器与 App **不共享登录态**，
/// 跳过去看到的是统一认证登录页，用户还得再输一遍密码（网站导航那边一律跳浏览器，
/// 是因为那些站点本来就无需登录）。这里把 App 已经握着的 TGC 写进内嵌浏览器，
/// 页面直接就是**已登录门户** —— 这正是用户 2026-10-08 要的东西
/// （「用于加载原生网页：http://ehall.jxufe.edu.cn/，但是支持直接复用当前项目里的
/// 登录 cookie」）。
///
/// 本页只做三态：解析登录态（加载）→ 交给 `InAppWebScreen`（数据）→ 给错误 +
/// 两条出路（错误：重试 / 用系统浏览器打开）。
///
/// ⚠ **刻意不挂 `PageAutoRefresher`**：§3 那条纪律针对的是「展示**缓存型**
/// `FutureProvider` 数据」的页面，而 `ehallWebSessionProvider` 是**一次性的会话解析**
/// （拿一枚当下可用的 TGC），页面本体是个自带状态的 WebView —— 回前台/从子页返回时
/// 重新解析等于把用户正在操作的网页整个重载掉。要刷新请用页面上的「刷新」按钮
/// （`InAppWebScreen` 导航栏那个），它只 reload 网页、不重开会话。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/web/external_url.dart';
import 'package:smarter_jxufe/core/web/in_app_web_screen.dart';
import 'package:smarter_jxufe/design/app_states.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/ehall/data/ehall_endpoints.dart';
import 'package:smarter_jxufe/features/ehall/data/providers/ehall_session_provider.dart';

/// 智慧江财 · 综合服务门户。
class EhallScreen extends ConsumerWidget {
  const EhallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(ehallWebSessionProvider);
    return session.when(
      // 拿到请求就整页交给内嵌页 —— 它自带 Scaffold / 导航栏 / 三态，
      // 这里再包一层 Scaffold 会套出两条标题栏。
      // 走 `webViewScreenBuilderProvider` 这个缝：widget 测试里不能真的构造
      // WebView（需要平台实现），override 一下就能断言「要开哪个 URL、写了哪些 Cookie」。
      data: (request) => ref.watch(webViewScreenBuilderProvider)(request),
      loading: () =>
          _shell(context, const AppLoadingState(message: '正在把统一认证登录态交给内嵌浏览器…')),
      error: (error, _) => _shell(
        context,
        AppErrorState(
          error: error,
          title: '智慧江财打不开',
          onRetry: () => ref.invalidate(ehallWebSessionProvider),
          retryKey: const Key('ehallSessionRetry'),
        ),
        actions: [_openInBrowser(context, ref)],
      ),
    );
  }

  /// 加载 / 错误两态的壳（数据态由 `InAppWebScreen` 自己画）。
  Widget _shell(
    BuildContext context,
    Widget child, {
    List<Widget> actions = const <Widget>[],
  }) => Scaffold(
    appBar: paneAppBar(context, title: const Text('智慧江财'), actions: actions),
    body: PaneBody(actions: actions, child: child),
  );

  /// 兜底出路：拿不到登录态 / 内嵌浏览器不可用时，至少能去系统浏览器。
  Widget _openInBrowser(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: '用系统浏览器打开',
    onPressed: () {
      final uri = Uri.tryParse(ehallPortalUrl);
      if (uri != null) ref.read(externalUrlOpenerProvider)(uri);
    },
    icon: const Icon(Icons.open_in_new),
  );
}
