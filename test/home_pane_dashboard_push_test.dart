// 概览面板里的卡片点开后，页面必须落在**右侧内容区**里，不许占满整个窗口
// （用户 2026-10-09 二十四轮：「点击主页卡片后，页面会占满整个窗口，而不是显示在
// 右侧内容区」）。
//
// 真因：`DashboardPanel` 自己就被内嵌在侧栏右栏，但它的指标卡一律
// `Navigator.push`（`dashboardPush`）→ 盖住整个窗口。
//
// ⚠ 为什么单开一个文件：要 pump **真实 `HomeScreen`**（侧栏视图）+ 真跳转缝注册，
// 塞进 `home_sidebar_test.dart` 会与那堆 `pumpSidebar` 参数纠缠。
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/navigation/service_nav.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/electricity/presentation/electricity_screen.dart';
import 'package:smarter_jxufe/features/home/data/home_grid_prefs.dart';
import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';

import 'package:smarter_jxufe/features/home/presentation/dashboard_common.dart';
import 'package:smarter_jxufe/features/home/presentation/home_detail_pane.dart';
import 'package:smarter_jxufe/features/home/presentation/home_screen.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_grid.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_screen.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('tmp_pane_push');
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

  setUp(() {
    // ⚠⚠ **故意把跳转缝清空、什么都不注册**。
    // 二十四轮第一版就是靠"测试自己往缝里注册 `宿舍电费`"才变绿的，而真实应用里
    // 缝中只注册了 7 个 id（home/materials/settings/ims/comprehensive/dataCenter/
    // studentInfo）—— `宿舍电费`/`校园网`/`成绩`/`课表` 一个都没有，于是
    // `openServiceScreen` 恒返回 false、每次都整页 push，用户照样看到"占满整个窗口"。
    // 这条用例现在**只允许走传进来的页面本体**，不许依赖缝。
    clearServiceScreens();
  });
  tearDown(clearServiceScreens);

  /// ⚠ `ProviderScope` 要在 **`pumpWidget` 之外**建（否则每次 pump 都换一个新容器，
  /// 页面里的 provider 状态会被清空 —— 本仓已踩过这个坑）。
  ///
  /// 侧栏视图的判据 = `layout == sidebar && desktop && width >= 900`，
  /// 所以这里两件事都要办：**把落盘布局设成 sidebar** + 让 `homeDesktopPlatform` 为真。
  Widget homeApp({
    required Size size,
    required Widget home,
    required HomeLayoutStore store,
  }) {
    // ⚠ `MediaQuery` 必须在 **`MaterialApp` 之内**（放外面会被 MaterialApp 自己按 view
    // 建的那层盖掉，等于没设 —— 本仓踩过）。
    return ProviderScope(
      overrides: [homeLayoutStoreProvider.overrideWith((ref) => store)],
      child: MaterialApp(
        home: MediaQuery(data: MediaQueryData(size: size), child: home),
      ),
    );
  }

  Future<void> pumpHome(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // ⚠ 落盘要在**真异步区**里读（假异步区里开 box 会挂死到超时）；store 交给
    // `ProviderScope` 后**不要**再 `dispose`（容器自己会 dispose 一次，二次 dispose
    // 会报「used after being disposed」—— 实测踩过）。
    final store = HomeLayoutStore();
    await tester.runAsync(() async {
      await store.ensureLoaded();
      await store.save(HomeLayout.sidebar);
    });
    await tester.pumpWidget(
      homeApp(size: size, home: const HomeScreen(), store: store),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('★ 内嵌面板里点卡片 → 落在右栏，不盖窗口', (tester) async {
    // ⚠ `debugDefaultTargetPlatformOverride` 必须在**用例体结束前**清掉：框架的
    // `debugAssertAllFoundationVarsUnset` 是在测试体跑完、`addTearDown` **之前**查的，
    // 用 `addTearDown` 复位会报「The value of a foundation debug variable was changed
    // by the test」（实测踩过）。
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpHome(tester, size: const Size(1280, 800));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    // 拿右栏那块（`HomeDetailPane` 的面板）当参照。
    // ⚠ 右栏**默认那一格是「数据一览」概览**，它自己就是 `ListView`（不是
    // `HomeDetailPane`）—— 所以必须先真的选一个服务，右栏才会装上面板。
    // 侧栏那一行在滚动区里、可能在视口外 → 先滚到它再点。
    final row = find.byKey(const Key('homeSidebarItem-宿舍电费'));
    await tester.scrollUntilVisible(
      row,
      120,
      scrollable: find.descendant(
        of: find.byKey(const Key('homeSidebar')),
        matching: find.byType(Scrollable),
      ).first,
    );
    await tester.tap(row);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }

    final paneFinder = find.byType(PaneScope);
    expect(paneFinder, findsOneWidget, reason: '选了服务之后右栏应当是内嵌面板');
    expect(tester.widget<PaneScope>(paneFinder).embedded, isTrue);

    // 面板自己的 Navigator（`homeDetailNav-<paneKey>`）—— 量它里面开了几个路由。
    NavigatorState paneNav() => tester.state<NavigatorState>(
      find.byKey(HomeDetailPane.navKeyOfId('宿舍电费')),
    );
    final routesBefore = paneNav().canPop() ? 2 : 1;

    // ignore: avoid_print
    print(
      'PROBE 推之前 面板canPop=${paneNav().canPop()} 根canPop='
      '${tester.state<NavigatorState>(find.ancestor(of: find.byType(HomeScreen), matching: find.byType(Navigator)).last).canPop()} '
      'NetFee=${find.byType(NetFeeScreen).evaluate().length}',
    );
    // 模拟**右栏里的卡片**被点（概览面板的指标卡就是这条路径）：
    // `paneEmbedded(context)` 为真 → 必须走**面板自己的** Navigator。
    // 面板里那一页（「宿舍电费」的真实首路由 = IMS 那条溅屏入口）就是页面自己的
    // `context` —— 概览面板的卡片也在同一个 Navigator 底下，取它等价。
    final context = tester.element(find.byType(ElectricityScreen));
    // 推一个**和面板首路由不同**的页面（校园网）—— 这样"面板里多了一层"和
    // "根 Navigator 没动"两件事都能独立看出来。
    dashboardPush(context, const NetFeeScreen());
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }

    // ① **面板的路由栈真的长了一层**，而且压上去的就是那个页面 ——
    //    `_ProbePage` 只可能从面板里长出来（它是注册在「宿舍电费」这个 id 上的
    //    探针；整页 push 走的是 `MaterialPageRoute(builder: (_) => ElectricityScreen())`，
    //    永远不会是它）。**这条断言在改之前的代码上必红。**
    expect(
      paneNav().canPop(),
      isTrue,
      reason: '卡片点开的页面必须落在面板自己的 Navigator 里',
    );
    expect(
      routesBefore,
      1,
      reason: '推开之前面板只有首路由（canPop = false）',
    );
    expect(
      find.byType(NetFeeScreen),
      findsOneWidget,
      reason: '面板里应当出现「校园网」页 —— 找不到就是整页 push 走了',
    );
    expect(
      find.byType(ElectricityScreen),
      findsNothing,
      reason: '校园网是**二级页**，压在电费之上（不是替换）',
    );

    // ② **根 Navigator 一个路由都没多** = 没有东西盖在整页之上
    //    （用户报的 bug 正是这里多了一层：整个主页被页面盖住）。
    final rootNav = tester.state<NavigatorState>(
      find.ancestor(of: find.byType(HomeScreen), matching: find.byType(Navigator)).last,
    );
    expect(
      rootNav.canPop(),
      isFalse,
      reason: '根 Navigator 不许被压栈（压了 = 页面占满整个窗口）',
    );
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宫格视图（没有面板）：仍旧整页打开', (tester) async {
    // 直接搭一个"没有 PaneScope"的宿主 = 宫格视图那一路。
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    final store = HomeLayoutStore();
    await tester.runAsync(store.ensureLoaded);
    await tester.pumpWidget(
      homeApp(
        size: const Size(1280, 800),
        store: store,
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );
    dashboardPush(ctx, const ElectricityScreen());
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(
      find.byType(ElectricityScreen),
      findsOneWidget,
      reason: '没有面板时必须退回整页 push —— 宫格视图的老行为不许变',
    );
  });

  group('dashboardPaneKeyOf：认得出目录条目名', () {
    test('IMS 那条按 initialTab 走（标题 = ImsTab.title）', () {
      expect(
        dashboardPaneKeyOf(const ImsSplashScreen(initialTab: ImsTab.grade)),
        '成绩',
      );
      expect(
        dashboardPaneKeyOf(const ImsSplashScreen(initialTab: ImsTab.schedule)),
        '课表',
      );
      expect(
        dashboardPaneKeyOf(const ImsSplashScreen()),
        ImsTab.curriculum.title,
        reason: '没给 tab（落到 IMS 菜单）→ 用培养方案那条的 id 兜底，不许 null',
      );
    });

    test('电费 / 校园网 = 目录里的标题（不是随手写的简称）', () {
      expect(dashboardPaneKeyOf(const ElectricityScreen()), '宿舍电费');
      expect(dashboardPaneKeyOf(const NetFeeScreen()), '校园网');
    });

    test('目录里没有的页面 → null（调用方退回整页 push）', () {
      expect(dashboardPaneKeyOf(const SizedBox()), isNull);
    });
  });
}
