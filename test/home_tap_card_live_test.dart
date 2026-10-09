// 用户 2026-10-09 二十四轮（**仍然存在**）：「点击主页卡片后，页面会占满整个窗口，
// 而不是显示在右侧内容区」。
//
// 这条刻意**不模拟**：pump 真实 `HomeScreen`（侧栏视图 + 卡片形态），
// 直接**点真的那张概览卡片**，然后问"根 Navigator 的路由栈变了吗"。
// 变了 = 整页盖上来（用户报的现象）；没变 = 落在右栏里。
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/navigation/service_nav.dart';
import 'package:smarter_jxufe/features/home/data/home_grid_prefs.dart';
import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_style.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/home_screen.dart';

/// 根 Navigator = 树里**第一个** `Navigator`（`MaterialApp` 自己那个；
/// 右栏面板的 Navigator 在它下面）。
NavigatorState rootNav(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).first);

/// 树里所有 `Navigator` 各自的路由层数（诊断用）。
String navStackReport(WidgetTester tester) {
  final navs = find.byType(Navigator).evaluate().toList();
  final out = <String>[];
  for (var i = 0; i < navs.length; i++) {
    final s = (navs[i] as StatefulElement).state as NavigatorState;
    out.add('#$i(canPop=${s.canPop()})');
  }
  return out.join(' ');
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('tmp_pane_tap');
    Hive.init(dir.path);
    await Hive.openBox<String>(homePrefsBoxName);
    await Hive.openBox<String>(homeGridPrefsBoxName);
  });
  tearDownAll(() {
    unawaited(Hive.close());
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ⚠ 故意**什么都不往跳转缝里注册**（只清空）：真实应用里也只有 7 个 id。
  setUp(clearServiceScreens);
  tearDown(clearServiceScreens);

  testWidgets('★ 点概览里的卡片：根 Navigator 不许被压栈', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = HomeLayoutStore();
    await tester.runAsync(() async {
      await store.ensureLoaded();
      await store.save(HomeLayout.sidebar);
      await store.saveCardStyle(HomeCardStyle.both);
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeLayoutStoreProvider.overrideWith((ref) => store)],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    // ignore: avoid_print
    print('PROBE 起始 ');
    expect(rootNav(tester).canPop(), isFalse, reason: '起始时根栈只有主页一层');

    // 概览面板里的「宿舍电费」卡片：按文案找到它，点它。
    // （`DashboardPanel` 就在右栏里，卡片是 `InkWell`。）
    // 概览里的电费卡标题是「电费余额」（`dashboard_metrics.dart` 的 `_MetricCard`）。
    final card = find.text('电费余额');
    expect(
      card,
      findsWidgets,
      reason: '概览面板里应当有「电费余额」那张指标卡（找不到说明概览没渲染出来）',
    );
    await tester.tap(card.first, warnIfMissed: false);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }

    // ① 根 Navigator 的路由栈**一层都没多** —— 这是"没占满整个窗口"的硬判据
    expect(
      rootNav(tester).canPop(),
      isFalse,
      reason: '点了主页卡片之后根 Navigator 被压栈了 = 页面占满整个窗口（用户报的 bug）',
    );
    // ② 主页还在（不是被盖住）
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
