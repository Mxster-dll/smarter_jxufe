import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/card_frame.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/home/presentation/home_sidebar.dart';

/// 左侧导航栏守卫。
///
/// 第 1 条（2026-09-15）：分组齐全、条目齐全、组序固定、行高一致。
/// 第 2 条（同日二轮）：侧栏点击改成**选中**（`onSelect`），页面由 `HomeDetailPane`
/// 内嵌到右侧 —— 所以这里额外守「点条目回调选中而不是自己 push」「选中态高亮」
/// 「顶部『数据一览』= 概览行，且是默认选中项」。
void main() {
  HomeServiceEntry entry(
    String title,
    HomeServiceGroup group, {
    VoidCallback? onTap,
    Widget Function()? builder,
    bool sidebarPinned = false,
    Color accent = const Color(0xFFC3282E),
  }) => HomeServiceEntry(
    icon: Icons.abc,
    title: title,
    subtitle: '$title 说明',
    group: group,
    accent: accent,
    builder: builder ?? () => const SizedBox.shrink(),
    onTap: onTap ?? () {},
    sidebarPinned: sidebarPinned,
  );

  /// ⚠ 「课程」与「选课」**故意用不同 accent**：颜色补间那条守卫全靠它 ——
  /// 全用同一个红的话，插值出来跟起点终点一模一样，测试会**假绿**
  /// （实测踩过：旧/中/新三个色值完全相同，断言 `isNot(old)` 才把它抓出来）。
  List<HomeServiceEntry> stubEntries({VoidCallback? onTap}) => [
    entry('课程', HomeServiceGroup.ims, onTap: onTap),
    entry(
      '选课',
      HomeServiceGroup.ims,
      onTap: onTap,
      accent: const Color(0xFF536DFE),
    ),
    entry('分数估计', HomeServiceGroup.study, onTap: onTap),
    entry('宿舍电费', HomeServiceGroup.campus, onTap: onTap),
    entry('校历', HomeServiceGroup.info, onTap: onTap),
  ];

  /// 桩数据里**真的有条目**的分组（按枚举顺序）。
  ///
  /// ⚠ 断言不要直接遍历 `HomeServiceGroup.values`：侧栏**不画空分组**
  /// （见「空分组不渲染标题」一例），所以枚举里新增一个分组而桩数据没跟上时，
  /// `find.text(g.title)` 会找不到而报「could not find」。
  /// 2026-10-07 新增 `fillForm`（填表助手独立成组）时就踩了这条。
  List<HomeServiceGroup> stubGroups() => [
    for (final g in HomeServiceGroup.values)
      if (stubEntries().any((e) => e.group == g)) g,
  ];

  Future<void> pumpSidebar(
    WidgetTester tester,
    List<HomeServiceEntry> entries, {
    String? selectedTitle,
    ValueChanged<HomeServiceEntry>? onSelect,
    VoidCallback? onOverview,
    Widget? footer,
    bool card = false,
    bool collapsed = false,
    VoidCallback? onToggleCollapsed,
    double radius = kCardFrameRadius,
    bool cardShadow = false,
    Size size = const Size(1200, 900),
    Brightness? brightness,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        // ⚠ 默认不传 theme（旧用例的逐像素口径不变）；要验"深色下的取值"时显式给亮度 ——
        // 光设 `platformBrightnessTestValue` 不够：本 harness 的 `MaterialApp` 没有
        // `darkTheme`，系统亮度影响不到 `Theme.of(context)`（实测踩过）。
        theme: brightness == null
            ? null
            : (brightness == Brightness.dark ? appDarkTheme : appLightTheme)
                  // ⚠ 本仓 `_themeOf` 只设 `colorScheme`，没设 `ThemeData.brightness`
                  // → 深色主题里 `Theme.of(context).brightness` 仍是 light（自相矛盾）。
                  // 这里显式对齐，免得守卫量到"假亮度"。
                  .copyWith(brightness: brightness),
        home: Scaffold(
          body: Row(
            children: [
              HomeSidebar(
                entries: entries,
                card: card,
                radius: radius,
                cardShadow: cardShadow,
                collapsed: collapsed,
                onToggleCollapsed: onToggleCollapsed,
                selectedTitle: selectedTitle,
                onSelect: onSelect,
                onOverview: onOverview,
                footer: footer,
              ),
            ],
          ),
        ),
      ),
    );
    // ⚠ 那个会飞的高亮框要**等一帧**才出现：它的矩形是在 `initState` 的
    // post-frame 回调里量出来的（量之前没有矩形可画）。所以这里补一帧 ——
    // 少了它，凡是找 `homeSidebarFlyingPill` 的断言都会 "Found 0 widgets"
    // （实测踩过：只 `pumpWidget` 不 `pump` 就会）。
    await tester.pump();
  }

  group('顶部固定项（紧贴「数据一览」）', () {
    // 用户 2026-09-19：「电脑端AI助手在侧边栏放到和"数据一览"下方紧贴」。
    testWidgets('固定项渲染在「数据一览」正下方，且不在所属分组里重复出现', (tester) async {
      await pumpSidebar(
        tester,
        [
          entry('AI 助手', HomeServiceGroup.info, sidebarPinned: true),
          entry('课程', HomeServiceGroup.ims),
          entry('校历', HomeServiceGroup.info),
        ],
        onOverview: () {},
      );

      final overview = tester.getRect(
        find.byKey(const Key('homeSidebarOverview')),
      );
      final pinned = tester.getRect(
        find.byKey(const Key('homeSidebarItem-AI 助手')),
      );

      // 紧贴 = 固定项顶边就是「数据一览」底边，中间不夹分组标题、不夹分割线。
      expect(pinned.top, closeTo(overview.bottom, 0.5));
      // 两行同高（rowHeight），视觉上是一对。
      expect(pinned.height, HomeSidebar.rowHeight);

      // 只此一处：不能被「数据与信息」那个分组再渲染一遍。
      expect(find.byKey(const Key('homeSidebarItem-AI 助手')), findsOneWidget);
      // 它下面才是第一个分组标题；同组的其它条目照旧在分组里。
      expect(
        tester.getRect(find.text('教务系统')).top,
        greaterThan(pinned.bottom),
      );
      expect(find.byKey(const Key('homeSidebarItem-校历')), findsOneWidget);
      // 固定项本身不额外产生分割线。
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('点固定项走的还是 onSelect（内嵌右侧面板，不自己 push）', (tester) async {
      HomeServiceEntry? selected;
      await pumpSidebar(
        tester,
        [entry('AI 助手', HomeServiceGroup.info, sidebarPinned: true)],
        onOverview: () {},
        onSelect: (e) => selected = e,
      );

      await tester.tap(find.byKey(const Key('homeSidebarItem-AI 助手')));
      expect(selected?.title, 'AI 助手');
    });

    test('目录里恰好一条固定项，且就是「AI 助手」', () {
      final entries = homeServiceEntries(push: (_) {});
      expect(
        homePinnedSidebarEntries(entries).map((e) => e.title).toList(),
        ['AI 助手'],
        reason: '增删侧栏顶部固定项请同步本测试与 AGENTS.md §17',
      );
      // 固定项仍然属于某个分组（`homeServiceEntriesInGroup` 照旧能取到它，
      // 「分组并集 = 全目录」那条不变量不受影响），只是侧栏渲染时会摘出去。
      final inGroup = homeServiceEntriesInGroup(entries, HomeServiceGroup.info);
      expect(inGroup.map((e) => e.title), contains('AI 助手'));
    });
  });

  /// 侧栏框线口径的守卫 —— **浅色 + 深色各跑一遍**。
  ///
  /// 2026-09-17：「顶部"数据一览"和教务系统之间不要显示分割线」；
  /// 2026-10-09 十三轮：「侧边栏不要有边框线」（把底部那条也撤了）；
  /// **2026-10-10 三十二轮（现行）**：「我希望侧边栏底部固定部分要有一个顶部框线，
  /// 但是不要有别的框线」—— 于是底部那一条**回来**，其余仍然一条不许有。
  ///
  /// ⚠ 为什么必须两种亮度都跑：`AppColors.hairline` 与裸
  /// `outlineVariant.withValues(alpha: 0.6)` 在**浅色下逐值相同**（实测：只跑浅色时
  /// 把线色换回裸写法，守卫照样绿 —— 等于没测），差别只出现在深色侧
  /// （`outlineVariant` 深色下自带 10% alpha，`withValues` 是替换不是相乘）。
  testWidgets('★ 侧栏只有底部固定区上沿那一条框线，别处一条都没有（浅 / 深各一遍）', (
    tester,
  ) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await pumpSidebar(
        tester,
        stubEntries(),
        onOverview: () {},
        selectedTitle: null,
        brightness: brightness,
        // 给一个真的 footer 行：确认那条线是"固定区上沿"而不是别处冒出来的。
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeSidebarFooterRow(
              key: homeSidebarProfileKey,
              leading: const Icon(Icons.person_outline, size: 18),
              label: '我的',
              onTap: () {},
            ),
          ],
        ),
      );

      final where = '（$brightness 亮度）';
      // ⚠ **必须 `pumpAndSettle`**：`MaterialApp` 换 theme 是**补间**的，
      // 紧接着那一帧量到的还是上一轮的主题（实测：`[light, dark]` 循环里第二轮
      // 读出来仍是 light —— 白折腾了半天，真因就在这一行）。
      await tester.pumpAndSettle();

      // 判据用 `colorScheme.brightness`（= `AppColors.isDark` 用的那个），
      // **不是** `Theme.of(...).brightness`（本仓 `_themeOf` 不设后者，虽已显式对齐）。
      expect(
        Theme.of(
          tester.element(find.byKey(homeSidebarProfileKey)),
        ).colorScheme.brightness,
        brightness,
        reason: '用例前提：这一轮真的跑在 $brightness 下$where',
      );

      final overview = tester.getRect(
        find.byKey(const Key('homeSidebarOverview')),
      );
      final firstGroupTitle = tester.getRect(
        find.text(HomeServiceGroup.values.first.title),
      );
      expect(
        HomeServiceGroup.values.first.title,
        '教务系统',
        reason: '第一个分组应当就是教务系统（这条守卫的前提）',
      );
      expect(
        firstGroupTitle.top,
        greaterThanOrEqualTo(overview.bottom - 0.5),
        reason: '「数据一览」与教务系统之间不许有线$where',
      );

      // ① **不再用 `Divider` 实现**：侧栏里一个 `Divider` 都不该有。
      expect(
        find.byType(Divider),
        findsNothing,
        reason: '底部那条线不该是 Divider（收起态的窄轨里它会横向溢出）$where',
      );

      // ② 底部固定区上沿**必须**有那条线。
      //
      final footerTop = tester.getRect(find.byKey(homeSidebarProfileKey)).top;

      // ③ 底部固定区上沿那道**轻分割线**（现行口径 · 三十四轮）：
      //    「不连接左右边界的轻分割线，去除阴影」。
      final lineRect = tester.getRect(
        find.byKey(const Key('homeSidebarFooterDivider')),
      );
      final barRect = tester.getRect(find.byKey(const Key('homeSidebar')));
      expect(find.byKey(homeSidebarProfileKey), findsOneWidget, reason: where);

      // ★ **不连接左右边界**：左右各退 `pillInset`（与高亮胶囊左右对齐，
      //   不另立一套留白口径）—— 这是本轮改动的重点。
      expect(
        lineRect.left - barRect.left,
        HomeSidebar.pillInset,
        reason: '★ 分割线左端不许贴到侧栏左边界$where',
      );
      expect(
        barRect.right - lineRect.right,
        HomeSidebar.pillInset,
        reason: '★ 分割线右端不许贴到侧栏右边界$where',
      );
      expect(lineRect.height, 1, reason: '1px 细线$where');
      expect(
        lineRect.top,
        lessThanOrEqualTo(footerTop + 0.5),
        reason: '它应当在固定区上沿（实测 line=${lineRect.top}，固定区 top=$footerTop）'
            '$where',
      );

      // ★ **没有阴影**：整棵树里不许再出现"只有上边 + 带 boxShadow"的那套
      //   （三十三轮试过，用户 2026-10-10：「去除阴影」）。
      final painted = <BoxShadow>[];
      void collectShadows(Element el) {
        final w = el.widget;
        if (w is DecoratedBox) {
          final d = w.decoration;
          if (d is BoxDecoration) painted.addAll(d.boxShadow ?? const []);
        }
        el.visitChildren(collectShadows);
      }

      collectShadows(tester.binding.rootElement!);
      // 卡片形态那圈阴影不在本用例里（`card: false`），所以这里应当是空的。
      expect(
        painted.where((s) => s.blurRadius > 0).isEmpty,
        isTrue,
        reason: '★ 固定区上沿不许再画阴影（三十四轮「去除阴影」）—— 实测 $painted$where',
      );

      // 线色 = `AppColors.hairline`（换回裸写法在深色下会变成 60% 白，2026-09-17
      // 实测过"太亮"）。
      final lineColor = tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byKey(const Key('homeSidebarFooterDivider')),
              matching: find.byType(ColoredBox),
            ),
          )
          .color;
      expect(
        lineColor,
        AppColors.hairline(tester.element(find.byKey(homeSidebarProfileKey))),
        reason: '★ 线色 = `AppColors.hairline` —— 换成裸 '
            '`outlineVariant.withValues(alpha: 0.6)` 在深色下会变成 60% 白（"太亮"）$where',
      );
    }
  });


  testWidgets('按分组列出全部条目，且分组顺序 = 枚举顺序', (tester) async {
    await pumpSidebar(tester, stubEntries());

    for (final e in stubEntries()) {
      expect(
        find.byKey(Key('homeSidebarItem-${e.title}')),
        findsOneWidget,
        reason: e.title,
      );
    }
    // 分组标题都在，且自上而下顺序固定。
    final offsets = [
      for (final g in stubGroups()) tester.getTopLeft(find.text(g.title)).dy,
    ];
    final sorted = [...offsets]..sort();
    expect(offsets, sorted, reason: '分组标题应按 HomeServiceGroup 顺序排列');
  });

  testWidgets('空分组不渲染标题', (tester) async {
    await pumpSidebar(tester, [entry('课程', HomeServiceGroup.ims)]);

    expect(find.text(HomeServiceGroup.ims.title), findsOneWidget);
    expect(find.text(HomeServiceGroup.study.title), findsNothing);
    expect(find.text(HomeServiceGroup.campus.title), findsNothing);
    expect(find.text(HomeServiceGroup.info.title), findsNothing);
  });

  testWidgets('没给 onSelect 时回落条目自带 onTap（旧行为兜底）', (tester) async {
    var tapped = '';
    await pumpSidebar(tester, [
      entry('课程', HomeServiceGroup.ims, onTap: () => tapped = '课程'),
      entry('校历', HomeServiceGroup.info, onTap: () => tapped = '校历'),
    ]);

    await tester.tap(find.byKey(const Key('homeSidebarItem-校历')));
    expect(tapped, '校历');
  });

  testWidgets('给了 onSelect 时只回调选中，不 push（第 2 条：内嵌而非跳转）', (tester) async {
    var pushed = '';
    HomeServiceEntry? selected;
    await pumpSidebar(
      tester,
      [
        entry('课程', HomeServiceGroup.ims, onTap: () => pushed = '课程'),
        entry('校历', HomeServiceGroup.info, onTap: () => pushed = '校历'),
      ],
      onSelect: (e) => selected = e,
    );

    await tester.tap(find.byKey(const Key('homeSidebarItem-校历')));
    expect(selected?.title, '校历');
    expect(pushed, isEmpty, reason: 'onSelect 给了就不该再跳转整页');
  });

  // 用户 2026-10-09 十轮：「我希望改成圆角高亮，侧边条改成短的圆角的」——
  // 选中态从「左侧通高 3px 指示条」改成**圆角胶囊**（同色淡底 + 很淡的同色描边）。
  testWidgets('选中行是圆角胶囊高亮（不再是左边条）', (tester) async {
    await pumpSidebar(
      tester,
      stubEntries(),
      selectedTitle: '分数估计',
      onSelect: (_) {},
    );

    /// 那**一个**会飞的高亮框（2026-10-10 三十一轮起，高亮不再是行内的一层 Container）。
    BoxDecoration pillOf(String title) => tester
        .widget<DecoratedBox>(find.byKey(const Key('homeSidebarFlyingPill')))
        .decoration
        as BoxDecoration;

    final selected = pillOf('分数估计');
    expect(
      selected.borderRadius,
      BorderRadius.circular(HomeSidebar.pillRadius),
      reason: '高亮必须是圆角（十轮口径）',
    );
    expect(
      selected.color?.a ?? 0,
      greaterThan(0.05),
      reason: '选中的胶囊要有底色',
    );
    // ⚠ **不再有左侧指示条**：`BoxDecoration.border` 要么为 null，要么是四边同宽的
    // 胶囊描边（`Border.all`），**不能**是「只有左边」的那种。
    if (selected.border != null) {
      final b = selected.border! as Border;
      expect(
        b.left.width,
        b.top.width,
        reason: '有描边时四边同宽（Border.all）；出现"只加粗左边"就是旧指示条复活了',
      );
      expect(b.right.width, b.top.width);
      expect(b.bottom.width, b.top.width);
    }

    // 三十一轮起高亮**只有一个**，所以判据从"未选中那行没有底色"改成
    // "那个框就停在**选中那一行**上"（飞行语义另有一组专门守，见「会飞的高亮框」）。
    expect(
      tester.getCenter(find.byKey(const Key('homeSidebarFlyingPill'))).dy,
      closeTo(
        tester.getCenter(find.byKey(const Key('homeSidebarItem-分数估计'))).dy,
        0.5,
      ),
      reason: '高亮框应当与选中行同心',
    );

    // 胶囊比行矮（上下各留 pillVerticalInset），圆角才看得出来。
    final outer = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const Key('homeSidebarItem-分数估计')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      tester.getSize(find.byKey(const Key('homeSidebarItem-分数估计'))).height,
      HomeSidebar.rowHeight,
      reason: '行高契约不变',
    );
    expect(
      (outer.padding! as EdgeInsets).vertical / 2,
      HomeSidebar.pillVerticalInset,
      reason: '胶囊上下要留出留白（否则圆角贴边看不出来）',
    );

    final selectedText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('homeSidebarItem-分数估计')),
        matching: find.text('分数估计'),
      ),
    );
    expect(selectedText.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('顶部「数据一览」：默认选中、点击回概览', (tester) async {
    var overviewTaps = 0;
    await pumpSidebar(
      tester,
      stubEntries(),
      onSelect: (_) {},
      onOverview: () => overviewTaps++,
    );

    expect(find.byKey(const Key('homeSidebarOverview')), findsOneWidget);
    expect(find.text(homeSidebarOverviewTitle), findsOneWidget);
    // 没传 selectedTitle → 概览行就是当前选中项。
    expect(
      tester
          .widget<Text>(find.text(homeSidebarOverviewTitle))
          .style
          ?.fontWeight,
      FontWeight.w600,
    );
    // 概览行在第一个分组标题之上。
    expect(
      tester.getTopLeft(find.text(homeSidebarOverviewTitle)).dy,
      lessThan(tester.getTopLeft(find.text(HomeServiceGroup.ims.title)).dy),
    );

    await tester.tap(find.byKey(const Key('homeSidebarOverview')));
    expect(overviewTaps, 1);
  });

  testWidgets('没给 onOverview 时不渲染概览行（旧调用点零改动）', (tester) async {
    await pumpSidebar(tester, stubEntries());
    expect(find.byKey(const Key('homeSidebarOverview')), findsNothing);
  });

  testWidgets('侧栏宽度 = homeSidebarWidth，条目行高一致', (tester) async {
    await pumpSidebar(tester, stubEntries());

    final bar = tester.getSize(find.byKey(const Key('homeSidebar')));
    expect(bar.width, homeSidebarWidth);
    for (final title in ['课程', '分数估计', '校历']) {
      expect(
        tester.getSize(find.byKey(Key('homeSidebarItem-$title'))).height,
        HomeSidebar.rowHeight,
        reason: title,
      );
    }
  });

  testWidgets('长标题不溢出（省略号）', (tester) async {
    await pumpSidebar(tester, [
      entry('这是一个非常非常非常长的服务名称用于验证省略号', HomeServiceGroup.ims),
    ]);
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------------
  // 底部固定区（用户 2026-09-16 裁定：「桌面端把标题栏里的头像和设置都应该改到侧边
  // 导航栏，设置在下，头像在上，并且这两个是固定在底部不浮动的」）。
  // 生产装配在 `home_screen.dart`（头像 = AccountAvatar + 设置 = 齿轮图标），
  // 这里用假 leading 只守侧栏自身的排版与固定行为。
  // ---------------------------------------------------------------------------
  group('底部固定区', () {
    Widget footerWith({
      VoidCallback? onProfile,
      VoidCallback? onSettings,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSidebarFooterRow(
          key: homeSidebarProfileKey,
          leading: const Icon(Icons.person_outline, size: 18),
          label: '我的',
          onTap: onProfile ?? () {},
        ),
        HomeSidebarFooterRow(
          key: homeSidebarSettingsKey,
          leading: const Icon(Icons.settings_outlined, size: 18),
          label: '设置',
          onTap: onSettings ?? () {},
        ),
      ],
    );

    testWidgets('头像行在上、设置行在下，Key 与行高契约正确', (tester) async {
      await pumpSidebar(tester, stubEntries(), footer: footerWith());

      expect(find.byKey(homeSidebarProfileKey), findsOneWidget);
      expect(find.byKey(homeSidebarSettingsKey), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(homeSidebarProfileKey)).dy,
        lessThan(tester.getTopLeft(find.byKey(homeSidebarSettingsKey)).dy),
        reason: '用户裁定：头像在上、设置在下',
      );
      expect(
        tester.getSize(find.byKey(homeSidebarProfileKey)).height,
        HomeSidebar.footerRowHeight,
      );
    });

    testWidgets('固定在底部：列表滚动后它不动，且始终贴侧栏底边', (tester) async {
      // 矮视口 + 21 条服务 → 列表必然可滚。
      await pumpSidebar(
        tester,
        [
          for (var i = 0; i < 21; i++)
            entry('服务$i', HomeServiceGroup.values[i % 4]),
        ],
        footer: footerWith(),
        size: const Size(1200, 420),
      );

      final bar = tester.getRect(find.byKey(const Key('homeSidebar')));
      final before = tester.getTopLeft(find.byKey(homeSidebarSettingsKey)).dy;
      expect(
        tester.getBottomLeft(find.byKey(homeSidebarSettingsKey)).dy,
        closeTo(bar.bottom, 1),
        reason: '固定区必须贴侧栏底边',
      );

      // 滚服务列表 → 固定区纹丝不动。
      await tester.drag(
        find.byKey(const Key('homeSidebarItem-服务0')),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(homeSidebarSettingsKey)).dy,
        closeTo(before, 0.5),
      );
    });

    testWidgets('点两行分别回传「我的」与「设置」', (tester) async {
      final taps = <String>[];
      await pumpSidebar(
        tester,
        stubEntries(),
        footer: footerWith(
          onProfile: () => taps.add('profile'),
          onSettings: () => taps.add('settings'),
        ),
      );

      await tester.tap(find.byKey(homeSidebarProfileKey));
      await tester.tap(find.byKey(homeSidebarSettingsKey));
      await tester.pump();
      expect(taps, ['profile', 'settings']);
    });

    testWidgets('未传 footer 时底部区整块不画（旧调用点不受影响）', (tester) async {
      await pumpSidebar(tester, stubEntries());
      expect(find.byKey(homeSidebarProfileKey), findsNothing);
      expect(find.byKey(homeSidebarSettingsKey), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // 高亮框的**移动 + 颜色/尺寸变化**动画
  // （用户 2026-10-10 三十轮：「我希望增加左侧侧边栏高亮切换动画」→
  //   三十一轮：「我希望是高亮框有移动和颜色大小改变动画」）。
  //
  // 口径（见 `HomeSidebar.pillDuration` 的注释）：侧栏里**只有一个**高亮框，
  // 换选中项时它从旧行的矩形**平移到**新行的矩形，颜色同时从旧条目的 accent 渐变过来。
  // ---------------------------------------------------------------------------
  group('高亮框会飞（移动 + 颜色/尺寸补间）', () {
    /// 那个高亮框此刻画出来的填充色。
    ///
    /// ⚠ 读 **render object 上正在生效的 decoration**（`RenderDecoratedBox.decoration`）——
    /// 那才是插值出来的颜色。读 `DecoratedBox.decoration` 是 widget 上的**目标值**，
    /// 动画中途也一直是终点值，"有没有补间"根本测不出来。
    Color? pillColor(WidgetTester tester) {
      final render = tester.renderObject(
        find.byKey(const Key('homeSidebarFlyingPill')),
      );
      final decoration = (render as RenderDecoratedBox).decoration;
      if (decoration is! BoxDecoration) return null;
      return decoration.color;
    }

    Rect pillRect(WidgetTester tester) =>
        tester.getRect(find.byKey(const Key('homeSidebarFlyingPill')));

    /// 在**同一个** `HomeSidebar` 实例上换选中项（不重挂），让补间真的跑起来。
    ///
    /// ⚠ 不能在同一个用例里再调一次 `pumpSidebar`：那个 helper 每次都
    /// `addTearDown(tester.view.reset)`，第二次调用会让整棵树重挂 → State 重建 →
    /// **动画从终点开始**（实测：中间帧直接是终值，看着像"没动画"）。
    Future<void> pumpWithSelection(
      WidgetTester tester,
      String? title, {
      bool collapsed = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                HomeSidebar(
                  entries: stubEntries(),
                  selectedTitle: title,
                  collapsed: collapsed,
                  onSelect: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('★ 换选中项：框**从旧行飞到新行**（中途停在两行之间）', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpWithSelection(tester, '课程');
      await tester.pumpAndSettle();
      final startY = pillRect(tester).top;
      final courseY = tester
          .getRect(find.byKey(const Key('homeSidebarItem-课程')))
          .top;
      final electiveY = tester
          .getRect(find.byKey(const Key('homeSidebarItem-选课')))
          .top;
      expect(
        startY,
        closeTo(courseY + HomeSidebar.pillVerticalInset, 0.5),
        reason: '起点应当是「课程」那一行的胶囊位置',
      );
      expect(electiveY, greaterThan(courseY), reason: '「选课」在「课程」下面（用例前提）');

      // 换成「选课」 —— **同一个实例上重建**，飞行才会跑。
      await pumpWithSelection(tester, '选课');
      await tester.pump();
      await tester.pump(HomeSidebar.pillDuration ~/ 2);

      final midY = pillRect(tester).top;
      expect(
        midY,
        greaterThan(startY + 1),
        reason: '★ 中途必须已经离开起点（实测 $midY vs 起点 $startY）'
            '—— 等于起点就是没动画（瞬切）',
      );
      expect(
        midY,
        lessThan(electiveY + HomeSidebar.pillVerticalInset - 1),
        reason: '★ 中途必须**还没到**终点（实测 $midY）—— 直接到终点也是没动画',
      );

      await tester.pumpAndSettle();
      expect(
        pillRect(tester).top,
        closeTo(electiveY + HomeSidebar.pillVerticalInset, 0.5),
        reason: '飞完必须正好落在「选课」那一行上',
      );
    });

    testWidgets('★ 颜色**一起**补间：中途既不是旧色也不是新色', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpWithSelection(tester, '课程');
      await tester.pumpAndSettle();
      final oldColor = pillColor(tester);

      await pumpWithSelection(tester, '选课');
      // ⚠ 换项之后要**先推一帧**让 `_retarget` 跑（它挂在 post-frame 回调上），
      // 再推进半程；否则量到的还是上一帧的状态。
      await tester.pump();
      await tester.pump(HomeSidebar.pillDuration ~/ 2);
      final midColor = pillColor(tester);

      await tester.pumpAndSettle();
      final newColor = pillColor(tester);

      expect(oldColor, isNotNull);
      expect(newColor, isNotNull);
      expect(
        midColor,
        isNot(oldColor),
        reason: '中途不该还是旧色（那就是没补间）',
      );
      expect(
        midColor,
        isNot(newColor),
        reason: '中途也不该已经是新色（那就是瞬切）',
      );
      // 颜色确实在旧色与新色之间（逐通道比，容差留给缓动）。
      expect(
        (midColor!.b - oldColor!.b).abs() + (midColor.r - oldColor.r).abs(),
        greaterThan(0),
        reason: '两个条目的 accent 不同，插值后必然在某一通道上不同',
      );
    });

    testWidgets('★ 收起态：框的**宽度也跟着补间**（尺寸改变动画）', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpWithSelection(tester, '课程');
      await tester.pumpAndSettle();
      final wide = pillRect(tester).width;
      expect(wide, greaterThan(HomeSidebar.collapsedWidth));

      // 收起侧栏：宽度是补间的（`collapseDuration`），高亮框要跟着量到的行一起缩。
      await pumpWithSelection(tester, '课程', collapsed: true);
      await tester.pump();
      await tester.pump(HomeSidebar.pillDuration ~/ 2);
      final mid = pillRect(tester).width;
      expect(
        mid,
        lessThan(wide),
        reason: '中途应当已经比展开态窄（实测 $mid vs $wide）',
      );
      expect(
        mid,
        greaterThan(0),
        reason: '不许在中间帧塌成 0',
      );

      await tester.pumpAndSettle();
      expect(
        pillRect(tester).width,
        closeTo(HomeSidebar.collapsedWidth - HomeSidebar.pillInset * 2, 0.5),
        reason: '收起到底 = 栏宽减去左右各一个 pillInset',
      );
    });

    testWidgets('★ 高亮框**只有一个**，且不吃点击（行照旧能点）', (tester) async {
      final taps = <String>[];
      await pumpSidebar(
        tester,
        stubEntries(),
        selectedTitle: '课程',
        onSelect: (e) => taps.add(e.title),
      );
      expect(
        find.byKey(const Key('homeSidebarFlyingPill')),
        findsOneWidget,
        reason: '三十一轮口径 = 侧栏里只有一个会飞的框（不是每行各一个）',
      );
      // 框盖在行上，但必须 `IgnorePointer` —— 否则点到的是框、行收不到事件。
      await tester.tap(find.byKey(const Key('homeSidebarItem-选课')));
      await tester.pump();
      expect(taps, ['选课'], reason: '高亮框不许抢走点击');
    });

    testWidgets('★ 列表滚动时框**跟着行走**（不是钉在原地）', (tester) async {
      // 造一个长到必须滚的列表；选**中段**那一行 —— 滚一点点它还在可视区里
      // （滚出可视区时框会被有意藏起来，那是另一条用例的事）。
      final many = [
        for (var i = 0; i < 40; i++)
          entry('条目$i', HomeServiceGroup.info, accent: const Color(0xFF536DFE)),
      ];
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSidebar(
        tester,
        many,
        selectedTitle: '条目20',
        onSelect: (_) {},
      );
      await tester.pumpAndSettle();

      /// 框与它该在的那一行的相对位置（= 0 表示正正好）。
      double offsetFrom(String title) =>
          pillRect(tester).top -
          tester.getRect(find.byKey(Key('homeSidebarItem-$title'))).top -
          HomeSidebar.pillVerticalInset;

      expect(offsetFrom('条目20'), closeTo(0, 0.5), reason: '起始：框贴在被选中那行上');
      final rowTopBefore = tester
          .getRect(find.byKey(const Key('homeSidebarItem-条目20')))
          .top;

      // 滚下去（幅度小于到可视区底边的距离，保证那一行还在屏幕上）。
      await tester.drag(
        find.byKey(const Key('homeSidebar')),
        const Offset(0, -40),
      );
      await tester.pumpAndSettle();

      final rowTopAfter = tester
          .getRect(find.byKey(const Key('homeSidebarItem-条目20')))
          .top;
      expect(
        rowTopAfter,
        lessThan(rowTopBefore - 10),
        reason: '前提：这一滚真的把那行挪上去了（实测 $rowTopBefore → $rowTopAfter）',
      );
      // ⚠ 真因之一：框画在**栏坐标系**里，行的全局位置随滚动变 —— 不重新量就是
      // "列表在滚、框钉在原地"，看起来完全不对。所以滚完必须仍然贴着那一行。
      expect(
        offsetFrom('条目20'),
        closeTo(0, 0.5),
        reason: '滚过之后框必须仍然贴在被选中那一行上'
            '（实测偏离 ${offsetFrom('条目20')}）',
      );
    });

    testWidgets('★ 滚动时框**逐帧贴合**，不许"慢慢追"', (tester) async {
      // 用户 2026-10-10 三十五轮：「当左侧导航栏滚动时，会导致高亮矩形位置不能随着滚动
      // 立刻相应位置，而是慢慢变到目标位置」。
      //
      // 真因（逐帧实测）：滚动通知是在 **reflow 之前**到的 —— 那一刻"重新量"读到的还是
      // **上一帧**的位置（行已经到 784，量出来仍是 788），于是**恒定落后一个滚动步长**
      // （实测浅色 4px）。修法 = 按 `ScrollPosition` 的增量把框平移
      // （行的 y 与 pixels 严格反向），当帧就对齐。
      //
      // ⚠ 这条守卫**必须**：① 用 `startGesture` + `moveBy` 一小步一小步推
      // （`tester.drag` 会一次走完并带上回弹，中间帧看不到）；
      // ② 每步只 `pump()` **一帧**就量 —— 用 `pumpAndSettle` 的话"慢慢追"也能追平，
      // 守卫就白写了（第一版如此，恒落后 4px 却照样绿）。
      final many = [
        for (var i = 0; i < 60; i++)
          entry('条目$i', HomeServiceGroup.info, accent: const Color(0xFF536DFE)),
      ];
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSidebar(
        tester,
        many,
        selectedTitle: '条目20',
        onSelect: (_) {},
      );
      await tester.pumpAndSettle();

      double lag() =>
          pillRect(tester).top -
          tester.getRect(find.byKey(const Key('homeSidebarItem-条目20'))).top -
          HomeSidebar.pillVerticalInset;

      expect(lag(), closeTo(0, 0.5), reason: '起始就贴合');

      var moved = 0;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('homeSidebar'))),
      );
      for (var step = 0; step < 8; step++) {
        final before = tester
            .getRect(find.byKey(const Key('homeSidebarItem-条目20')))
            .top;
        await gesture.moveBy(const Offset(0, -12));
        await tester.pump(); // 只一帧
        final after = tester
            .getRect(find.byKey(const Key('homeSidebarItem-条目20')))
            .top;
        if ((after - before).abs() < 0.5) continue; // 这一步没真的滚（到边界了）
        moved++;
        expect(
          lag(),
          closeTo(0, 0.5),
          reason: '★ 第 $step 步滚完的**当帧**，框必须还贴在那一行上'
              '（实测落后 ${lag()}；行 $before → $after）——'
              '落后就是"慢慢变到目标位置"那个 bug 复活了',
        );
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(moved, greaterThanOrEqualTo(3), reason: '前提：这几步真的滚动了');
      expect(lag(), closeTo(0, 0.5), reason: '松手（含回弹）之后仍然贴合');
    });
    testWidgets('★ 选中行滚出可视区时，框不许糊到底部固定区上', (tester) async {
      final many = [
        for (var i = 0; i < 40; i++)
          entry('条目$i', HomeServiceGroup.info, accent: const Color(0xFF536DFE)),
      ];
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSidebar(
        tester,
        many,
        selectedTitle: '条目0',
        onSelect: (_) {},
        footer: Column(
          children: [
            HomeSidebarFooterRow(
              key: homeSidebarProfileKey,
              leading: const SizedBox.shrink(),
              label: '我的',
              onTap: () {},
            ),
            HomeSidebarFooterRow(
              key: homeSidebarSettingsKey,
              leading: const SizedBox.shrink(),
              label: '设置',
              onTap: () {},
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final footerTop = tester
          .getRect(find.byKey(homeSidebarProfileKey))
          .top;

      // 把被选中的第一行滚到看不见。
      await tester.drag(
        find.byKey(const Key('homeSidebar')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();

      final pill = find.byKey(const Key('homeSidebarFlyingPill'));
      // 框可以整个藏起来（`SizedBox.shrink()`），但**只要还在画**就不许越界。
      if (pill.evaluate().isNotEmpty) {
        final rect = tester.getRect(pill);
        if (rect.height > 0) {
          expect(
            rect.bottom,
            lessThanOrEqualTo(footerTop + 0.5),
            reason: '★ 框不许画到不滚动的底部固定区上（那里是头像 / 设置两行）',
          );
        }
      }
    });

    testWidgets('★ 飞行是**单调**的：逐帧采样不许往回跳 / 不许跳空', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpWithSelection(tester, '课程');
      await tester.pumpAndSettle();
      final start = pillRect(tester).top;

      // 跨好几个分组（长距离飞行，最容易看出跳变）。
      await pumpWithSelection(tester, '校历');
      await tester.pump();

      final tops = <double>[start];
      // ⚠ **飞一半时再换一次目标** —— 用户报的「位置会闪动」就出在这条路上
      // （目标在半途变了）。只换一次的话这条守卫抓不到任何东西：
      // 实测把起点改回旧写法（`_from = _target`）它照样绿。
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        tops.add(pillRect(tester).top);
        if (i == 2) {
          await pumpWithSelection(tester, '宿舍电费');
        }
      }
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        tops.add(pillRect(tester).top);
      }
      await tester.pumpAndSettle();
      tops.add(pillRect(tester).top);

      // ① 相邻两帧不许"跳空"：位移不许超过全程的一大半（那就是瞬移 / 闪）。
      final span = tops.reduce((a, b) => a > b ? a : b) -
          tops.reduce((a, b) => a < b ? a : b);
      expect(span, greaterThan(40), reason: '用例前提：这一跳确实有距离');
      for (var i = 1; i < tops.length; i++) {
        expect(
          (tops[i] - tops[i - 1]).abs(),
          lessThanOrEqualTo(span * 0.6),
          reason: '★ 第 $i 帧跳空了：${tops[i - 1]} → ${tops[i]}'
              '（整串 $tops）',
        );
      }
      // ② 中途必须出现过"在两端之间"的帧（说明真是一格格挪过去的）。
      final lowest = tops.reduce((a, b) => a < b ? a : b);
      final highest = tops.reduce((a, b) => a > b ? a : b);
      expect(
        tops.any((t) => t > lowest + 1 && t < highest - 1),
        isTrue,
        reason: '★ 中途必须出现过中间位置（整串 $tops）',
      );
    });

    testWidgets('★ 点底部固定区：框会飞过去（不是"啪"地消失）', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Future<void> pumpFooterSelected(bool settingsSelected) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  HomeSidebar(
                    entries: stubEntries(),
                    // 选中底部那两行时 `selectedTitle` 也是 null（概览同样为 null）→
                    // 由 `overviewSelected: false` 把它与概览区分开。
                    selectedTitle: null,
                    footerSelected: true,
                    overviewSelected: false,
                    onSelect: (_) {},
                    onOverview: () {},
                    footer: Column(
                      children: [
                        HomeSidebarFooterRow(
                          key: homeSidebarProfileKey,
                          selected: !settingsSelected,
                          leading: const SizedBox.shrink(),
                          label: '我的',
                          onTap: () {},
                        ),
                        HomeSidebarFooterRow(
                          key: homeSidebarSettingsKey,
                          selected: settingsSelected,
                          leading: const SizedBox.shrink(),
                          label: '设置',
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // 起始：选中目录里的「课程」。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                HomeSidebar(
                  entries: stubEntries(),
                  selectedTitle: '课程',
                  onSelect: (_) {},
                  onOverview: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      final startTop = pillRect(tester).top;

      // 切到「设置」（底部固定区）。
      await pumpFooterSelected(true);
      await tester.pump();

      final tops = <double>[startTop];
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final pill = find.byKey(const Key('homeSidebarFlyingPill'));
        tops.add(pill.evaluate().isEmpty ? double.nan : pillRect(tester).top);
      }

      // ⚠ 用户 2026-10-10：「位置会闪动」。若底部那两行**不参与高亮**，
      // 点它们时 `_measure()` 返回 null → 框直接消失（`SizedBox.shrink()`），
      // 观感就是"啪"地一闪；再点回目录条目又"啪"地出现。
      expect(
        tops.every((t) => !t.isNaN),
        isTrue,
        reason: '★ 点底部固定区时框不该整个消失（那一下就是闪）：$tops',
      );
      expect(
        tops.last,
        greaterThan(startTop),
        reason: '应当飞到底部那一行去（实测 $tops）',
      );
    });

    testWidgets('时长与侧栏其它补间同档（200ms 级，不是几十毫秒的闪）', (tester) async {
      expect(
        HomeSidebar.pillDuration.inMilliseconds,
        greaterThanOrEqualTo(120),
        reason: '太短就等于瞬切',
      );
      expect(
        HomeSidebar.pillDuration.inMilliseconds,
        lessThanOrEqualTo(320),
        reason: '太长会显得粘滞',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 卡片形态（用户 2026-10-09 二轮：「我希望 内容区一个卡片、侧栏一个卡片，然后都是
  // 在设置了可选的。可以都不显示为卡片样式」+「要阴影」）。
  //
  // 形状 / 底色 / 阴影的**取值口径**在 `lib/design/card_frame.dart`（`test/` 里没有
  // 单独的 card_frame 守卫文件，取值断言就落在这里）；这道缝（卡片与窗口边缘之间的
  // 留白）由 `home_screen.dart` 的 `AnimatedPadding` 负责，本文件守侧栏自己那一半。
  // ---------------------------------------------------------------------------
  group('卡片形态', () {
    /// 卡片形态下那一层画形状的 `Container`（`CardFrame` 自己那层）。
    ///
    /// ⚠ 按 `cardFrameContainerKey` 取，**别用** `find.byType(Container)` /
    /// `descendant(of: CardFrame, …)`：`CardFrame` 的子树里不止一个 `Container`
    /// （补间层 + 它自己那层），`widget<Container>()` 会 `Bad state: Too many elements`
    /// （实测踩过）。
    /// ⚠ 两种形态（card true/false）都是**同一个** `Container`，只是 decoration 不同 ——
    /// 这是刻意的（换形态不许重挂子树，见 §44.4）。
    BoxDecoration decorationOf(WidgetTester tester) {
      final container = tester.widget<Container>(
        find.byKey(cardFrameContainerKey),
      );
      return container.decoration! as BoxDecoration;
    }

    Container frameContainerOf(WidgetTester tester) =>
        tester.widget<Container>(find.byKey(cardFrameContainerKey));

    /// 侧栏本体的底色。
    ///
    /// ⚠ 侧栏那层是 `AnimatedContainer`（十二轮起宽度补间），而它**没有 `color`
    /// getter** —— `color:` 传进去之后落在 `decoration`（`BoxDecoration.color`）里。
    Color? sidebarBackgroundOf(WidgetTester tester) {
      final body = tester.widget<AnimatedContainer>(
        find.byKey(const Key('homeSidebar')),
      );
      return (body.decoration as BoxDecoration?)?.color;
    }

    testWidgets('默认（card=false）零包裹：与改造前逐像素一致', (tester) async {
      await pumpSidebar(tester, stubEntries());

      // 底色还是那一档通栏分区色（不是卡片色）。
      final context = tester.element(find.byKey(const Key('homeSidebar')));
      // ⚠ 侧栏本体是 `AnimatedContainer`（十二轮起宽度补间），别按 `Container` 取；
      // 而且 `color` 传进去之后是**藏在 decoration 里**的（没有 `color` getter）。
      expect(
        sidebarBackgroundOf(tester),
        Theme.of(context).colorScheme.surfaceContainerLow,
        reason: '不开卡片时底色不许变（通栏分区色）',
      );
      // 没有圆角 / 描边 / 阴影：decoration 是那个「占位」（圆角 0、无描边无阴影）。
      // ⚠ 不是「整层消失」—— `CardFrame` 现在**两种形态返回同一个组件**
      // （否则换形态会让子树重新挂载，内嵌页的滚动位置会归零，见 §44.4 的新条目）。
      final frame = frameContainerOf(tester);
      final decoration = frame.decoration! as BoxDecoration;
      expect(decoration.border, isNull, reason: '不是卡片时不许有描边');
      expect(decoration.boxShadow, isNull, reason: '不是卡片时不许有阴影');
      expect(
        decoration.borderRadius,
        BorderRadius.circular(0),
        reason: '不是卡片时圆角 0（= 逐像素与改造前一致）',
      );
    });

    testWidgets('card=true：底色换成卡片色（浅色纯白 / 深色 #1A1A1A）', (tester) async {
      await pumpSidebar(tester, stubEntries(), card: true);

      final context = tester.element(find.byKey(const Key('homeSidebar')));
      expect(
        sidebarBackgroundOf(tester),
        appCardColorOf(Theme.of(context).colorScheme),
      );
    });

    testWidgets('card=true：圆角 = kCardFrameRadius、描边 = 卡片描边口径', (tester) async {
      await pumpSidebar(tester, stubEntries(), card: true);

      final context = tester.element(find.byKey(const Key('homeSidebar')));
      final decoration = decorationOf(tester);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(kCardFrameRadius),
      );
      expect(
        (decoration.border! as Border).top.color,
        appCardBorderSide(Theme.of(context).colorScheme).color,
        reason: '区域卡的描边必须与页面内卡片同源（浅色暖灰 / 深色 10% 白）',
      );
    });

    // 用户 2026-10-09 十五轮：「我希望卡片圆角大小也是可控的」。
    testWidgets('★ 圆角跟着 radius 走（0 = 直角档也要真的生效）', (tester) async {
      await pumpSidebar(tester, stubEntries(), card: true, radius: 20);
      expect(
        decorationOf(tester).borderRadius,
        BorderRadius.circular(20),
        reason: '传进去的 radius 必须落到 decoration 上（不许被常量吃掉）',
      );
      // 描边不随圆角变（阴影看开关，见下一条用例）。
      expect(decorationOf(tester).border, isNotNull);
      expect(
        decorationOf(tester).boxShadow,
        isNull,
        reason: '★ 默认**没有**阴影（2026-10-10 三十六轮当面选定）',
      );

      // 显式开阴影：圆角 0 也照样有（阴影不吃圆角）。
      await pumpSidebar(
        tester,
        stubEntries(),
        card: true,
        radius: 0,
        cardShadow: true,
      );
      expect(
        decorationOf(tester).borderRadius,
        BorderRadius.circular(0),
        reason: '0 = 直角（纯色块 + 投影），这是允许的一档',
      );
      expect(
        decorationOf(tester).boxShadow,
        isNotNull,
        reason: '圆角 0 时阴影仍在（阴影不吃圆角）',
      );
    });

    testWidgets('★ 阴影是**可选的**：默认关、显式开才有（用户 2026-10-10 三十六轮）', (
      tester,
    ) async {
      // ① 默认（不传 cardShadow）→ 没有阴影。
      await pumpSidebar(tester, stubEntries(), card: true);
      expect(
        decorationOf(tester).boxShadow,
        isNull,
        reason: '★ 默认没有阴影（当面选定的口径）',
      );
      expect(
        decorationOf(tester).border,
        isNotNull,
        reason: '关阴影**不影响描边**（卡片形态照旧分得出来）',
      );

      // ② 显式开 → 两层，峰值够（口径与从前一致）。
      await pumpSidebar(
        tester,
        stubEntries(),
        card: true,
        cardShadow: true,
      );
      final shadows = decorationOf(tester).boxShadow;
      expect(shadows, isNotNull);
      // 两层（Material elevation 那套规模）：小 blur 勾边 + 大 blur 扩散。
      // ⚠ 单层 vshell 的 `alpha .14 / blur 12` 在 Flutter 里逐像素测不到
      // （见 `card_frame.dart` 里那条实测注释），所以这里连**层数与峰值 alpha** 一起钉住。
      expect(shadows, hasLength(2));
      expect(
        shadows!.map((s) => s.color.a).reduce((a, b) => a > b ? a : b),
        greaterThanOrEqualTo(0.14),
        reason: '峰值强度不够就测不出阴影（实测 0.14 单层在大 blur 下只有 ~0.7%）',
      );
      expect(shadows.map((s) => s.blurRadius), containsAll(<double>[3, 12]));

      // ③ 关掉之后**又没有**了（开关是双向的，不是一次性）。
      await pumpSidebar(tester, stubEntries(), card: true);
      expect(
        decorationOf(tester).boxShadow,
        isNull,
        reason: '★ 关掉之后必须真的没有阴影',
      );
    });

    testWidgets('card=true：内容按圆角裁掉（内嵌页的底色不许盖住圆角）', (tester) async {
      await pumpSidebar(tester, stubEntries(), card: true);

      // ⚠ 断言的是那个 `Container` 的 `clipBehavior`，不是「找一个 ClipRRect」：
      // 圆角裁剪走 decoration 的 `borderRadius`，树里**没有** ClipRRect（实测踩过）。
      final frame = frameContainerOf(tester);
      expect(frame.clipBehavior, Clip.antiAlias);
      expect(
        (frame.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(kCardFrameRadius),
        reason: '裁剪半径必须与框线半径同源，否则内容会在圆角处透出来',
      );
      expect(find.byKey(const Key('homeSidebar')), findsOneWidget);
    });

    testWidgets('宽高契约不变：卡片形态不改侧栏宽度，底部固定区仍贴底边', (tester) async {
      await pumpSidebar(
        tester,
        stubEntries(),
        card: true,
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeSidebarFooterRow(
              key: homeSidebarProfileKey,
              leading: const Icon(Icons.person_outline, size: 18),
              label: '我的',
              onTap: () {},
            ),
            HomeSidebarFooterRow(
              key: homeSidebarSettingsKey,
              leading: const Icon(Icons.settings_outlined, size: 18),
              label: '设置',
              onTap: () {},
            ),
          ],
        ),
      );

      expect(
        tester.getSize(find.byKey(const Key('homeSidebar'))).width,
        homeSidebarWidth,
      );
      expect(
        tester.getBottomLeft(find.byKey(homeSidebarSettingsKey)).dy,
        closeTo(tester.getRect(find.byKey(const Key('homeSidebar'))).bottom, 1),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // 可收起（用户 2026-10-09 七轮：「我希望侧边栏可收起」）。
  // ---------------------------------------------------------------------------
  group('可收起', () {
    testWidgets('未收起时画展开/收起按钮', (tester) async {
      var toggles = 0;
      await pumpSidebar(
        tester,
        stubEntries(),
        onToggleCollapsed: () => toggles++,
      );

      // ⚠ 2026-10-09 起这枚按钮**只在标题栏**（用户：「我希望展开 / 收起侧边栏的按钮
      // 放在标题栏」）—— 侧栏里不再画，入口由 home_screen 的 _publishSidebarToggle`n      // 发布到 WindowTitleBarActions.leading（守卫见 	est/home_sidebar_test.dart`n      // 的源码守卫那组 + 	est/window_title_bar_test.dart）。
      expect(find.byKey(homeSidebarToggleKey), findsNothing,
          reason: '侧栏里不再自带展开 / 收起按钮（已挪到标题栏）');
      expect(toggles, 0, reason: '没有按钮可点');
    });

    testWidgets('收起态：只剩图标 + 胶囊，文本全不画（2026-10-09 十一轮口径）', (tester) async {
      await pumpSidebar(
        tester,
        stubEntries(),
        selectedTitle: '课程',
        collapsed: true,
        onOverview: () {},
        onToggleCollapsed: () {},
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeSidebarFooterRow(
              key: homeSidebarProfileKey,
              leading: const Icon(Icons.person_outline, size: 18),
              label: '我的',
              onTap: () {},
            ),
          ],
        ),
      );

      // 宽度 = 收起档
      expect(
        tester.getSize(find.byKey(const Key('homeSidebar'))).width,
        HomeSidebar.collapsedWidth,
      );
      // 图标 / 行 / 底部固定区**照旧都在**（这是本轮的关键变化）
      // 展开入口同样在标题栏（侧栏里不再画），见上面的说明。
      expect(find.byKey(homeSidebarToggleKey), findsNothing);
      expect(find.byIcon(Icons.abc), findsWidgets, reason: '每行的图标要照画');
      expect(find.byKey(const Key('homeSidebarOverview')), findsOneWidget);
      expect(find.byKey(const Key('homeSidebarItem-课程')), findsOneWidget);
      expect(find.byKey(homeSidebarProfileKey), findsOneWidget, reason: '底部固定区照旧');
      // 文本全不画
      expect(find.text('课程'), findsNothing);
      expect(find.text(homeSidebarOverviewTitle), findsNothing);
      expect(find.text('教务系统'), findsNothing, reason: '分组标题改成一条分隔线');
      expect(find.text('我的'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('收起态下选中胶囊照旧（圆角 / 底色都在，只是窄）', (tester) async {
      await pumpSidebar(
        tester,
        stubEntries(),
        selectedTitle: '课程',
        collapsed: true,
        onToggleCollapsed: () {},
      );
      final decoration = tester
          .widget<DecoratedBox>(find.byKey(const Key('homeSidebarFlyingPill')))
          .decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(HomeSidebar.pillRadius));
      expect(decoration.color?.a ?? 0, greaterThan(0.05), reason: '高亮照旧');
      expect(
        tester.getSize(find.byKey(const Key('homeSidebarItem-课程'))).height,
        HomeSidebar.rowHeight,
      );
    });

    // 用户 2026-10-09 十八轮：「我希望卡片模式的侧边栏收起后仍然是卡片」。
    //
    // 实现侧的重点不在 `HomeSidebar`（它本来就支持 card+collapsed 同时为真），
    // 而在**调用方** `home_screen.dart`：从前传的是 `card: sidebarCard && !collapsed`
    // （收起 = 不算卡片），留下的 `a` 也跟着 `!collapsed` 一起没了 ——
    // 所以这条守卫既测渲染、也钉住那个装配（见上面那组源码守卫）。
    testWidgets('★ 收起 + 卡片：窄轨仍画圆角 / 描边，且左边留 a', (tester) async {
      await pumpSidebar(
        tester,
        stubEntries(),
        collapsed: true,
        card: true,
        radius: 8,
        // ⚠ 阴影现在是**可选**的（2026-10-10 三十六轮，默认关）—— 要验"收起也是卡片、
        // 阴影照样在"就得显式把它打开；不传只说明默认口径是关的（那是另一条用例）。
        cardShadow: true,
        onToggleCollapsed: () {},
      );
      final decoration = tester
          .widget<Container>(find.byKey(cardFrameContainerKey))
          .decoration! as BoxDecoration;
      expect(
        decoration.borderRadius,
        BorderRadius.circular(8),
        reason: '收起后窄轨仍按设置里的圆角画',
      );
      expect(decoration.border, isNotNull, reason: '十八轮：收起也是卡片，描边要在');
      expect(
        decoration.boxShadow,
        isNotNull,
        reason: '十八轮：收起也是卡片；开了阴影时窄轨也要有',
      );
      expect(
        tester.getSize(find.byKey(const Key('homeSidebar'))).width,
        HomeSidebar.collapsedWidth,
        reason: '仍要是那条窄轨（卡片化不改宽度契约）',
      );
    });

    testWidgets('未给 onToggleCollapsed 时不画那枚按钮（旧调用点零改动）', (tester) async {
      await pumpSidebar(tester, stubEntries());
      expect(find.byKey(homeSidebarToggleKey), findsNothing);
    });
    // 用户 2026-10-09 十二轮：「展开收起侧边栏要有动画」。
    testWidgets('★ 收起 / 展开是补间的：中途宽度要在两端之间', (tester) async {
      await pumpSidebar(
        tester,
        stubEntries(),
        collapsed: false,
        onToggleCollapsed: () {},
      );
      double widthNow() =>
          tester.getSize(find.byKey(const Key('homeSidebar'))).width;

      expect(widthNow(), homeSidebarWidth, reason: '起始 = 展开宽');

      // 换成收起态（模拟父级 setState 后重建）。
      await pumpSidebar(
        tester,
        stubEntries(),
        collapsed: true,
        onToggleCollapsed: () {},
      );
      // 补间**起点**：第一帧还应该是展开宽（说明确实在动，而不是瞬变）
      expect(
        widthNow(),
        homeSidebarWidth,
        reason: '第一帧不该已经跳到终点 —— 那就是"没有动画"',
      );
      // 走到一半
      await tester.pump(HomeSidebar.collapseDuration ~/ 2);
      final mid = widthNow();
      expect(
        mid,
        lessThan(homeSidebarWidth),
        reason: '中途必须已经窄于展开宽',
      );
      expect(
        mid,
        greaterThan(HomeSidebar.collapsedWidth),
        reason: '中途必须还没到收起宽（瞬变会直接等于终点）',
      );
      // 走完
      await tester.pump(HomeSidebar.collapseDuration);
      expect(widthNow(), HomeSidebar.collapsedWidth);

      // 再展开：同样要经过中间态
      await pumpSidebar(
        tester,
        stubEntries(),
        collapsed: false,
        onToggleCollapsed: () {},
      );
      await tester.pump(HomeSidebar.collapseDuration ~/ 2);
      final back = widthNow();
      expect(back, greaterThan(HomeSidebar.collapsedWidth));
      expect(back, lessThan(homeSidebarWidth));
      await tester.pump(HomeSidebar.collapseDuration);
      expect(widthNow(), homeSidebarWidth);
      expect(tester.takeException(), isNull);
    });
  });

  // 用户 2026-10-09 十三轮：「我希望侧边栏滚动不显示滚动条」。
  testWidgets('滚动区不套 Scrollbar（滚轮照旧可用）', (tester) async {
    // 造一份足够长的目录（5 条不够撑出滚动区间，`maxScrollExtent` 会是 0）。
    final many = [
      for (var i = 0; i < 12; i++)
        entry('课程$i', HomeServiceGroup.values[i % HomeServiceGroup.values.length]),
    ];
    await pumpSidebar(
      tester,
      many,
      onOverview: () {},
      onSelect: (_) {},
      // 视口压矮一点，保证一定滚得动。
      size: const Size(1200, 500),
    );

    // 桌面端默认 `MaterialScrollBehavior` 会替滚动区套一层 `Scrollbar` ——
    // 侧栏里必须一个都没有。
    expect(
      find.byType(Scrollbar),
      findsNothing,
      reason: '侧栏滚动区不许套 Scrollbar（十三轮口径）',
    );
    final list = find.byType(Scrollable).first;
    expect(
      tester.state<ScrollableState>(list).position.maxScrollExtent,
      greaterThan(0),
      reason: '这个用例的前提是内容可滚（否则下面那条断言恒真）',
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -60));
    await tester.pump();
    expect(
      tester.state<ScrollableState>(list).position.pixels,
      greaterThan(0),
      reason: '不画滚动条不能把滚动本身一起关掉',
    );
    expect(tester.takeException(), isNull);
  });

  group('源码守卫：主页装配（桌面端）', () {
    test('侧栏底部固定区 + 设置/头像在侧栏视图下只在固定区', () {
      final src = File(
        'lib/features/home/presentation/home_screen.dart',
      ).readAsStringSync();
      expect(src, contains('homeSidebarProfileKey'));
      expect(src, contains('homeSidebarSettingsKey'));
      expect(
        src,
        contains('AccountAvatar(radius: 15)'),
        reason: '侧栏底部头像行用紧凑半径',
      );
      // 2026-10-09：首页顶栏整条撤了（品牌与三键都归全局窗口标题栏）——
      // 宫格视图的设置 / 头像改为经「标题栏动作插槽」发布，侧栏视图下**不发布**
      // （那两个入口就在侧栏底部固定区，再挂一遍就重复了）。
      expect(
        src.contains('_buildTopBar'),
        isFalse,
        reason: '首页不再有自己的顶栏（品牌并入 WindowTitleBar）',
      );
      expect(src, contains('_queueTitleBarActions'));
      expect(
        src,
        contains('!useSidebar && (ModalRoute.of(context)?.isCurrent ?? true)'),
        reason: '侧栏视图 / 二级页盖上来时都不往标题栏里塞设置与头像',
      );
    });

    // 卡片形态的装配守卫（用户 2026-10-09 二轮）。判定本身是纯逻辑
    // （`HomeCardStyle` 三件，守卫在 `test/home_layout_test.dart`），
    // 这里只钉「主页真的按判定去装配了」——侧栏 / 内容区各自的用法都在 `home_screen.dart`。
    test('卡片形态：两块各自可开，缝由 AnimatedPadding 留', () {
      final src = File(
        'lib/features/home/presentation/home_screen.dart',
      ).readAsStringSync();
      expect(src, contains("import 'package:smarter_jxufe/design/card_frame.dart'"));
      expect(
        src,
        contains('cardStyle.sidebarIsCard'),
        reason: '侧栏那一块由 HomeCardStyle.sidebarIsCard 决定',
      );
      expect(
        src,
        allOf(contains('HomeSidebar('), contains('card: sidebarCard')),
        reason: '侧栏卡片形态必须经 HomeSidebar.card 传入（别在页面里再包一层）',
      );
      expect(
        src,
        allOf(contains('cardGapMetricsOf('), contains('gap.edge')),
        reason: '间距口径走 domain 的 cardGapMetricsOf（卡片之间 = 距窗口 = a，十七轮起同值）',
      );
      expect(
        src,
        contains('left: sidebarCard ? gap.edge : 0'),
        reason: '侧栏左边：只要是卡片就留 a（**收起也留**，十八轮口径）——'
            '不是卡片却仍缩边就是用户 2026-10-09 七轮要取消的那种「整体边距」',
      );
      expect(
        src,
        contains('card: sidebarCard,'),
        reason: '十八轮：侧栏卡片形态**不再随收没收起变**'
            '（用户：「我希望卡片模式的侧边栏收起后仍然是卡片」）',
      );
      expect(
        src.split('\n').where((l) => !l.trimLeft().startsWith('//')).any(
              (l) => l.contains('card: sidebarCard && !collapsed'),
            ),
        isFalse,
        reason: '旧写法（收起就不算卡片）不许复活',
      );
      expect(
        src,
        contains('sidebarCard && contentCard ? gap.between : 1'),
        reason: '两块之间：只要**两侧都是卡片**就留那道缝（宽度 = a，**收起也留**，'
            '十九轮口径）；否则才是那 1px 的空隙',
      );
      expect(
        src.split('\n').where((l) => !l.trimLeft().startsWith('//')).any(
              (l) => l.contains('sidebarCard && contentCard && !collapsed'),
            ),
        isFalse,
        reason: '旧写法（收起就不留块间缝）不许复活 —— 用户十九轮：'
            '「我希望收起之后与右侧卡片的间距不要变」',
      );
      // 2026-10-09 十三轮（用户：「侧边栏不要有边框线」）：那道 1px 分割线撤掉，
      // 只留空隙。**别再让它回来**——判据要跳过注释行（这条守卫自己的注释里就写着
      // `VerticalDivider` 这个名字，直接 `contains` 会自证自话）。
      expect(
        src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .any((l) => l.contains('VerticalDivider')),
        isFalse,
        reason: '侧栏与内容之间不再画分割线（十三轮口径）',
      );
      expect(
        src,
        allOf(
          // ⚠ 只断言「这一行在」—— 别把换行也写进断言：本仓源码是 **CRLF**，
          // `'…(\n            left:'` 这类永远匹配不上（实测踩过）。
          // 侧栏那层：左 + **下**（二十三轮补的下边 —— 漏了它侧栏卡片就会一路铺到
          // 窗口底、和右边那张内容卡不齐，用户读作「没应用设置里的卡片间距」）。
          contains('left: sidebarCard ? gap.edge : 0,'),
          contains('bottom: sidebarCard ? gap.edge : 0,'),
          // 右 / 底由右栏那层给（二十一轮起它和卡片层一起挪到了 AnimatedSwitcher 外面）。
          contains('right: contentCard ? gap.edge : 0,'),
          contains('bottom: contentCard ? gap.edge : 0,'),
        ),
        reason: '逐边给 padding：侧栏留左+下、右栏留右+下（两张卡的下边同值）',
      );
      expect(
        src,
        allOf(
          contains('CardFrameBackdrop('),
          contains('visible: sidebarCard || contentCard,'),
        ),
        reason: '卡片背后露出来的背景 = 标题栏色（用户 2026-10-09 八轮）',
      );
      // 二十一轮（用户：「点击切换页面，会导致整个右侧内容卡片出现位置的水平闪动」）：
      // **卡片层必须在 `AnimatedSwitcher` 外面**。原来 `CardFrame` 在 switcher 的 child
      // 里面 → 换页时整张卡片跟着 `SlideTransition` 横移、还被 `Stack` 的边界裁掉一截
      // （被裁那侧的描边整段消失 —— 那正是二十轮「圆角处框线断开」的真因）。
      expect(
        src,
        contains('child: _paneSwitcher('),
        reason: '右栏的层级必须是 Padding → CardFrame → _paneSwitcher（框在外、内容在内）',
      );
      expect(
        src.split('\n').where((l) => !l.trimLeft().startsWith('//')).any(
              (l) => l.contains('_paneCard('),
            ),
        isFalse,
        reason: '旧的 `_paneCard`（把 CardFrame 包在 AnimatedSwitcher 里）不许复活',
      );
    });
  });
}