/// 通用三宫格日期选择器（`lib/shared/widgets/grid_date_picker.dart`）守卫。
///
/// 用户 2026-09-17 定制：「点击后显示三个浮窗，第一个选择年份，第二个选择
/// 月份，第三个选择日期，都以宫格显示」——形态经 ask 确认为**一个弹窗里三块
/// 宫格**（宽屏三列并排 / 窄屏纵向堆叠）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/shared/widgets/grid_date_picker.dart';

Widget _harness(
  DateTime? initial,
  DateTime first,
  DateTime last,
  void Function(DateTime?) onResult, {
  String title = '选择日期',
  String? helpText,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final r = await showGridDatePicker(
                context,
                initialDate: initial,
                firstDate: first,
                lastDate: last,
                title: title,
                helpText: helpText,
              );
              onResult(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('纯逻辑', () {
    test('每月天数（含闰年规则）', () {
      expect(gridDaysInMonth(2026, 1), 31);
      expect(gridDaysInMonth(2026, 2), 28);
      expect(gridDaysInMonth(2024, 2), 29);
      expect(gridDaysInMonth(2100, 2), 28);
      expect(gridDaysInMonth(2000, 2), 29);
      expect(gridDaysInMonth(2026, 4), 30);
      expect(gridDaysInMonth(2026, 12), 31);
    });

    test('日期夹取到区间内', () {
      final first = DateTime(2026, 3, 10);
      final last = DateTime(2026, 5, 20);
      expect(
        gridClampDate(DateTime(2020, 1, 1), first, last),
        DateTime(2026, 3, 10),
      );
      expect(
        gridClampDate(DateTime(2030, 1, 1), first, last),
        DateTime(2026, 5, 20),
      );
      expect(
        gridClampDate(DateTime(2026, 4, 7, 15, 30), first, last),
        DateTime(2026, 4, 7),
      );
    });
  });

  group('渲染', () {
    testWidgets('弹出后同时给出年 / 月 / 日三块宫格', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(
          DateTime(2026, 9, 17),
          DateTime(2024, 1, 1),
          DateTime(2026, 12, 31),
          (_) {},
          title: '选择盖章日期',
          helpText: '证书盖章时间',
        ),
      );
      await _open(tester);

      expect(find.byKey(gridDatePickerKey), findsOneWidget);
      expect(find.text('年份'), findsOneWidget);
      expect(find.text('月份'), findsOneWidget);
      expect(find.text('日期'), findsOneWidget);
      expect(find.text('选择盖章日期'), findsOneWidget);
      expect(find.textContaining('已选 2026-09-17'), findsOneWidget);
      // 年份宫格 = 区间内逐年；月份 12 格；9 月 30 天。
      for (final y in const [2024, 2025, 2026]) {
        expect(find.byKey(gridDateYearKey(y)), findsOneWidget);
      }
      expect(find.byKey(gridDateYearKey(2023)), findsNothing);
      expect(find.byKey(gridDateMonthKey(12)), findsOneWidget);
      expect(find.byKey(gridDateDayKey(30)), findsOneWidget);
      expect(find.byKey(gridDateDayKey(31)), findsNothing, reason: '9 月只有 30 天');
    });

    testWidgets('宽屏三块并排：年 / 月 / 日 顶边同行', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(null, DateTime(2024, 1, 1), DateTime(2026, 12, 31), (_) {}),
      );
      await _open(tester);
      final year = tester.getTopLeft(find.text('年份')).dy;
      final month = tester.getTopLeft(find.text('月份')).dy;
      final day = tester.getTopLeft(find.text('日期')).dy;
      expect(month, closeTo(year, 0.5));
      expect(day, closeTo(year, 0.5));
    });

    testWidgets('窄屏纵向堆叠：三块顶边递增', (tester) async {
      tester.view.physicalSize = const Size(420, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(null, DateTime(2024, 1, 1), DateTime(2026, 12, 31), (_) {}),
      );
      await _open(tester);
      final year = tester.getTopLeft(find.text('年份')).dy;
      final month = tester.getTopLeft(find.text('月份')).dy;
      final day = tester.getTopLeft(find.text('日期')).dy;
      expect(month, greaterThan(year));
      expect(day, greaterThan(month));
    });
  });

  group('交互', () {
    testWidgets('选年 → 选月 → 点日即完成并回传日期', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final results = <DateTime?>[];
      await tester.pumpWidget(
        _harness(
          DateTime(2026, 9, 17),
          DateTime(2024, 1, 1),
          DateTime(2026, 12, 31),
          results.add,
        ),
      );
      await _open(tester);

      await tester.tap(find.byKey(gridDateYearKey(2025)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(gridDateMonthKey(3)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(gridDateDayKey(7)));
      await tester.pumpAndSettle();

      expect(results, [DateTime(2025, 3, 7)]);
      expect(find.byKey(gridDatePickerKey), findsNothing, reason: '点日即关闭');
    });

    testWidgets('切到 2 月后日期格收敛到 28 天（闰年 29）', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final results = <DateTime?>[];
      await tester.pumpWidget(
        _harness(
          DateTime(2026, 1, 31),
          DateTime(2024, 1, 1),
          DateTime(2026, 12, 31),
          results.add,
        ),
      );
      await _open(tester);

      await tester.tap(find.byKey(gridDateMonthKey(2)));
      await tester.pumpAndSettle();
      expect(find.byKey(gridDateDayKey(29)), findsNothing, reason: '2026 年 2 月 28 天');
      expect(find.textContaining('已选 2026-02-28'), findsOneWidget, reason: '31 日收敛到 28');

      await tester.tap(find.byKey(gridDateDayKey(28)));
      await tester.pumpAndSettle();
      expect(results, [DateTime(2026, 2, 28)]);

      // 闰年 2024：29 日可选。
      await tester.pumpWidget(
        _harness(
          DateTime(2024, 2, 1),
          DateTime(2024, 1, 1),
          DateTime(2024, 12, 31),
          (_) {},
        ),
      );
      await _open(tester);
      expect(find.byKey(gridDateDayKey(29)), findsOneWidget);
    });

    testWidgets('区间外的年 / 月 / 日不可选（点了不关闭弹窗）', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final results = <DateTime?>[];
      await tester.pumpWidget(
        _harness(
          DateTime(2026, 3, 15),
          DateTime(2026, 3, 10),
          DateTime(2026, 3, 20),
          results.add,
        ),
      );
      await _open(tester);

      // 只应出现 2026 一年；1 月 / 4 月整月越界 → 禁用。
      expect(find.byKey(gridDateYearKey(2025)), findsNothing);
      await tester.tap(find.byKey(gridDateMonthKey(1)));
      await tester.pumpAndSettle();
      expect(find.byKey(gridDatePickerKey), findsOneWidget, reason: '1 月越界，点了不生效');

      // 10 日之前不可选。
      await tester.tap(find.byKey(gridDateDayKey(5)));
      await tester.pumpAndSettle();
      expect(find.byKey(gridDatePickerKey), findsOneWidget);
      expect(results, isEmpty);

      await tester.tap(find.byKey(gridDateDayKey(15)));
      await tester.pumpAndSettle();
      expect(results, [DateTime(2026, 3, 15)]);
    });

    testWidgets('「今天」在区间内才可用', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final inRange = <DateTime?>[];
      await tester.pumpWidget(
        _harness(
          DateTime(now.year, 1, 1),
          DateTime(now.year - 1, 1, 1),
          now,
          inRange.add,
        ),
      );
      await _open(tester);
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      expect(inRange, [today]);

      // 区间全在过去 → 按钮禁用。
      await tester.pumpWidget(
        _harness(
          DateTime(2020, 1, 1),
          DateTime(2019, 1, 1),
          DateTime(2020, 12, 31),
          (_) {},
        ),
      );
      await _open(tester);
      final btn = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('今天'),
          matching: find.byType(TextButton),
        ),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('取消返回 null', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final results = <DateTime?>[];
      await tester.pumpWidget(
        _harness(
          DateTime(2026, 9, 17),
          DateTime(2026, 1, 1),
          DateTime(2026, 12, 31),
          results.add,
        ),
      );
      await _open(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });
  });

  group('日期块：周一到周日表头 + 日期对齐（用户 2026-09-17 追加）', () {
    test('每月 1 号前的空格数 = 该日星期（周一 = 0）', () {
      // 2026-09-07 是周一 → 09-01 是周二 → 前导 1 格。
      expect(gridDateMonthOffset(2026, 9), 1);
      // 2026-09-01 起算：09-07 周一 → offset 0 的月份找 2026-06（06-01 周一）。
      expect(gridDateMonthOffset(2026, 6), 0);
      // 2026-03-01 是周日 → 前导 6 格。
      expect(gridDateMonthOffset(2026, 3), 6);
    });

    testWidgets('顶部显示周一到周日，且 1 号落在正确的星期列', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(
          DateTime(2026, 9, 17),
          DateTime(2026, 1, 1),
          DateTime(2026, 12, 31),
          (_) {},
        ),
      );
      await _open(tester);

      // 表头：周一到周日 7 格。
      expect(gridDateWeekdayLabels.length, 7);
      for (var i = 0; i < 7; i++) {
        expect(find.byKey(gridDateWeekdayKey(i)), findsOneWidget);
        expect(find.text(gridDateWeekdayLabels[i]), findsOneWidget);
      }

      // 对齐：2026-09-01 是周二 → 与「周二」同列；09-07（周一）与「周一」同列；
      // 09-06（周日）与「周日」同列。
      double x(int index) => tester.getCenter(find.byKey(gridDateWeekdayKey(index))).dx;
      expect(
        tester.getCenter(find.byKey(gridDateDayKey(1))).dx,
        closeTo(x(1), 0.5),
        reason: '1 号（周二）应落在周二列',
      );
      expect(tester.getCenter(find.byKey(gridDateDayKey(6))).dx, closeTo(x(6), 0.5));
      expect(tester.getCenter(find.byKey(gridDateDayKey(7))).dx, closeTo(x(0), 0.5));

      // 同一列的纵向间距一致（每格都在自己那一列内，不串列）。
      expect(
        tester.getCenter(find.byKey(gridDateDayKey(14))).dx,
        closeTo(x(0), 0.5),
      );
    });

    testWidgets('切月后表头不变、日期重新对齐', (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(
          DateTime(2026, 9, 17),
          DateTime(2026, 1, 1),
          DateTime(2026, 12, 31),
          (_) {},
        ),
      );
      await _open(tester);

      await tester.tap(find.byKey(gridDateMonthKey(3)));
      await tester.pumpAndSettle();

      // 2026-03-01 是周日 → 落在「周日」列（index 6）。
      expect(gridDateMonthOffset(2026, 3), 6);
      expect(
        tester.getCenter(find.byKey(gridDateDayKey(1))).dx,
        closeTo(tester.getCenter(find.byKey(gridDateWeekdayKey(6))).dx, 0.5),
      );
      // 表头依旧 7 格、仍在（不随月份变化）。
      for (var i = 0; i < 7; i++) {
        expect(find.byKey(gridDateWeekdayKey(i)), findsOneWidget);
      }
    });
  });
}
