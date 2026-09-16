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
  }) => HomeServiceEntry(
    icon: Icons.abc,
    title: title,
    subtitle: '$title 说明',
    group: group,
    accent: const Color(0xFFC3282E),
    builder: builder ?? () => const SizedBox.shrink(),
    onTap: onTap ?? () {},
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
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
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
              ),
            ],
          ),
        ),
      ),
    );
  }

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
}
