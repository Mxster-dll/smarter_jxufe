import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/web/in_app_web_screen.dart';
import 'package:smarter_jxufe/core/web/web_session.dart';

/// 内嵌网页的**页内返回**守卫（2026-10-08 二轮）。
///
/// 用户原话：「我希望在这个 webview 内，增加一个内部页面返回」——
/// 起因是点进 ehall 的子页面之后**只剩整页退出**一条路。
///
/// 两条语义**刻意分开**，别合并：
/// - 导航栏**左上角箭头** = 退出本页（`Navigator.pop`，用户在哪儿都出得来）；
/// - **「上一页」按钮 + 系统返回键** = 网页自己的历史（`canGoBack` / `goBack`）。
///
/// ⚠ 真 WebView 在 widget 测试里建不出来（`InAppWebViewPlatform.instance` 没被
/// 设置过 → 一 build 就断言失败），所以这里分两层验：
/// 1. **行为**：直接 pump `inAppWebNavActions` 产出的那排按钮 —— 它是「只吃普通入参」
///    的顶层函数，正是为了能被这样推；
/// 2. **接线**：`_InAppWebScreenState` 里 `canGoBack`/`goBack`/`PopScope` 的接法
///    只能读源码断言（那些代码路径要真平台实现才会跑到）。
void main() {
  /// 把按钮组塞进一个最小可 pump 的环境。
  Future<void> pumpActions(
    WidgetTester tester, {
    required bool canGoBack,
    VoidCallback? onBack,
    VoidCallback? onRefresh,
    VoidCallback? onHome,
    VoidCallback? onOpenExternal,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('x'),
            actions: inAppWebNavActions(
              canGoBack: canGoBack,
              onBack: onBack,
              onRefresh: onRefresh,
              onHome: onHome,
              onOpenExternal: onOpenExternal ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  IconButton btn(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(Key(key)));

  group('页内返回按钮（inAppWebNavActions）', () {
    testWidgets('没有上一页时「上一页」是**禁用**的（灰，不是坏）', (tester) async {
      await pumpActions(tester, canGoBack: false, onBack: () {});
      expect(find.byKey(const Key('inAppWebBack')), findsOneWidget);
      expect(find.byTooltip('上一页'), findsOneWidget);
      expect(
        btn(tester, 'inAppWebBack').onPressed,
        isNull,
        reason: '浏览器也是这个行为：到底了就灰掉',
      );
    });

    testWidgets('有上一页时点得动，且回调真的被调用', (tester) async {
      var backCalls = 0;
      await pumpActions(
        tester,
        canGoBack: true,
        onBack: () => backCalls++,
      );
      expect(btn(tester, 'inAppWebBack').onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('inAppWebBack')));
      await tester.pump();
      expect(backCalls, 1);
    });

    testWidgets('canGoBack 为真但没给回调 → 仍然禁用（不画死按钮）', (tester) async {
      await pumpActions(tester, canGoBack: true);
      expect(btn(tester, 'inAppWebBack').onPressed, isNull);
    });

    testWidgets('刷新 / 回到首页：回调为空即禁用（控制器还没建好时不假装能点）', (tester) async {
      await pumpActions(tester, canGoBack: false);
      expect(btn(tester, 'inAppWebRefresh').onPressed, isNull);
      expect(btn(tester, 'inAppWebHome').onPressed, isNull);
    });

    testWidgets('「用系统浏览器打开」**恒可点** —— 它是内嵌失败时的唯一出路', (tester) async {
      var opened = 0;
      await pumpActions(
        tester,
        canGoBack: false,
        onOpenExternal: () => opened++,
      );
      expect(btn(tester, 'inAppWebExternal').onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('inAppWebExternal')));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('四个按钮齐全，且「上一页」排在最前（与浏览器一致）', (tester) async {
      await pumpActions(tester, canGoBack: true, onBack: () {});
      final keys = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .map((b) => b.key)
          .toList();
      expect(keys, [
        const Key('inAppWebBack'),
        const Key('inAppWebRefresh'),
        const Key('inAppWebHome'),
        const Key('inAppWebExternal'),
      ]);
    });
  });

  group('内嵌页源码接线守卫', () {
    final source = File(
      'lib/core/web/in_app_web_screen.dart',
    ).readAsStringSync();

    test('系统返回键先走网页历史，回到底才退页面', () {
      expect(source.contains('PopScope('), isTrue);
      expect(
        source.contains('canPop: !_canGoBack'),
        isTrue,
        reason: '写反了（canPop: _canGoBack）会让用户在三级页面里一按返回就整页退出',
      );
      expect(source.contains('onPopInvokedWithResult'), isTrue);
      expect(source.contains('unawaited(_goBack())'), isTrue);
    });

    test('「能不能上一页」只在导航事件后同步，且问的是 WebView', () {
      expect(source.contains('controller.canGoBack()'), isTrue);
      expect(source.contains('onUpdateVisitedHistory'), isTrue);
      // 历史变化（最准）+ 加载完成（兜底）两个调用点都要有。
      expect(
        RegExp(r'_syncHistory\(\)').allMatches(source).length,
        greaterThanOrEqualTo(4),
        reason: '定义 1 处 + _goBack 里 1 处 + onLoadStop / onUpdateVisitedHistory 各 1 处',
      );
    });

    test('页内返回与退出本页是两条路（左上角箭头不受 PopScope 管）', () {
      // ⚠ 关键：默认 `BackButton` 走 `Navigator.maybePop`，会被 PopScope 拦下来
      // → 左上角箭头会变成「页内返回」，用户得连按好几次才出得去。
      // 所以必须显式给 leading 并用 `pop` 直通。
      expect(
        source.contains('leading:'),
        isTrue,
        reason: '不显式给 leading 就会被 PopScope 接管',
      );
      expect(source.contains('Navigator.of(context).pop()'), isTrue);
      expect(source.contains('BackButton(onPressed:'), isTrue);
      // 页内返回只经 goBack()。
      expect(source.contains('_controller?.goBack()'), isTrue);
    });

    test('建页时把「上一页」重置为假（免得上一轮的残留状态带进来）', () {
      expect(source.contains('_canGoBack = false;'), isTrue);
    });
  });

  // 用户 2026-10-10 二十八轮：「我希望内嵌的智慧江财的内部页面也要接入路由」。
  group('网页内部跳转接入全局路由历史', () {
    String key({
      bool enabled = true,
      String url = 'http://ehall.jxufe.edu.cn/a',
      String previous = '',
      bool reload = false,
    }) => webRouteHistoryKey(
      enabled: enabled,
      url: url,
      previousUrl: previous,
      isReload: reload,
    ) ??
        '<不记>';

    test('★ 新地址记一笔，键里带 URL（同一地址不会重复记）', () {
      expect(key(), 'web:http://ehall.jxufe.edu.cn/a');
      expect(
        key(previous: 'http://ehall.jxufe.edu.cn/a'),
        '<不记>',
        reason: 'onLoadStop 与 onUpdateVisitedHistory 会各喊一次，第二次必须被去重掉',
      );
    });

    test('地址还没拿到（空串）不记', () {
      expect(key(url: ''), '<不记>');
    });

    test('用户按刷新不算新位置', () {
      expect(key(reload: true), '<不记>');
    });

    test('调用点显式关掉时不记（recordRouteHistory: false）', () {
      expect(key(enabled: false), '<不记>');
    });

    test('接线：两个回调都记，且 restore 走 loadUrl（不重开会话）', () {
      final source = File(
        'lib/core/web/in_app_web_screen.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'_recordRoute\(').allMatches(source).length,
        greaterThanOrEqualTo(2),
        reason: 'onLoadStop 与 onUpdateVisitedHistory 各要喊一次',
      );
      expect(source.contains('webRouteHistoryKey('), isTrue);
      expect(
        source.contains('routeHistoryProvider'),
        isTrue,
        reason: '要真的落到全局那一份历史上',
      );
      expect(
        source.contains('URLRequest(url: WebUri(url))'),
        isTrue,
        reason: 'restore 必须是"让这个 WebView 加载那个地址"（同一会话，登录态还在）',
      );
      expect(
        source.contains('recordRouteHistory = true'),
        isTrue,
        reason: '默认开启（用户要的就是默认接上）',
      );
    });
  });

  group('内嵌请求口径没有被这次改动带偏', () {
    test('EmbeddedWebRequest 的 toString 仍不带 Cookie 值', () {
      const request = EmbeddedWebRequest(
        title: 'x',
        url: 'https://example.com/',
        cookies: [WebSessionCookie(name: 'TGC', value: 'secret', domain: 'h')],
      );
      expect(request.toString(), isNot(contains('secret')));
    });
  });
}
