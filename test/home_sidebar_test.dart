import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/card_frame.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';
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
  }) => HomeServiceEntry(
    icon: Icons.abc,
    title: title,
    subtitle: '$title 说明',
    group: group,
    accent: const Color(0xFFC3282E),
    builder: builder ?? () => const SizedBox.shrink(),
    onTap: onTap ?? () {},
    sidebarPinned: sidebarPinned,
  );

  List<HomeServiceEntry> stubEntries({VoidCallback? onTap}) => [
    entry('课程', HomeServiceGroup.ims, onTap: onTap),
    entry('选课', HomeServiceGroup.ims, onTap: onTap),
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
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              HomeSidebar(
                entries: entries,
                card: card,
                radius: radius,
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

  testWidgets('整个侧栏一条分割线都没有（2026-09-17 第 4 条 + 2026-10-09 十三轮）', (tester) async {
    // 用户 2026-09-17 原话：「我希望桌面端主页的侧边导航栏里，顶部"数据一览"和教务系统
    // 之间不要显示分割线」；2026-10-09 十三轮又补一刀：「侧边栏不要有边框线」——
    // **底部固定区上方那条也撤了**，所以现在侧栏里 `Divider` 数量应当是 0。
    await pumpSidebar(
      tester,
      stubEntries(),
      onOverview: () {},
      selectedTitle: null,
      // 给一个真的 footer 行：确认"一条线都没有"不是因为压根没渲染底部固定区。
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
    expect(firstGroupTitle.top, greaterThanOrEqualTo(overview.bottom - 0.5));

    expect(
      find.byType(Divider),
      findsNothing,
      reason: '侧栏里一条分割线都不该有（十三轮把底部固定区上方那条也撤了）',
    );
    // 底部固定区确实在（没有线是取舍，不是没渲染）。
    expect(find.byKey(homeSidebarProfileKey), findsOneWidget);
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

    /// 行内那层「画胶囊」的 Container（外层只是给外边距，没有 decoration）。
    BoxDecoration pillOf(String title) {
      final containers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(Key('homeSidebarItem-$title')),
              matching: find.byType(Container),
            ),
          )
          .toList();
      final decorated = containers.firstWhere((c) => c.decoration != null);
      return decorated.decoration! as BoxDecoration;
    }

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

    // 未选中：没有底色（decoration 为占位或全透明）。
    final plain = pillOf('课程');
    expect(plain.color?.a ?? 0, 0, reason: '未选中不该有底色');
    expect(plain.borderRadius, BorderRadius.circular(HomeSidebar.pillRadius));

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
      // 描边 / 阴影不随圆角变。
      expect(decorationOf(tester).border, isNotNull);
      expect(decorationOf(tester).boxShadow, isNotNull);

      await pumpSidebar(tester, stubEntries(), card: true, radius: 0);
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

    testWidgets('card=true：**有阴影**（用户明确要求「要阴影」）', (tester) async {
      await pumpSidebar(tester, stubEntries(), card: true);

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
          .widget<Container>(
            find
                .descendant(
                  of: find.byKey(const Key('homeSidebarItem-课程')),
                  matching: find.byType(Container),
                )
                .at(1),
          )
          .decoration! as BoxDecoration;
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
    testWidgets('★ 收起 + 卡片：窄轨仍画圆角 / 描边 / 阴影，且左边留 a', (tester) async {
      await pumpSidebar(
        tester,
        stubEntries(),
        collapsed: true,
        card: true,
        radius: 8,
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
      expect(decoration.boxShadow, isNotNull, reason: '十八轮：收起也是卡片，阴影要在');
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
