import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/fluent/fluent.dart';

/// `FluentProgressBar`（2026-10-08 加，毕业学分页用）——
/// 只测**比率到像素的换算与边界**，不碰颜色令牌（那是 `theme_dark_test` 的地盘）。
///
/// 2026-10-08 二轮加 `secondary`（「已选未考」浅色段）：渲染是
/// `[轨道][tailEnd 段][value 段]` 三层叠，所以断言要分清是哪一段。
void main() {
  Future<({double track, double primary, double tail})> measure(
    WidgetTester tester,
    double value, {
    double secondary = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: FluentProgressBar(value: value, secondary: secondary),
            ),
          ),
        ),
      ),
    );
    final track = tester.getSize(find.byType(FluentProgressBar)).width;
    final boxes = find.descendant(
      of: find.byType(FluentProgressBar),
      matching: find.byType(FractionallySizedBox),
    );
    // 顺序 = Stack 里的顺序：[tailEnd, primary]
    final sizes = tester
        .widgetList<FractionallySizedBox>(boxes)
        .map((w) => w.widthFactor!)
        .toList();
    return (
      track: track,
      tail: sizes.first * track,
      primary: sizes.last * track,
    );
  }

  testWidgets('比率画得准（0 / 0.25 / 0.5 / 1）', (tester) async {
    for (final v in [0.0, 0.25, 0.5, 1.0]) {
      final m = await measure(tester, v);
      expect(m.primary, closeTo(m.track * v, 1e-6), reason: 'value=$v');
    }
  });

  testWidgets('★ 越界与 NaN 一律夹到 0~1（不许把 RenderFlex 撑爆）', (tester) async {
    for (final (v, want) in [
      (-3.0, 0.0),
      (7.0, 1.0),
      (double.nan, 0.0),
      (double.infinity, 1.0),
      (double.negativeInfinity, 0.0),
    ]) {
      final m = await measure(tester, v);
      expect(m.primary, closeTo(m.track * want, 1e-6), reason: 'value=$v');
    }
  });

  testWidgets('★ 第二段（在修）从主段右端接着画，且两段合计不越过 100%', (tester) async {
    // 已修 25% + 在修 25% → 主段停在 50px、尾段铺到 100px
    final m = await measure(tester, 0.25, secondary: 0.25);
    expect(m.primary, closeTo(m.track * 0.25, 1e-6));
    expect(m.tail, closeTo(m.track * 0.50, 1e-6));

    // 已修 80% + 在修 80% → 尾段最多铺满，不许溢出
    final over = await measure(tester, 0.8, secondary: 0.8);
    expect(over.primary, closeTo(over.track * 0.8, 1e-6));
    expect(over.tail, closeTo(over.track, 1e-6));

    // 已修已满 → 尾段也只有满格（不会超过轨道）
    final full = await measure(tester, 1.0, secondary: 0.5);
    expect(full.tail, closeTo(full.track, 1e-6));
    expect(full.primary, closeTo(full.track, 1e-6));
  });

  testWidgets('不给 secondary 时尾段与主段重合（旧行为逐像素不变）', (tester) async {
    final m = await measure(tester, 0.42);
    expect(m.tail, closeTo(m.primary, 1e-6));
  });

  testWidgets('高度可配，且无障碍读出百分比', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: FluentProgressBar(value: 0.42, height: 8),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(FluentProgressBar)).height, 8);

    final semantics = tester.getSemantics(find.byType(FluentProgressBar));
    expect(semantics.value, '42%');
  });

  testWidgets('无障碍值把「在修」也读出来', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: FluentProgressBar(value: 0.25, secondary: 0.25),
            ),
          ),
        ),
      ),
    );
    final semantics = tester.getSemantics(find.byType(FluentProgressBar));
    expect(semantics.value, '25%（在修 25%）');
  });
}
