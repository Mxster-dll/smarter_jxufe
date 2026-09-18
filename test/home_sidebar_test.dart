import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Future<void> pumpSidebar(
    WidgetTester tester,
    List<HomeServiceEntry> entries, {
    String? selectedTitle,
    ValueChanged<HomeServiceEntry>? onSelect,
    VoidCallback? onOverview,
    Widget? footer,
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

  testWidgets('「数据一览」与「教务系统」之间不画分割线（用户 2026-09-17 第 4 条）', (tester) async {
    // 用户原话：「我希望桌面端主页的侧边导航栏里，顶部"数据一览"和教务系统之间
    // 不要显示分割线」。断言方式 = 量两者的竖直区间，**中间不许夹任何 Divider**。
    await pumpSidebar(
      tester,
      stubEntries(),
      onOverview: () {},
      selectedTitle: null,
      // 传一个 footer → 侧栏里确实存在一条线（底部固定区上方那条），
      // 这样「中间没有线」的断言才有意义（不是因为没有线才通过）。
      footer: const SizedBox(height: HomeSidebar.footerRowHeight),
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

    // 侧栏里唯一的线是底部固定区上方那条，且它必须在**最后一个分组之下**。
    final dividers = find.byType(Divider);
    expect(dividers, findsOneWidget, reason: '除了底部固定区上方，不该有第二条分割线');
    final dividerRect = tester.getRect(dividers);
    expect(
      dividerRect.top,
      greaterThan(firstGroupTitle.top),
      reason: '「数据一览」与「教务系统」之间出现了分割线（${dividerRect.top}）',
    );
    final lastGroupTitle = tester.getRect(
      find.text(HomeServiceGroup.values.last.title),
    );
    expect(
      dividerRect.top,
      greaterThanOrEqualTo(lastGroupTitle.bottom - 0.5),
      reason: '分组之间不该有分割线',
    );
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
      for (final g in HomeServiceGroup.values)
        tester.getTopLeft(find.text(g.title)).dy,
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

  testWidgets('选中行高亮（左边条 + 加粗），未选中行不画条', (tester) async {
    await pumpSidebar(
      tester,
      stubEntries(),
      selectedTitle: '分数估计',
      onSelect: (_) {},
    );

    BorderSide leftBorderOf(String title) {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(Key('homeSidebarItem-$title')),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      return (decoration.border! as Border).left;
    }

    expect(leftBorderOf('分数估计').width, HomeSidebar.indicatorWidth);
    expect(leftBorderOf('分数估计').color.a, greaterThan(0.9));
    expect(leftBorderOf('课程').color.a, 0, reason: '未选中 → 透明占位条');

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

  group('源码守卫：主页装配（桌面端）', () {
    test('侧栏底部固定区 + 顶栏在侧栏视图下只留品牌', () {
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
      expect(
        src,
        contains('showAccountActions: !useSidebar'),
        reason: '侧栏视图下顶栏不再放设置/头像（它们搬到了侧栏底部）',
      );
    });
  });
}
