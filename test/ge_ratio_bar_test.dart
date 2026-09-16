/// 分数估计 · 构成占比条（分段切分 + 45°/135° 引出线布局 + 点击设置）守卫测试。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_models.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_ratio_bar.dart';

GePart _part(String name, double cap, {int i = 0}) =>
    GePart(id: 'p$i', name: name, cap: cap);

void main() {
  group('geRatioSegments 分段', () {
    test('平时按各分项分值上限切分，期末占剩余（合计 100%）', () {
      final segs = geRatioSegments(
        parts: [_part('考勤', 5), _part('作业', 15), _part('表现', 10)],
        dailyPercent: 30,
      );
      expect(segs.length, 4);
      expect(segs.map((s) => s.label).toList(), [
        '考勤 5',
        '作业 15',
        '表现 10',
        '期末 70%',
      ]);
      expect(segs[0].fraction, closeTo(0.05, 1e-9)); // 30% × 5/30
      expect(segs[1].fraction, closeTo(0.15, 1e-9));
      expect(segs[2].fraction, closeTo(0.10, 1e-9));
      expect(segs[3].fraction, closeTo(0.70, 1e-9));
      expect(segs[3].kind, GeRatioSegmentKind.finalScore);
      expect(segs.take(3).every((s) => s.isPart), isTrue);
      expect(segs.fold<double>(0, (a, s) => a + s.fraction), closeTo(1, 1e-9));
    });

    test('分项下标按原列表保留（跳过 0 分值的分项）', () {
      final segs = geRatioSegments(
        parts: [_part('考勤', 5), _part('待定', 0), _part('作业', 15)],
        dailyPercent: 40,
      );
      expect(segs.map((s) => s.partIndex).toList(), [0, 2, -1]);
      expect(segs[0].fraction, closeTo(0.1, 1e-9)); // 40% × 5/20
      expect(segs[1].fraction, closeTo(0.3, 1e-9));
      expect(segs[2].fraction, closeTo(0.6, 1e-9));
    });

    test('平时占比为 0 → 只有期末段', () {
      final segs = geRatioSegments(parts: [_part('考勤', 5)], dailyPercent: 0);
      expect(segs.length, 1);
      expect(segs.single.label, '期末 100%');
      expect(segs.single.fraction, 1);
    });

    test('平时占比 100 → 只有平时各段', () {
      final segs = geRatioSegments(
        parts: [_part('考勤', 1), _part('作业', 3)],
        dailyPercent: 100,
      );
      expect(segs.length, 2);
      expect(segs[0].fraction, closeTo(0.25, 1e-9));
      expect(segs[1].fraction, closeTo(0.75, 1e-9));
      expect(segs.any((s) => !s.isPart), isFalse);
      expect(segs.fold<double>(0, (a, s) => a + s.fraction), closeTo(1, 1e-9));
    });

    test('平时占比 > 0 但未配置分项 → 一整段「待配置」', () {
      final segs = geRatioSegments(parts: const [], dailyPercent: 30);
      expect(segs.length, 2);
      expect(segs[0].pending, isTrue);
      expect(segs[0].label, contains('待配置'));
      expect(segs[0].fraction, closeTo(0.3, 1e-9));
      expect(segs[1].label, '期末 70%');
    });

    test('分项分值全为 0（或非法）→ 同样退化为「待配置」', () {
      final segs = geRatioSegments(
        parts: [_part('考勤', 0), _part('作业', -3)],
        dailyPercent: 50,
      );
      expect(segs.length, 2);
      expect(segs[0].pending, isTrue);
      expect(segs.fold<double>(0, (a, s) => a + s.fraction), closeTo(1, 1e-9));
    });

    test('分项名为空 → 回退「分项 N」；占比越界被夹紧', () {
      final segs = geRatioSegments(parts: [_part('  ', 5)], dailyPercent: 150);
      expect(segs.single.label, '分项 1 5');
      expect(segs.single.fraction, 1); // 平时被夹到 100% → 无期末段
    });

    test('占比为 NaN → 回退默认 30%', () {
      final segs = geRatioSegments(parts: const [], dailyPercent: double.nan);
      expect(segs[0].fraction, closeTo(0.3, 1e-9));
      expect(segs[1].label, '期末 70%');
    });
  });

  group('geCalloutLayout 引出线', () {
    List<GeCallout> layout({
      required int partCount,
      double dailyPercent = 30,
      double width = 360,
      double barBottom = geRatioBarHeight,
    }) {
      final parts = [
        for (var i = 0; i < partCount; i++) _part('分项${i + 1}', 10, i: i),
      ];
      final segs = geRatioSegments(parts: parts, dailyPercent: dailyPercent);
      return geCalloutLayout(
        segments: segs,
        labelWidths: [for (final s in segs) 52.0 + s.label.length * 2],
        width: width,
        barBottom: barBottom,
      );
    }

    test('斜线严格 45°/135°（竖直位移 = 水平位移）', () {
      for (final n in [1, 2, 3, 5, 8]) {
        for (final c in layout(partCount: n)) {
          expect(
            (c.run - c.drop).abs(),
            lessThan(1e-6),
            reason: '${c.segment.label} 的斜线不是 45°：run=${c.run} drop=${c.drop}',
          );
        }
      }
    });

    test('起点恒为各段中心', () {
      const width = 400.0;
      final callouts = layout(partCount: 4, width: width);
      expect(callouts.length, 5); // 4 分项 + 期末
      var cursor = 0.0;
      for (final c in callouts) {
        final segWidth = width * c.segment.fraction;
        expect(c.anchorX, closeTo(cursor + segWidth / 2, 1e-6));
        cursor += segWidth;
      }
      expect(cursor, closeTo(width, 1e-6));
    });

    test('标注不重叠且不出界（常见分项数）', () {
      for (final n in [1, 2, 3, 4, 5]) {
        for (final w in [320.0, 360.0, 520.0]) {
          final callouts = layout(partCount: n, width: w);
          for (final c in callouts) {
            expect(c.labelLeft, greaterThanOrEqualTo(-0.5));
            expect(c.labelRight, lessThanOrEqualTo(w + 0.5));
          }
          for (var i = 0; i < callouts.length; i++) {
            for (var j = i + 1; j < callouts.length; j++) {
              expect(
                callouts[i].rect.overlaps(callouts[j].rect),
                isFalse,
                reason:
                    'n=$n w=$w：${callouts[i].segment.label} 与 '
                    '${callouts[j].segment.label} 重叠',
              );
            }
          }
        }
      }
    });

    test('方向按相对位置择向：左半段先右下，右半段先左下', () {
      final callouts = layout(partCount: 1, width: 400);
      // 平时 30%（左半）→ 右下 45°；期末段中心在右半 → 左下 135°。
      expect(callouts[0].direction, 1);
      expect(callouts[1].direction, -1);
    });

    test('标注宽度超过条宽时仍不出界', () {
      final segs = geRatioSegments(parts: [_part('考勤', 1)], dailyPercent: 10);
      final callouts = geCalloutLayout(
        segments: segs,
        labelWidths: [400, 400],
        width: 120,
        barBottom: geRatioBarHeight,
      );
      for (final c in callouts) {
        expect(c.labelLeft, greaterThanOrEqualTo(-0.5));
        expect(c.labelRight, lessThanOrEqualTo(120.5));
        expect((c.run - c.drop).abs(), lessThan(1e-6));
      }
    });

    test('同一输入两次布局完全一致（无隐藏随机性）', () {
      final a = layout(partCount: 5);
      final b = layout(partCount: 5);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].labelLeft, b[i].labelLeft);
        expect(a[i].labelTop, b[i].labelTop);
        expect(a[i].direction, b[i].direction);
        expect(a[i].level, b[i].level);
      }
    });

    test('极端分项数：仍满足 45° 与不出界（允许标注挤在一起）', () {
      final callouts = layout(partCount: 12, width: 320);
      expect(callouts.length, 13);
      for (final c in callouts) {
        expect((c.run - c.drop).abs(), lessThan(1e-6));
        expect(c.labelLeft, greaterThanOrEqualTo(-0.5));
        expect(c.labelRight, lessThanOrEqualTo(320.5));
      }
    });
  });

  group('GeRatioChart 交互', () {
    testWidgets('渲染分段条与全部标注，点击整块触发比例设置', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: GeRatioChart(
                  parts: [_part('考勤', 5), _part('作业', 25)],
                  dailyPercent: 40,
                  onTap: () => taps++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('考勤 5'), findsOneWidget);
      expect(find.text('作业 25'), findsOneWidget);
      expect(find.text('期末 60%'), findsOneWidget);
      // 平时 40% = 考勤 5 + 作业 25 → 6.67% / 33.33%
      expect(find.byType(GeRatioBar), findsOneWidget);

      await tester.tap(find.byType(GeRatioChart));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('未配置分项时显示「待配置」段', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: GeRatioChart(parts: [], dailyPercent: 30),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('待配置'), findsOneWidget);
      expect(find.text('期末 70%'), findsOneWidget);
    });

    testWidgets('分段真的画出来（有高度、宽度按占比、两色分明）', (tester) async {
      // 回归守卫：Row 若用默认 crossAxisAlignment，无子 ColoredBox 的高度会塌成 0
      // → 整条隐形（旧版 8px 双色条就是这个写法，从未画出来过）。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: GeRatioBar(
                  parts: [
                    _part('考勤', 5),
                    _part('作业', 15),
                    _part('平时表现', 10),
                  ],
                  dailyPercent: 30,
                ),
              ),
            ),
          ),
        ),
      );
      final finder = find.descendant(
        of: find.byType(GeRatioBar),
        matching: find.byType(ColoredBox),
      );
      final boxes = tester.widgetList<ColoredBox>(finder).toList();
      expect(boxes.length, 4); // 3 分项 + 期末
      final sizes = [
        for (var i = 0; i < boxes.length; i++) tester.getSize(finder.at(i)),
      ];
      for (final s in sizes) {
        expect(s.height, geRatioBarHeight);
      }
      // 条宽 360、3 处 2px 断口 → 可分配 354；flex = 5/15/10/70（万分比）。
      expect(sizes[0].width, closeTo(354 * 0.05, 0.6));
      expect(sizes[1].width, closeTo(354 * 0.15, 0.6));
      expect(sizes[2].width, closeTo(354 * 0.10, 0.6));
      expect(sizes[3].width, closeTo(354 * 0.70, 0.6));
      expect(boxes.map((b) => b.color).toList(), [
        FeaturePalette.scoreEstimate,
        FeaturePalette.scoreEstimate,
        FeaturePalette.scoreEstimate,
        FeaturePalette.scoreEstimateFinal,
      ]);
    });

    testWidgets('点条打开弹层：滑动条即时生效，快捷比例可点选', (tester) async {
      final applied = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 360,
                  child: GeRatioChart(
                    parts: [_part('考勤', 5), _part('作业', 15)],
                    dailyPercent: 30,
                    onTap: () => showGeRatioSheet(
                      context,
                      parts: [_part('考勤', 5), _part('作业', 15)],
                      dailyPercent: 30,
                      onChanged: applied.add,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GeRatioChart));
      await tester.pumpAndSettle();
      expect(find.text('平时 / 期末占比'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);

      // 快捷比例：40 / 60。
      await tester.tap(find.text('40 / 60'));
      await tester.pump();
      expect(applied.last, 40);
      expect(find.text('总评 = 平时均分 × 40% + 期末 × 60%'), findsOneWidget);

      // 手输 55。
      await tester.enterText(find.byType(TextField), '55');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(applied.last, 55);

      // 完成后关闭弹层。
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('平时 / 期末占比'), findsNothing);
    });
  });
}
