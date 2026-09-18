import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/shared/widgets/count_stepper.dart';

/// 次数步进器 + 「点击才输入」数字弹窗（用户 2026-09-18 裁定）。
///
/// 原话：「所有输入次数的输入框都要改成直接显示次数，点击向左右的三角形可以增减，
/// 点击数字可以唤起输入」；「民主评议也改成点击才输入」。
void main() {
  group('CountStepper 纯逻辑', () {
    test('clampCount 上下夹取', () {
      expect(CountStepper.clampCount(5), 5);
      expect(CountStepper.clampCount(-3), 0);
      expect(CountStepper.clampCount(120), 99);
      expect(CountStepper.clampCount(-1, min: 2, max: 8), 2);
      expect(CountStepper.clampCount(9, min: 2, max: 8), 8);
    });

    test('三个 Key 都带字段名（同页多个步进器互不冲突）', () {
      expect('${CountStepper.minusKey('缺课节数')}', contains('缺课节数'));
      expect('${CountStepper.plusKey('缺席次数')}', contains('缺席次数'));
      expect('${CountStepper.valueKey('退团次数')}', contains('退团次数'));
      expect(
        CountStepper.minusKey('a') == CountStepper.minusKey('b'),
        isFalse,
      );
    });
  });

  group('CountStepper 交互', () {
    Future<List<int>> pump(
      WidgetTester tester, {
      int value = 3,
      int min = 0,
      int max = 99,
    }) async {
      final changes = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CountStepper(
                label: '缺课节数',
                value: value,
                min: min,
                max: max,
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('左三角减 1、右三角加 1，中间直接显示次数', (tester) async {
      final changes = await pump(tester);
      expect(find.text('3'), findsOneWidget, reason: '直接显示次数，不是输入框');

      await tester.tap(find.byKey(CountStepper.minusKey('缺课节数')));
      await tester.tap(find.byKey(CountStepper.plusKey('缺课节数')));
      expect(changes, [2, 4]);
    });

    testWidgets('到边界时对应三角不可点', (tester) async {
      final changes = await pump(tester, value: 0, min: 0, max: 2);
      final minus = tester.widget<InkWell>(
        find.byKey(CountStepper.minusKey('缺课节数')),
      );
      expect(minus.onTap, isNull, reason: '已到下限 0 → 减号不可点');

      await tester.tap(find.byKey(CountStepper.plusKey('缺课节数')));
      expect(changes, [1]);
    });

    testWidgets('点数字唤起输入框，输入后回传夹取后的值', (tester) async {
      final changes = await pump(tester, max: 10);
      await tester.tap(find.byKey(CountStepper.valueKey('缺课节数')));
      await tester.pumpAndSettle();

      expect(find.text('输入缺课节数'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '7');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(changes, [7]);
    });

    testWidgets('点数字输入越界 → 报错且不关闭', (tester) async {
      final changes = await pump(tester, max: 10);
      await tester.tap(find.byKey(CountStepper.valueKey('缺课节数')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '99');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
      expect(find.text('输入缺课节数'), findsOneWidget, reason: '弹窗不关闭');
    });

    testWidgets('胶囊外观：圆角 999 + 主色淡底 + 主色数字，宽度自适应（不再是 138 宽的方框）', (
      tester,
    ) async {
      // 用户 2026-09-18：「我希望把所有次数型的项，其次数修改组件放到条目右侧，
      // 并改成胶囊」→ 与 `_staticChip` / `_valueTap` 同款。
      final changes = await pump(tester);
      expect(changes, isEmpty);

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(CountStepper),
              matching: find.byType(Container),
            )
            .first,
      );
      final deco = container.decoration! as BoxDecoration;
      expect(deco.borderRadius, BorderRadius.circular(999));
      expect(deco.border, isNull, reason: '不再用 hairline 细描边方框');
      expect(
        tester.widget<Text>(find.text('3')).style!.color,
        Theme.of(tester.element(find.byType(CountStepper))).colorScheme.primary,
        reason: '数字用主色（胶囊口径），不是 onSurface',
      );

      final width = tester.getSize(find.byType(CountStepper)).width;
      expect(width, lessThan(138), reason: '自适应内容：两个三角加一位数不该占满 138');
      expect(width, greaterThan(60), reason: '两个三角 + 数字仍要够点');
    });
  });

  group('promptNumberValue（评议分 / 体测 / 加权共用）', () {
    /// 挂一个按钮把弹窗结果记进 [sink]（`pumpAndSettle` 之后即有值）。
    Future<void> open(
      WidgetTester tester,
      List<NumberPromptOutcome> sink, {
      bool allowClear = false,
      double max = 20,
      double? initial = 12,
      String title = '输入民主评议分',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  sink.add(
                    await promptNumberValue(
                      context,
                      title: title,
                      label: title.replaceFirst('输入', ''),
                      initial: initial,
                      max: max,
                      allowClear: allowClear,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('确定 → confirmed + 数值', (tester) async {
      final sink = <NumberPromptOutcome>[];
      await open(tester, sink);
      expect(find.text('输入民主评议分'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '18.5');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(sink.single.confirmed, isTrue);
      expect(sink.single.cleared, isFalse);
      expect(sink.single.value, 18.5);
    });

    testWidgets('取消 → confirmed 为假（调用方不改动）', (tester) async {
      final sink = <NumberPromptOutcome>[];
      await open(tester, sink);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(sink.single.confirmed, isFalse);
      expect(sink.single.value, isNull);
    });

    testWidgets('allowClear → 「用自动值」返回 cleared', (tester) async {
      final sink = <NumberPromptOutcome>[];
      await open(
        tester,
        sink,
        allowClear: true,
        initial: 91.5,
        max: 100,
        title: '输入加权成绩',
      );
      await tester.tap(find.text('用自动值'));
      await tester.pumpAndSettle();

      expect(sink.single.confirmed, isTrue);
      expect(sink.single.cleared, isTrue);
      expect(sink.single.value, isNull);
    });

    testWidgets('越界 → 报错且不关闭', (tester) async {
      final sink = <NumberPromptOutcome>[];
      await open(tester, sink);
      await tester.enterText(find.byType(TextField), '40');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(sink, isEmpty, reason: '弹窗没关，结果还没回传');
      expect(find.textContaining('范围'), findsWidgets);
      expect(find.text('输入民主评议分'), findsOneWidget);
    });

    testWidgets('留空 → 报错', (tester) async {
      final sink = <NumberPromptOutcome>[];
      await open(tester, sink, initial: null);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(sink, isEmpty);
      expect(find.textContaining('请输入'), findsWidgets);
    });
  });
}
