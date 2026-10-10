import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/design/card_frame.dart';
import 'package:smarter_jxufe/features/home/data/home_grid_prefs.dart';
import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_shadow.dart';
import 'package:smarter_jxufe/design/fluent/fluent_surfaces.dart';
import 'package:smarter_jxufe/design/fluent/fluent_tokens.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_gap.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_radius.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_style.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/home_detail_pane.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';
import 'package:smarter_jxufe/features/settings/presentation/widgets/settings_cards.dart';

/// 侧栏视图的**卡片形态**守卫（用户 2026-10-09 二轮原话：「我希望 内容区一个卡片、
/// 侧栏一个卡片，然后都是在设置了可选的。可以都不显示为卡片样式」+「要阴影」）。
///
/// 分三层守，判定 / 留缝几何 / 侧栏那一半分别在：
/// - 纯逻辑（四档 → 哪块是卡片）：`test/home_layout_test.dart` 的 `HomeCardStyle` 组；
/// - 形状与阴影取值：`test/home_sidebar_test.dart` 的「卡片形态」组
///   （`lib/design/card_frame.dart` 没有单独的守卫文件，取值断言落在那里）；
/// - **本文件**：设置页那一半（四档入口 + 落盘）。
///
/// ⚠ **为什么单开一个文件**（2026-10-09 实测）：把这两例塞进
/// `test/home_grid_aggregate_test.dart`（那个文件 2500 行、前后几十个重用例）时，
/// 它们从「单独跑 0.1 秒过」变成「跑到 24 分钟才失败」——同一条用例在整份文件的
/// 上下文里挂死。分文件之后两处都不受影响。
void main() {
  late Directory hiveDir;
  late Box<String> homeBox;

  setUpAll(() async {
    hiveDir = Directory.systemTemp.createTempSync('home_card_style_test');
    Hive.init(hiveDir.path);
    // ⚠ 这两个 box 必须在**真异步区**里先打开：`HomeLayoutStore.ensureLoaded` /
    // `HomeGridStore.ensureLoaded` 会 `Hive.openBox(...)`，而它们在 `testWidgets`
    // 的假异步区里跑会挂死到超时。
    homeBox = await Hive.openBox<String>(homePrefsBoxName);
    await Hive.openBox<String>(homeGridPrefsBoxName);
  });

  setUp(() async {
    await homeBox.clear();
  });

  tearDownAll(() {
    // ⚠ 收尾阶段 `await Hive.close()` 可能永远不返回（本仓踩过），不 await。
    unawaited(Hive.close());
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ---------------------------------------------------------------------------
  // 设置页：四档入口都在（「主页布局」卡里的「卡片样式」一节）。
  // ---------------------------------------------------------------------------
  testWidgets('「主页布局」卡里有卡片样式四档', (tester) async {
    // 设置卡比默认的 800×600 视口高（多出来的四行卡片样式 + 原有几节），
    // 不开高视口会 RenderFlex overflow（本文件里放大视口是安全的 —— 实测）。
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SettingsHomeLayoutCard())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('卡片样式'), findsOneWidget);
    for (final value in HomeCardStyle.values) {
      expect(
        find.byKey(Key('homeCardOption-${value.name}')),
        findsOneWidget,
        reason: '${value.name} 这一档必须有入口',
      );
      expect(find.text(value.label), findsOneWidget, reason: value.name);
    }
    // 默认档 = 都不显示（不然老用户升级后主页会自己变成卡片）。
    expect(HomeCardStyle.fromName(null), HomeCardStyle.none);
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------------
  // 落盘：`saveCardStyle` 写 `homePrefs` 的 `homeCardStyle`（纯 Dart 用例，
  // 真异步区里 `await` 能正常 resume）。
  // ---------------------------------------------------------------------------
  test('卡片样式落盘：saveCardStyle 写进 homePrefs 的 homeCardStyle', () async {
    final store = HomeLayoutStore();
    addTearDown(store.dispose);
    await store.ensureLoaded();
    expect(store.cardStyle, HomeCardStyle.none, reason: '缺省 = 都不显示');

    var notified = 0;
    store.addListener(() => notified++);
    await store.saveCardStyle(HomeCardStyle.both);

    expect(store.cardStyle, HomeCardStyle.both);
    expect(notified, 1, reason: '改动要即时通知（主页不必重进就跟随）');
    expect(
      homeBox.get(homeCardStyleKey),
      HomeCardStyle.both.name,
      reason: '选择要真的落盘（重启后仍生效）',
    );

    // 再存一次同值：不重复通知。
    await store.saveCardStyle(HomeCardStyle.both);
    expect(notified, 1);

    // 换一档再验证（四档都要能存能读）。
    await store.saveCardStyle(HomeCardStyle.sidebar);
    expect(store.cardStyle, HomeCardStyle.sidebar);
    expect(store.cardStyle.sidebarIsCard, isTrue);
    expect(store.cardStyle.contentIsCard, isFalse);
    expect(homeBox.get(homeCardStyleKey), HomeCardStyle.sidebar.name);

    // 旧数据 / 脏值 → 回落「都不显示」，不崩。
    await homeBox.put(homeCardStyleKey, 'floating');
    final reloaded = HomeLayoutStore();
    addTearDown(reloaded.dispose);
    await reloaded.ensureLoaded();
    expect(reloaded.cardStyle, HomeCardStyle.none);
    expect(reloaded.layout, HomeLayout.grid, reason: '两个 key 互不影响');
  });

  // ---------------------------------------------------------------------------
  // 卡片阴影（用户 2026-10-10 三十六轮：「我希望侧边栏内容卡片的阴影是可选的」；
  // 当面选定：两块**各自**一个开关、**默认没有阴影**）。
  // 渲染侧那一半（CardFrame 画不画）在 `test/home_sidebar_test.dart` 的「卡片形态」组。
  // ---------------------------------------------------------------------------
  test('卡片阴影：两块各自独立、默认关、各自落盘', () async {
    final store = HomeLayoutStore();
    addTearDown(store.dispose);
    await store.ensureLoaded();

    expect(kCardShadowDefault, isFalse, reason: '★ 默认没有阴影（当面选定）');
    expect(store.sidebarCardShadow, isFalse, reason: '缺省 = kCardShadowDefault');
    expect(store.contentCardShadow, isFalse, reason: '缺省 = kCardShadowDefault');

    var notified = 0;
    store.addListener(() => notified++);

    // 只开侧栏 —— **不许**把内容区一起带上（"两块各自的开关"就是这一条）。
    await store.saveSidebarCardShadow(true);
    expect(store.sidebarCardShadow, isTrue);
    expect(store.contentCardShadow, isFalse, reason: '★ 两块各自独立');
    expect(notified, 1);
    expect(
      homeBox.get(homeSidebarCardShadowKey),
      'true',
      reason: '要真的落盘（重启后仍生效）',
    );
    expect(
      homeBox.get(homeContentCardShadowKey),
      isNull,
      reason: '没动过的那一个不该被顺带写盘',
    );

    await store.saveContentCardShadow(true);
    expect(store.contentCardShadow, isTrue);
    expect(homeBox.get(homeContentCardShadowKey), 'true');

    // 同值再存：不重复通知。
    await store.saveSidebarCardShadow(true);
    expect(notified, 2);

    // 关掉是双向的。
    await store.saveSidebarCardShadow(false);
    expect(store.sidebarCardShadow, isFalse);
    expect(homeBox.get(homeSidebarCardShadowKey), 'false');

    // 脏值 → 回落默认（关），不崩。
    await homeBox.put(homeSidebarCardShadowKey, 'yes-please');
    final reloaded = HomeLayoutStore();
    addTearDown(reloaded.dispose);
    await reloaded.ensureLoaded();
    expect(reloaded.sidebarCardShadow, isFalse, reason: '只认 "true"');
  });

  // ---------------------------------------------------------------------------
  // 卡片间距 a（三轮：「卡片与卡片之间的距离为 2a、卡片与窗口之间
  // （卡片与标题栏之间的距离不受此限制）的距离为 a；然后 a 可以通过设置调」）。
  // 派生量的纯逻辑守卫在 `test/home_card_gap_test.dart`，这里守落盘那一半。
  // ---------------------------------------------------------------------------
  test('卡片间距 a：落盘 + 越界夹回 + 脏值回落', () async {
    final store = HomeLayoutStore();
    addTearDown(store.dispose);
    await store.ensureLoaded();
    expect(store.cardGap, kCardGapDefault, reason: '缺省 = kCardGapDefault');

    await store.saveCardGap(10);
    expect(store.cardGap, 10);
    expect(homeBox.get(homeCardGapKey), '10', reason: '整数文本落盘');

    // 越界一律夹回（滑杆给不出越界值，但盘上的脏数据可能）。
    await store.saveCardGap(999);
    expect(store.cardGap, kCardGapMax);
    await store.saveCardGap(0);
    expect(store.cardGap, kCardGapMin);

    await homeBox.put(homeCardGapKey, 'not-a-number');
    final reloaded = HomeLayoutStore();
    addTearDown(reloaded.dispose);
    await reloaded.ensureLoaded();
    expect(reloaded.cardGap, kCardGapDefault);

    // 间距与形态互不影响（同 box 三个 key）。
    expect(reloaded.cardStyle, HomeCardStyle.none);
  });

  testWidgets('设置页有卡片间距滑杆，且读数 = 卡片之间 / 距窗口', (tester) async {
    tester.view.physicalSize = const Size(800, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // ⚠ **不要**给这个 store 挂 `addTearDown(store.dispose)`：它被 override 进
    // ProviderScope，容器销毁时会自己 dispose 一次 —— 挂上去就是二次 dispose，
    // 报「A HomeLayoutStore was used after being disposed」（实测）。
    final store = HomeLayoutStore();
    await tester.runAsync(store.ensureLoaded);
    // 先开到「两块都是卡片」，滑杆才是可用的。
    await tester.runAsync(() => store.saveCardStyle(HomeCardStyle.both));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeLayoutStoreProvider.overrideWith((ref) => store)],
        child: const MaterialApp(
          home: Scaffold(body: SettingsHomeLayoutCard()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('卡片间距'), findsOneWidget);
    expect(find.byKey(const Key('homeCardGapSlider')), findsOneWidget);
    // 卡片圆角（十五轮）也在这张卡里。
    expect(find.text('卡片圆角'), findsOneWidget);
    expect(find.byKey(const Key('homeCardRadiusSlider')), findsOneWidget);
    expect(
      find.byKey(const Key('homeCardRadiusSummary')),
      findsOneWidget,
      reason: '要显示当前 px',
    );
    final metrics = cardGapMetricsOf(store.cardGap);
    expect(
      find.text('卡片之间 ${metrics.between.round()} · 距窗口 ${metrics.edge.round()}'),
      findsOneWidget,
      reason: '读数要把「卡片之间 / 距窗口」直接说清',
    );
    expect(tester.takeException(), isNull);
  });

  // 用户 2026-10-09 十五轮：「我希望卡片圆角大小也是可控的」。
  group('卡片圆角', () {
    test('默认 = 页面小卡口径；夹取 / 脏值 / 步长 1', () async {
      final store = HomeLayoutStore();
      addTearDown(store.dispose);
      await store.ensureLoaded();
      // 用户 2026-10-09 十六轮：「卡片圆角样式我希望与毕业学分页的卡片圆角样式相同」。
      // 毕业学分页的卡片全是 `FluentCard`，其默认圆角 = `FluentRadius.overlay`。
      expect(
        kCardRadiusDefault,
        FluentRadius.overlay,
        reason: '两边必须同源（引用同一个常量，而不是各写一个 8）',
      );
      expect(
        kCardRadiusDefault,
        FluentCard.defaultRadius,
        reason: '这条是"毕业学分页用的就是那一档"的凭证：'
            '`FluentCard` 的默认圆角若改，这里会红',
      );
      expect(store.cardRadius, kCardRadiusDefault);

      await store.saveCardRadius(999);
      expect(store.cardRadius, kCardRadiusMax, reason: '越界夹回上限');
      expect(parseCardRadius(homeBox.get(homeCardRadiusKey)), kCardRadiusMax);

      await store.saveCardRadius(-5);
      expect(store.cardRadius, kCardRadiusMin, reason: '越界夹回下限（0 = 直角）');

      // 逐格都能取到（步长 1），且落盘往返还原。
      for (final r in kCardRadiusStops) {
        await store.saveCardRadius(r);
        expect(store.cardRadius, r, reason: '$r');
        expect(parseCardRadius(homeBox.get(homeCardRadiusKey)), r, reason: '$r 往返');
      }

      await homeBox.put(homeCardRadiusKey, 'oops');
      final reloaded = HomeLayoutStore();
      addTearDown(reloaded.dispose);
      await reloaded.ensureLoaded();
      expect(reloaded.cardRadius, kCardRadiusDefault, reason: '脏值回落默认');
    });

    test('★ 档位表 = 0..28 的每个整数（步长 1，与滑杆 divisions 同口径）', () {
      expect(kCardRadiusStops, [
        for (var v = kCardRadiusMin; v <= kCardRadiusMax; v += 1) v.toDouble(),
      ]);
      expect(
        kCardRadiusStops.length,
        (kCardRadiusMax - kCardRadiusMin).round() + 1,
        reason: '`divisions` 是段数、档位表是刻度数，差 1 —— 别写错（间距那轮踩过）',
      );
      for (final r in kCardRadiusStops) {
        expect(snapCardRadius(r), r, reason: '$r 吸附后必须还是 $r');
      }
    });

    test('圆角与间距 / 形态互不干扰（同 box 四个 key）', () async {
      final store = HomeLayoutStore();
      addTearDown(store.dispose);
      await store.ensureLoaded();
      await store.save(HomeLayout.sidebar);
      await store.saveCardStyle(HomeCardStyle.both);
      await store.saveCardGap(9);
      await store.saveCardRadius(4);

      expect(parseCardGap(homeBox.get(homeCardGapKey)), 9);
      expect(homeBox.get(homeCardStyleKey), HomeCardStyle.both.name);
      expect(homeBox.get(homeLayoutPrefsKey), HomeLayout.sidebar.name);
      expect(parseCardRadius(homeBox.get(homeCardRadiusKey)), 4);
    });

    // 十六轮把默认值从 12 改成 8（= 毕业学分页那套 Fluent 卡片）。
    //
    // ⚠ **刻意不做"老存档迁移"**：`_load()` 里只要出现一次写盘（`box.put`/`delete`），
    // 本仓的 Hive + 假异步测试环境就会把**每个建 store 的用例挂到超时**
    // （2026-10-09 十六轮实测：整份本文件从 1 秒变成逐例 12~30 秒超时，连不 await 的
    // `box.put` 也一样）。所以改默认值**只改常量**：盘上已存过 12 的用户保持 12，
    // 想要新默认按设置页那个「恢复默认」。这条注释就是防止有人再写一遍迁移。
    test('★ 默认值只由常量决定：盘上有值就听盘上的（不迁移）', () async {
      await homeBox.put(homeCardRadiusKey, '12');
      final store = HomeLayoutStore();
      addTearDown(store.dispose);
      await store.ensureLoaded();
      expect(
        store.cardRadius,
        12,
        reason: '盘上是 12 就显示 12 —— 不许偷偷改成默认值（那需要一个写盘迁移，'
            '而写盘迁移会把测试挂死，见上面的注释）',
      );
      expect(homeBox.get(homeCardRadiusKey), '12', reason: '也不许顺手改盘');
    });

    test('★ 脏值回落（越界/非数字都不崩）', () async {
      for (final bad in ['oops', '-3', '999', '']) {
        await homeBox.put(homeCardRadiusKey, bad);
        final store = HomeLayoutStore();
        addTearDown(store.dispose);
        await store.ensureLoaded();
        final expected = switch (bad) {
          '-3' => kCardRadiusMin,
          '999' => kCardRadiusMax,
          _ => kCardRadiusDefault,
        };
        expect(store.cardRadius, expected, reason: '"$bad" 要落成 $expected');
      }
    });
  });

  test('布局与卡片样式同 box 不同 key：存一个不动另一个', () async {
    final store = HomeLayoutStore();
    addTearDown(store.dispose);
    await store.ensureLoaded();

    await store.save(HomeLayout.sidebar);
    expect(homeBox.get(homeLayoutPrefsKey), HomeLayout.sidebar.name);
    expect(
      homeBox.get(homeCardStyleKey),
      isNull,
      reason: '存布局不该顺手写卡片样式',
    );

    await store.saveCardStyle(HomeCardStyle.content);
    expect(homeBox.get(homeCardStyleKey), HomeCardStyle.content.name);
    expect(
      homeBox.get(homeLayoutPrefsKey),
      HomeLayout.sidebar.name,
      reason: '存卡片样式不该覆盖布局',
    );
    expect(store.layout, HomeLayout.sidebar);
    expect(store.cardStyle, HomeCardStyle.content);
  });

  // ---------------------------------------------------------------------------
  // ⚠ 回归守卫：改卡片样式**不许让内嵌的设置页跳回顶部**（用户 2026-10-09 九轮报的 bug）。
  //
  // 根因（已修）：`CardFrame` 原先在 `card == false` 时 `return child`，调用方又挂了
  // `ValueKey(card ? 'Card…' : 'Plain…')` —— **换 key + 换组件类型 = 整棵子树重新挂载**，
  // 内嵌的设置页（含它的 `ListView`）一起重建，滚动位置归零（实测 `pixels 1386 → 0`）。
  // 现在 `CardFrame` 两种形态都返回同一个 `Container` + 自己补间 decoration。
  //
  // 这条用例刻意**按生产装配搭宿主**（内容卡 + `_paneCard` 的 AnimatedPadding +
  // `HomeDetailPane(设置页)`），否则复现不出来：单独的 `SettingsScreen` 与单独的
  // `HomeDetailPane` 都不跳（实测），只有「外面的卡片层换了子树」才把滚动带塌。
  // ---------------------------------------------------------------------------
  testWidgets('★ 回归：改卡片形态 / 间距都不许把内嵌设置页的滚动带塌', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // ⚠ **不能靠反复 `pumpWidget(host())` 来"重建"**：那会换掉整棵树的 element
    // （连 `SettingsScreen` 的 State 都是新的），滚动位置必然归零 —— 测出来的
    // 是"重挂载"而不是生产路径。生产里是 `HomeScreen` 自己 `ref.watch` 到变化、
    // **原地重建**。所以这里用一个 `ValueNotifier` 驱动同一棵树原地重建。
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);

    var card = false;
    var edge = 0.0;
    var between = 1.0;

    Widget host() => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: revision,
            builder: (context, _, _) => CardFrameBackdrop(
              // 复刻 `home_screen.dart` 的 `_buildSidebarBody`：
              // 背景层（标题栏色）→ 逐边留白 → 卡片框 → 内嵌面板。**一律不换 key**。
              visible: card,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(width: 232),
                  SizedBox(width: between),
                  Expanded(
                    child: AnimatedPadding(
                      duration: CardFrame.duration,
                      padding: EdgeInsets.only(
                        right: edge,
                        bottom: edge,
                      ),
                      child: CardFrame(
                        card: card,
                        child: HomeDetailPane(
                          paneKey: 'settings',
                          builder: () => const SettingsScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 滚到「主页布局」那一段（卡片样式就在这一节里）。
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pump();
    final scrollable = find.byType(Scrollable).first;
    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    expect(before, greaterThan(0), reason: '先把页面滚下去，才测得出"跳回顶部"');

    // 一比一复刻「用户在设置页点了『侧栏 + 内容区』（a 还是默认）」之后的整条路径：
    // 背景层由透明变标题栏色、块间缝 1 → a、内容卡出现（边距 a + 描边 + 阴影）。
    card = true;
    edge = cardGapMetricsOf(kCardGapDefault).edge;
    between = cardGapMetricsOf(kCardGapDefault).between;
    revision.value++;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      before,
      reason: '换卡片形态不许把内嵌页滚动位置带塌'
          '（`CardFrame` / `CardFrameBackdrop` 一旦"换组件类型或换 key"就会）',
    );

    // 再改一次「间距 a」：同样是原地重建，同样不许跳。
    card = true;
    edge = cardGapMetricsOf(kCardGapMax).edge;
    between = cardGapMetricsOf(kCardGapMax).between;
    revision.value++;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      before,
      reason: '改卡片间距也不许把内嵌页滚动位置带塌',
    );
    expect(tester.takeException(), isNull);
  });

}
