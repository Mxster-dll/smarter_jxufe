/// 周数选择器守卫（用户 2026-09-16：「取消周数的左右按钮，但是点击周数，显示一个
/// 周数选择器，要可以输入周数 / 点击直接选择周数」；2026-09-17 追加：
/// 「我希望周数选择界面，除了输入周数外，还可以输入日期，跳到对应周数」）。
///
/// 只测 `showScheduleWeekPicker` 本身：点格子选、输入框选、**按日期跳转**、
/// 超范围/格式错就地报错不关闭、「本周」/「取消」，以及日期范围文案。标题栏里
/// 「点周数开弹窗」由 `test/schedule_title_bar_test.dart` 覆盖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_week_picker.dart';

/// 261 学期口径：第 1 教学周周一 = 2026-09-07（见 `teaching_week.dart`）。
DateTime _mondayOf261(int week) =>
    DateTime(2026, 9, 7).add(Duration(days: (week - 1) * 7));

void main() {
  group('日期范围文案', () {
    test('周一 + 六天', () {
      expect(
        scheduleWeekRangeText(DateTime(2026, 9, 7)),
        '09-07 ~ 09-13',
        reason: '第 1 周（261 学期）= 09-07 ~ 09-13',
      );
    });

    test('跨月', () {
      expect(scheduleWeekRangeText(DateTime(2026, 9, 28)), '09-28 ~ 10-04');
    });

    test('没有周一 → null（不显示范围行）', () {
      expect(scheduleWeekRangeText(null), isNull);
    });

    test('学期范围文案（第 1 周周一到第 20 周周日）', () {
      expect(
        scheduleTermRangeText(lastWeek: 20, mondayOf: _mondayOf261),
        '09-07 ~ 01-24',
        reason: '第 20 周 = 2027-01-18 ~ 01-24（跨年）',
      );
      expect(
        scheduleTermRangeText(lastWeek: 20, mondayOf: (w) => null),
        isNull,
      );
    });
  });

  group('日期输入解析（纯函数）', () {
    /// `[月, 日, 年]`（年可省）—— 用列表比对，避免 record 形状不同导致的不相等。
    List<int?> parts(String raw) {
      final p = scheduleParseDateInput(raw);
      return [p?.month, p?.day, p?.year];
    }

    test('省年份 / 完整日期 / 各种分隔符', () {
      expect(parts('10-02'), [10, 2, null]);
      for (final raw in const [
        '2026-10-02',
        '2026/10/2',
        '2026.10.2',
        '2026年10月2日',
        '20261002',
        ' 2026-10-2 ',
      ]) {
        expect(parts(raw), [10, 2, 2026], reason: '$raw 应解析成 2026-10-02');
      }
    });

    test('认不出的输入一律 null', () {
      for (final raw in const [
        '',
        '   ',
        'abc',
        '13-40',
        '00-10',
        '10-32',
        '2026-02-30',
        '2026',
        '2026-10',
        '1-2-3-4',
        '20260-10-02',
      ]) {
        expect(scheduleParseDateInput(raw), isNull, reason: '「$raw」不是日期');
      }
    });

    test('日期 → 教学周（周一到周日都算，含跨年）', () {
      int? week(String raw) => scheduleWeekOfDateText(
        raw,
        lastWeek: 20,
        mondayOf: _mondayOf261,
      );
      expect(week('09-07'), 1, reason: '第 1 周周一');
      expect(week('09-13'), 1, reason: '第 1 周周日');
      expect(week('09-14'), 2, reason: '第 2 周周一（不落到上一周）');
      expect(week('10-02'), 4);
      expect(week('2026-10-02'), 4);
      expect(week('01-20'), 20, reason: '跨年：第 20 周在 2027-01');
      expect(week('2027-01-20'), 20);
      expect(week('2026-01-20'), isNull, reason: '年份对不上就不认');
    });

    test('不在本学期范围内 → null', () {
      int? week(String raw) => scheduleWeekOfDateText(
        raw,
        lastWeek: 20,
        mondayOf: _mondayOf261,
      );
      expect(week('09-06'), isNull, reason: '开学前一天');
      expect(week('08-30'), isNull);
      expect(week('01-25'), isNull, reason: '第 20 周周日之后');
    });
  });

  group('选择周数弹窗', () {
    /// 开弹窗并把返回值写进 [results]。
    ///
    /// ⚠ 不能「先 `final future = open(...)`（不 await）再断言」—— 那样
    /// `pumpWidget` 还没跑完就调用其它 test API，报
    /// `Guarded function conflict. You must use "await" with all Future-returning
    /// test APIs.`（首版就是这么写的，5 例全挂）。
    Future<void> openPicker(
      WidgetTester tester, {
      int week = 3,
      int? currentWeek = 5,
      bool withDates = true,
      required List<int?> results,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    results.add(
                      await showScheduleWeekPicker(
                        context,
                        week: week,
                        lastWeek: 20,
                        currentWeek: currentWeek,
                        mondayOf: withDates ? _mondayOf261 : null,
                      ),
                    );
                  },
                  child: const Text('开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('开'));
      await tester.pumpAndSettle();
    }

    testWidgets('格子按 lastWeek 排开，点一下即选中并关闭', (tester) async {
      final results = <int?>[];
      await openPicker(tester, results: results);
      expect(find.text('选择周数'), findsOneWidget);
      for (final w in const [1, 2, 20]) {
        expect(find.byKey(scheduleWeekCellKey(w)), findsOneWidget);
      }
      expect(
        find.byKey(scheduleWeekCellKey(21)),
        findsNothing,
        reason: '范围 = 1..lastWeek（20）',
      );
      await tester.tap(find.byKey(scheduleWeekCellKey(9)));
      await tester.pumpAndSettle();
      expect(results, [9]);
      expect(find.text('选择周数'), findsNothing);
    });

    testWidgets('输入周数 + 「跳转」也能选', (tester) async {
      final results = <int?>[];
      await openPicker(tester, results: results);
      await tester.enterText(find.byKey(scheduleWeekInputKey), '12');
      await tester.tap(find.byKey(scheduleWeekSubmitKey));
      await tester.pumpAndSettle();
      expect(results, [12]);
    });

    testWidgets('输入越界 → 就地报错、弹窗不关（不返回）', (tester) async {
      final results = <int?>[];
      await openPicker(tester, results: results);
      await tester.enterText(find.byKey(scheduleWeekInputKey), '25');
      await tester.pump();
      expect(find.text('超出 1 - 20'), findsOneWidget);
      await tester.tap(find.byKey(scheduleWeekSubmitKey));
      await tester.pumpAndSettle();
      expect(find.text('选择周数'), findsOneWidget, reason: '越界不关闭');
      expect(results, isEmpty);
      // 改正后可选
      await tester.enterText(find.byKey(scheduleWeekInputKey), '7');
      await tester.tap(find.byKey(scheduleWeekSubmitKey));
      await tester.pumpAndSettle();
      expect(results, [7]);
    });

    testWidgets('「本周」直接回本周；没有本周时不显示该按钮；「取消」返回 null', (tester) async {
      final results = <int?>[];
      await openPicker(tester, currentWeek: 5, results: results);
      await tester.tap(find.text('本周'));
      await tester.pumpAndSettle();
      expect(results, [5]);

      final cancelled = <int?>[];
      await openPicker(tester, currentWeek: null, results: cancelled);
      expect(find.text('本周'), findsNothing, reason: '没有本周时不显示该按钮');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cancelled, [null]);
    });

    testWidgets('高亮当前周；本周带圆点说明；范围来自 mondayOf', (tester) async {
      final results = <int?>[];
      await openPicker(tester, week: 3, currentWeek: 3, results: results);
      final scheme = Theme.of(
        tester.element(find.byKey(scheduleWeekGridKey)),
      ).colorScheme;
      final selected = tester.widget<Material>(
        find
            .ancestor(
              of: find.byKey(scheduleWeekCellKey(3)),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(selected.color, scheme.primary, reason: '选中周 = 主色填充');
      expect(find.textContaining('圆点 = 本周'), findsOneWidget);
      expect(
        find.text('第 3 周：09-21 ~ 09-27（本周）'),
        findsOneWidget,
        reason: '第 3 周（09-07 起算）= 09-21 ~ 09-27',
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });

    testWidgets('输入日期 + 「按日期跳转」跳到那一周（周视图预览跟着日期走）', (tester) async {
      final results = <int?>[];
      await openPicker(tester, currentWeek: 5, results: results);
      await tester.enterText(find.byKey(scheduleWeekDateInputKey), '10-02');
      await tester.pump();
      expect(
        find.text('10-02 → 第 4 周：09-28 ~ 10-04'),
        findsOneWidget,
        reason: '10-02 落在第 4 周（09-28 ~ 10-04）',
      );
      await tester.tap(find.byKey(scheduleWeekDateSubmitKey));
      await tester.pumpAndSettle();
      expect(results, [4]);
      expect(find.text('选择周数'), findsNothing);
    });

    testWidgets('完整日期与省年份等价；周一到周日都算同一周', (tester) async {
      for (final (raw, expected) in const [
        ('2026-10-02', 4),
        ('2026/10/2', 4),
        ('10-04', 4),
        ('09-13', 1),
      ]) {
        final results = <int?>[];
        await openPicker(tester, results: results);
        await tester.enterText(find.byKey(scheduleWeekDateInputKey), raw);
        await tester.tap(find.byKey(scheduleWeekDateSubmitKey));
        await tester.pumpAndSettle();
        expect(results, [expected], reason: '「$raw」应跳到第 $expected 周');
      }
    });

    testWidgets('日期格式认不出 → 就地报错、弹窗不关', (tester) async {
      final results = <int?>[];
      await openPicker(tester, results: results);
      await tester.enterText(find.byKey(scheduleWeekDateInputKey), '13-40');
      await tester.pump();
      expect(find.text('认不出日期，如 10-02'), findsOneWidget);
      await tester.tap(find.byKey(scheduleWeekDateSubmitKey));
      await tester.pumpAndSettle();
      expect(find.text('选择周数'), findsOneWidget, reason: '格式错不关闭');
      expect(results, isEmpty);
    });

    testWidgets('日期不在本学期范围内 → 报出学期区间、不关闭；改正后可选', (tester) async {
      final results = <int?>[];
      await openPicker(tester, results: results);
      await tester.tap(find.byKey(scheduleWeekDateSubmitKey));
      await tester.pump();
      expect(find.text('请输入日期，如 10-02'), findsOneWidget, reason: '空输入也有提示');

      await tester.enterText(find.byKey(scheduleWeekDateInputKey), '08-30');
      await tester.pump();
      expect(
        find.text('不在本学期范围内（09-07 ~ 01-24）'),
        findsOneWidget,
        reason: '开学前 08-30 不在 261 学期（09-07 ~ 01-24）内',
      );
      await tester.enterText(find.byKey(scheduleWeekDateInputKey), '01-20');
      await tester.tap(find.byKey(scheduleWeekDateSubmitKey));
      await tester.pumpAndSettle();
      expect(results, [20], reason: '跨年学期：01-20 = 第 20 周');
    });

    testWidgets('拿不到日期（历史学期 / 无校历）→ 日期那一行整行不渲染', (tester) async {
      final results = <int?>[];
      await openPicker(tester, withDates: false, results: results);
      expect(find.byKey(scheduleWeekDateInputKey), findsNothing);
      expect(find.byKey(scheduleWeekDateSubmitKey), findsNothing);
      expect(find.textContaining('只能按周数选择'), findsOneWidget);
      // 周数输入仍然可用
      await tester.enterText(find.byKey(scheduleWeekInputKey), '6');
      await tester.tap(find.byKey(scheduleWeekSubmitKey));
      await tester.pumpAndSettle();
      expect(results, [6]);
    });
  });
}
