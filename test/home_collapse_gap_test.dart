// 收起侧栏时**间距契约不变**（用户 2026-10-09 十九轮：
// 「我希望收起之后与右侧卡片的间距不要变」）。
//
// 十八轮让收起后仍是卡片（圆角 / 描边 / 阴影都在），十九轮把**块间缝**的判据也从
// 「两块都是卡片**且侧栏没收起**」放宽成「两块都是卡片」—— 于是收起来只是窄轨让开，
// 左缝与块间缝都**不动**。
//
// ⚠ 为什么单开一个文件：这一条必须**按生产装配搭宿主**（要同时量左缝与块间缝），
// 塞进 `home_sidebar_test.dart` 会与那一堆 `pumpSidebar` 的可选参数纠缠；
// 本文件只干这一件事。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/card_frame.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_gap.dart';
import 'package:smarter_jxufe/features/home/presentation/home_sidebar.dart';
import 'package:smarter_jxufe/features/home/presentation/home_service_catalog.dart';

HomeServiceEntry _entry(String t, HomeServiceGroup g, IconData i) =>
    HomeServiceEntry(
      icon: i,
      title: t,
      subtitle: '$t 说明',
      group: g,
      accent: const Color(0xFFC3282E),
      builder: () => const SizedBox.shrink(),
      onTap: () {},
    );

/// 复刻 `home_screen._buildSidebarBody` 的装配（十九轮：缝只看「两块是不是卡片」；
/// 二十三轮：侧栏卡片的下边也要留 `a`，否则两张卡下边不齐）。
Widget _app({required bool collapsed, bool sidebarCard = true}) {
  final gap = cardGapMetricsOf(kCardGapDefault);
  return MaterialApp(
    theme: appDarkTheme,
    home: Scaffold(
      body: CardFrameBackdrop(
        visible: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedPadding(
              duration: CardFrame.duration,
              padding: EdgeInsets.only(
                left: sidebarCard ? gap.edge : 0,
                bottom: sidebarCard ? gap.edge : 0,
              ),
              child: HomeSidebar(
                entries: [
                  _entry('课程', HomeServiceGroup.ims, Icons.menu_book_outlined),
                  _entry('校历', HomeServiceGroup.info, Icons.calendar_month_outlined),
                ],
                card: sidebarCard,
                radius: 8,
                collapsed: collapsed,
                onOverview: () {},
                onSelect: (_) {},
                onToggleCollapsed: () {},
              ),
            ),
            // ↓ 这一道缝就是要量它
            SizedBox(key: const Key('gapUnderTest'), width: gap.between),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 8, bottom: 8),
                child: CardFrame(
                  card: true,
                  radius: 8,
                  child: ColoredBox(color: Color(0xFF1A1A1A)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('★ 收起与展开：块间缝与左缝都不变', (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(collapsed: false));
    await tester.pumpAndSettle();
    final expandedGap = tester
        .getSize(find.byKey(const Key('gapUnderTest')))
        .width;
    final expandedLeft = tester
        .getTopLeft(find.byKey(const Key('homeSidebar')))
        .dx;
    final expandedPaneLeft = tester.getTopLeft(find.byType(CardFrame).last).dx;

    await tester.pumpWidget(_app(collapsed: true));
    await tester.pumpAndSettle();
    final collapsedGap = tester
        .getSize(find.byKey(const Key('gapUnderTest')))
        .width;
    final collapsedLeft = tester
        .getTopLeft(find.byKey(const Key('homeSidebar')))
        .dx;
    final collapsedPaneLeft = tester.getTopLeft(find.byType(CardFrame).last).dx;

    // 实测（`a` = 8，900×620 宿主）：展开 gap=8 / leftInset=8+1 / paneLeft=250；
    // 收起 gap=8 / leftInset 不变 / paneLeft=58 —— 只有右栏让开。
    expect(
      collapsedGap,
      expandedGap,
      reason: '十九轮：收起之后与右侧卡片的间距不许变'
          '（实测展开 $expandedGap / 收起 $collapsedGap）',
    );
    expect(
      collapsedLeft,
      expandedLeft,
      reason: '左边那道 a 也不许变（实测展开 $expandedLeft / 收起 $collapsedLeft）',
    );
    expect(
      collapsedPaneLeft,
      lessThan(expandedPaneLeft),
      reason: '窄轨变窄，右栏应当整体左移（这正是"让开"的表现）',
    );
    expect(tester.takeException(), isNull);
  });

  // 用户 2026-10-09 二十三轮：「侧边栏以卡片形式显示时，距离页面底部太近，似乎没有
  // 应用设置里的卡片间距设置」—— 从前侧栏那层 `AnimatedPadding` 只有 `left`，
  // 于是侧栏卡片铺到窗口底、和右边那张内容卡**下边不齐**。
  testWidgets('★ 侧栏卡片的下边 = 内容卡的下边 = a', (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(collapsed: false));
    await tester.pumpAndSettle();

    const h = 620.0;
    final a = cardGapMetricsOf(kCardGapDefault).edge;
    // 量的是**两张卡片外框**的下边（不是里面那个 body —— 卡片自己的裁剪会给 body
    // 留 1px 内缩，见下面的容差说明）。
    final sidebarCard = tester.getRect(find.byType(CardFrame).first);
    final paneCard = tester.getRect(find.byType(CardFrame).last);

    expect(
      sidebarCard.bottom,
      closeTo(h - a, 1),
      reason: '侧栏卡片下边距窗口底 = a（实测 ${h - sidebarCard.bottom}，'
          '其中 1px 是卡片自己那道 1px 描边占的）',
    );
    expect(
      paneCard.bottom,
      closeTo(sidebarCard.bottom, 1),
      reason: '左右两张卡的下边必须**齐平**（各自距底 ${h - sidebarCard.bottom} / '
          '${h - paneCard.bottom}）—— 这正是用户二十三轮报的那条',
    );
    expect(
      a,
      kCardGapDefault,
      reason: 'a 就是设置里那个值 —— 它变了这两条断言跟着变，不是写死的 8',
    );
    expect(
      sidebarCard.top,
      0,
      reason: '顶边仍贴标题栏（顶边不受 a 限制，是六轮/七轮的口径）',
    );
  });

  testWidgets('侧栏不是卡片时不缩下边（通栏铺到窗口底）', (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(collapsed: false, sidebarCard: false));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byKey(const Key('homeSidebar'))).dy,
      620,
      reason: '不是卡片却缩边 = 用户七轮要取消的那种「整体边距」',
    );
  });
}
