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

import 'package:smarter_jxufe/core/navigation/route_history.dart';
import 'package:smarter_jxufe/core/navigation/service_nav.dart';
import 'package:smarter_jxufe/features/home/data/home_grid_prefs.dart';
import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_style.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/home_screen.dart';
import 'package:smarter_jxufe/features/home/presentation/overview_pane.dart';

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

/// 概览那一个 id 上注册的探针：**它既是"id 取对了"的证据，又是真的概览**。
///
/// 为什么必须是真概览：这条用例后面要**真的点**里面的「电费余额」卡片 ——
/// 换成一块色块就没有卡片可点了（实测踩过：换色块后 `find.text('电费余额')` 直接空）。
class _OverviewProbe extends StatelessWidget {
  const _OverviewProbe();

  @override
  Widget build(BuildContext context) => const HomeOverviewPane();
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

  // ⚠ **只注册概览那一个 id**（模拟组装根 `main.dart` 的最小注册），
  // 而**不注册**仪表盘卡片那些 id —— 真实应用里也没有。
  //
  // 另外这条注册还兼当"**id 有没有取错**"的探针：`home_screen` 必须用
  // `kServiceOverview` 取；一旦误用 `kServiceHome`，这里的探针就**不会出现**，
  // 断言立刻红（本轮真踩过这个坑：两者不一致时表现完全一样、测试照样绿）。
  setUp(() {
    clearServiceScreens();
    registerServiceScreen(kServiceOverview, () => const _OverviewProbe());
  });
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

    // ⓪ **id 取对了没有**：概览必须是从缝里按 `kServiceOverview` 取到的那个探针。
    //    取错 id（例如误用 `kServiceHome`）时它会静默走就地兜底 ——
    //    外观、测试全都照绿，所以这条断言是本轮唯一能抓住那个错的守卫。
    expect(
      find.byType(_OverviewProbe),
      findsOneWidget,
      reason: '概览应当是缝里按 kServiceOverview 取到的（取错 id 会静默兜底）',
    );
    expect(rootNav(tester).canPop(), isFalse, reason: '起始时根栈只有主页一层');

    // 拿历史那份单例（`routeHistoryProvider` 不是 autoDispose → 跨页面活着）。
    final history = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    ).read(routeHistoryProvider);
    final labelsBefore = history.entries.map((e) => e.label).toList();

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

    // ③ ★ **顶部路由历史必须记下这一笔**（用户 2026-10-10 二十七轮：
    //    「点击数据一览的卡片后，顶部路由不记录」）。
    //    判据 = 历史**末尾**多了一条「宿舍电费」。
    //
    // ⚠ 这里不能用 `labelsBefore` 比全表：本用例只 pump 了一个裸 `HomeScreen`
    // （不走组装根 `main.dart`），而 `_select` 的语义是"先记离开的位置、再记新位置" ——
    // 点一下之后末尾两笔正是「数据一览」「宿舍电费」（实测）。只钉末尾那笔即可。
    expect(
      history.entries.map((e) => e.label).last,
      '宿舍电费',
      reason: '点概览卡片必须落一笔历史（否则顶部前进/后退对它全瞎）'
          '（实测全表 ${history.entries.map((e) => e.label).toList()}，'
          '点之前 $labelsBefore）',
    );
    expect(
      history.entries.last.canRestore,
      isTrue,
      reason: '这一笔必须能回去（restore 非空），否则顶部按钮是死的',
    );

    // ④ **顶部的「后退」真能用**：`goBack()` 把游标退回上一笔（= 数据一览）并调它的
    //    restore → 右栏应当回到概览。
    //    ⚠ 别写成 `history.entries.last.restore!()`：那是**当前**这一笔（宿舍电费），
    //    调它等于原地重设一遍，什么都不会变（实测踩过）。
    expect(history.canGoBack, isTrue, reason: '刚记完一笔，顶部的后退应当可用');
    expect(history.goBack(), isTrue);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(
      find.byKey(homeOverviewPaneKey),
      findsOneWidget,
      reason: '顶部后退应当把右栏放回「数据一览」',
    );
    expect(
      history.current?.label,
      '数据一览',
      reason: '游标应当退回概览那一笔（实测 ${history.current?.label}）',
    );
    expect(tester.takeException(), isNull);
  });
}
