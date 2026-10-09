// 内嵌网页的**浏览器原生前进 / 后退**与顶部两枚按钮的融合
// （用户 2026-10-10 二十九轮：「我不希望你手动记录，我只希望把浏览器原生的前进回退
// 融合进来」）。
//
// ⚠ 真 WebView 在 widget 测试里建不出来（`InAppWebViewPlatform.instance` 没被设置过 →
// 一 build 就断言失败），所以这里分两层：
// 1. **行为**：`BrowserNavService` 是纯逻辑（只吃回调 + 状态），可以直接推；
// 2. **接线**：`InAppWebScreen` / `WindowTitleBarHistory` 里怎么接的，读源码断言。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/web/browser_nav.dart';

void main() {
  late BrowserNavService service;

  setUp(() => service = BrowserNavService());
  tearDown(() => service.dispose());

  group('BrowserNavService 语义', () {
    test('没网页登记时：不活跃、两向都不能走', () {
      expect(service.isActive, isFalse);
      expect(service.state.canGoBack, isFalse);
      expect(service.state.canGoForward, isFalse);
      expect(service.goBack(), isFalse, reason: '没人接 = 返回 false，调用方走应用回退');
      expect(service.goForward(), isFalse);
    });

    test('★ 能回网页时 goBack 返回 true 且真的调了回调（调用方不许再动历史）', () {
      var backCalls = 0;
      service.attach(
        onBack: () => backCalls++,
        state: const BrowserNavState(canGoBack: true, canGoForward: false),
      );
      expect(service.isActive, isTrue);
      expect(service.goBack(), isTrue);
      expect(backCalls, 1);
      expect(service.goForward(), isFalse, reason: '不能前进时不许乱调');
    });

    test('能力为假时 goBack 返回 false（调用方照旧回应用的上一个位置）', () {
      var backCalls = 0;
      service.attach(onBack: () => backCalls++, state: BrowserNavState.none);
      expect(service.goBack(), isFalse);
      expect(backCalls, 0, reason: '回不了网页就不该动它');
    });

    test('前进同理', () {
      var forwardCalls = 0;
      service.attach(
        onForward: () => forwardCalls++,
        state: const BrowserNavState(canGoBack: true, canGoForward: true),
      );
      expect(service.goForward(), isTrue);
      expect(forwardCalls, 1);
    });

    test('detach 之后立刻回到"没人管"（被盖住 / 页面销毁）', () {
      var backCalls = 0;
      service.attach(
        onBack: () => backCalls++,
        state: const BrowserNavState(canGoBack: true, canGoForward: true),
      );
      service.detach();
      expect(service.isActive, isFalse);
      expect(service.state, BrowserNavState.none);
      expect(service.goBack(), isFalse);
      expect(backCalls, 0);
    });

    test('只有能力**真的变了**才通知（否则顶部每帧重建）', () {
      var notifications = 0;
      service.addListener(() => notifications++);
      service.attach(
        onBack: () {},
        state: const BrowserNavState(canGoBack: true, canGoForward: false),
      );
      expect(notifications, 1);
      service.update(
        const BrowserNavState(canGoBack: true, canGoForward: false),
      );
      expect(notifications, 1, reason: '同一个状态重复上报不该再通知');
      service.update(
        const BrowserNavState(canGoBack: false, canGoForward: true),
      );
      expect(notifications, 2);
    });
  });

  group('接线守卫（源码）', () {
    final web = File('lib/core/web/in_app_web_screen.dart').readAsStringSync();
    final bar = File('lib/design/window_title_bar.dart').readAsStringSync();

    test('★ 网页内部跳转**不再**手动记进路由历史', () {
      expect(
        web.contains('routeHistoryProvider'),
        isFalse,
        reason: '用户明确「我不希望你手动记录」—— 这一页不许再碰 route_history',
      );
      expect(web.contains('webRouteHistoryKey'), isFalse);
      expect(web.contains('recordRouteHistory'), isFalse);
    });

    test('网页把自己的能力报给 browserNavService（含前进）', () {
      expect(web.contains('browserNavService.update('), isTrue);
      expect(web.contains('controller.canGoBack()'), isTrue);
      expect(
        web.contains('controller.canGoForward()'),
        isTrue,
        reason: '顶部「前进」要有得问，必须一起问 canGoForward',
      );
      expect(web.contains('Future<void> _goForward()'), isTrue);
    });

    test('只在当前可见时登记，销毁时让位', () {
      expect(web.contains('ModalRoute.of(context)'), isTrue);
      expect(web.contains('.isCurrent'), isTrue);
      expect(
        web.contains('browserNavService.detach()'),
        isTrue,
        reason: 'dispose / 被盖住都要让出顶部按钮',
      );
    });

    test('★ 顶部两枚按钮先问网页、再回应用', () {
      expect(bar.contains('browserNavService'), isTrue);
      expect(
        bar.contains('ListenableBuilder('),
        isTrue,
        reason: '网页里点一层后，顶部按钮要跟着亮起来',
      );
      expect(
        bar.contains('if (browserNavService.goBack()) return;'),
        isTrue,
        reason: '能回网页就别动 route_history（一个键一种读法）',
      );
      expect(
        bar.contains('if (browserNavService.goForward()) return;'),
        isTrue,
      );
      expect(
        bar.contains('browser.canGoBack || history.canGoBack'),
        isTrue,
        reason: '灰/亮 = 网页能回 **或** 应用能回',
      );
    });
  });
}
