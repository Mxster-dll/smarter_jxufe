/// 规则悬浮提示（`RuleTip`）的**位置**守卫。
///
/// 用户 2026-09-17 原话：「综测页的悬浮提示位置不对，我希望显示在悬浮按钮周围，
/// 并且不能超出屏幕外」——旧实现按 `maxHeight`（最多 400）估卡片高度来定位，
/// 翻到上方时卡片被推到离按钮很远处。现改为 `CustomSingleChildLayout` 的 delegate
/// 用**卡片真实尺寸**定位：下方放得下就紧贴下沿，放不下翻到上沿，横向夹在屏幕内。
///
/// 两条实测教训写在这里，免得下次再踩：
/// 1. **必须真改窗口尺寸**（`tester.view.physicalSize`）。只往树里塞一个
///    `MediaQuery(data: MediaQueryData(size: …))` 不改变 Overlay 的实际大小 ——
///    delegate 拿到的 `size` 仍是默认 800×600，断言会得出「越界」的假结论。
/// 2. **不要用 `tester.drag` 滚动**：浮层卡片就在列表上方（Overlay 命中测试优先），
///    拖拽落在卡片上 → 列表根本没滚。改用 `ScrollPosition.jumpTo`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_tip_data.dart';
import 'package:smarter_jxufe/features/zongce/presentation/widgets/rule_tip.dart';

/// 卡片与按钮之间的间距（与实现里的 `_tipGap` 同值）。
const double _gap = 6;

/// 与屏幕边缘的最小留白（与实现里的 `_tipMargin` 同值）。
const double _margin = 8;

void main() {
  final tipIds = [zcTipBlocks.keys.first];

  Future<void> pumpApp(
    WidgetTester tester, {
    required Size size,
    required Widget body,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pumpAndSettle();
  }

  Widget at({required double left, required double top}) => Stack(
    children: [
      Positioned(left: left, top: top, child: RuleTip(ids: tipIds, size: 18)),
    ],
  );

  Future<void> showTip(WidgetTester tester) async {
    await tester.tap(find.byType(RuleTip));
    await tester.pumpAndSettle();
    expect(find.byKey(ruleTipCardKey), findsOneWidget, reason: '点一下应弹出浮层');
  }

  Rect cardRect(WidgetTester tester) =>
      tester.getRect(find.byKey(ruleTipCardKey));

  Rect anchorRect(WidgetTester tester) => tester.getRect(find.byType(RuleTip));

  void expectInsideScreen(WidgetTester tester, Rect card, Size size) {
    expect(card.left, greaterThanOrEqualTo(_margin - 0.5), reason: '左不越界');
    expect(
      card.right,
      lessThanOrEqualTo(size.width - _margin + 0.5),
      reason: '右不越界',
    );
    expect(card.top, greaterThanOrEqualTo(_margin - 0.5), reason: '上不越界');
    expect(
      card.bottom,
      lessThanOrEqualTo(size.height - _margin + 0.5),
      reason: '下不越界',
    );
  }

  testWidgets('按钮上方有空间：卡片紧贴按钮下方、不出屏', (tester) async {
    const size = Size(800, 600);
    await pumpApp(tester, size: size, body: at(left: 380, top: 80));
    await showTip(tester);

    final card = cardRect(tester);
    final anchor = anchorRect(tester);
    expect(
      card.top - anchor.bottom,
      closeTo(_gap, 1),
      reason: '下方放得下 → 贴着按钮下沿（旧实现按 maxHeight 估高会离得很远）',
    );
    expectInsideScreen(tester, card, size);
  });

  testWidgets('按钮贴近屏幕底部：卡片翻到按钮上方且仍紧贴', (tester) async {
    const size = Size(800, 600);
    await pumpApp(tester, size: size, body: at(left: 380, top: 566));
    await showTip(tester);

    final card = cardRect(tester);
    final anchor = anchorRect(tester);
    expect(card.bottom, lessThanOrEqualTo(anchor.top));
    expect(
      anchor.top - card.bottom,
      closeTo(_gap, 1),
      reason: '翻到上方时也要贴着按钮上沿',
    );
    expectInsideScreen(tester, card, size);
  });

  testWidgets('按钮靠右：卡片横向夹在屏幕内', (tester) async {
    const size = Size(800, 600);
    await pumpApp(tester, size: size, body: at(left: 774, top: 200));
    await showTip(tester);

    final card = cardRect(tester);
    expect(card.right, lessThanOrEqualTo(size.width - _margin + 0.5));
    expect(card.left, greaterThanOrEqualTo(_margin - 0.5));
    expectInsideScreen(tester, card, size);
  });

  testWidgets('窗口很矮：卡片既不越界也不被裁掉', (tester) async {
    const size = Size(760, 220);
    await pumpApp(tester, size: size, body: at(left: 360, top: 100));
    await showTip(tester);

    expectInsideScreen(tester, cardRect(tester), size);
    expect(tester.takeException(), isNull);
  });

  testWidgets('上下都放不下时：卡片收缩，绝不遮盖悬停处（用户 2026-09-18 裁定）', (tester) async {
    // 旧实现把卡片高度 clamp 到 120~460，矮窗口下靠
    // `(size.height - margin - child.height).clamp(margin, belowTop)` 兜底，
    // 那一夹就把卡片夹到了按钮上（实测 220 高窗口里卡片 [42,212] 压住按钮 [100,118]）。
    const size = Size(760, 220);
    await pumpApp(tester, size: size, body: at(left: 360, top: 100));
    await showTip(tester);

    final card = cardRect(tester);
    final anchor = anchorRect(tester);
    expect(
      card.overlaps(anchor.inflate(4)),
      isFalse,
      reason: '卡片与「悬停目标安全区」不许相交：card=$card anchor=$anchor',
    );
    expectInsideScreen(tester, card, size);
    expect(tester.takeException(), isNull);
  });

  testWidgets('中部按钮：卡片贴下沿且不压按钮', (tester) async {
    const size = Size(800, 600);
    await pumpApp(tester, size: size, body: at(left: 380, top: 300));
    await showTip(tester);

    final card = cardRect(tester);
    final anchor = anchorRect(tester);
    expect(card.overlaps(anchor.inflate(4)), isFalse);
    // 下方（300 起算，屏高 600）放得下 → 贴下沿。
    expect(card.top - anchor.bottom, closeTo(_gap, 1));
  });

  testWidgets('滚动时浮层跟着按钮走（间距恒定）', (tester) async {
    await pumpApp(
      tester,
      size: const Size(800, 600),
      body: ListView(
        children: [
          const SizedBox(height: 60),
          const Padding(
            padding: EdgeInsets.only(left: 380),
            child: RuleTip(ids: ['r22'], size: 18),
          ),
          const SizedBox(height: 1600),
        ],
      ),
    );
    await showTip(tester);

    final before = cardRect(tester);
    final anchorBefore = anchorRect(tester);
    expect(before.top - anchorBefore.bottom, closeTo(_gap, 1));

    // 程序化滚动 40（不用 drag：浮层卡片会挡住手势）。
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(40);
    await tester.pumpAndSettle();

    final after = cardRect(tester);
    final anchorAfter = anchorRect(tester);
    expect(
      anchorAfter.top,
      closeTo(anchorBefore.top - 40, 1.5),
      reason: '列表确实滚动了 40',
    );
    expect(
      after.top - anchorAfter.bottom,
      closeTo(_gap, 1.5),
      reason: '滚动后浮层仍紧贴按钮（不再停在旧位置）',
    );
  });

  testWidgets('再点一下收起，浮层移除', (tester) async {
    await pumpApp(
      tester,
      size: const Size(800, 600),
      body: at(left: 380, top: 80),
    );
    await showTip(tester);
    await tester.tap(find.byType(RuleTip));
    await tester.pumpAndSettle();
    expect(find.byKey(ruleTipCardKey), findsNothing);
  });
}
