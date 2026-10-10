/// 课表视图「响应校历事件」的渲染守卫（用户 2026-10-08 需求）。
///
/// 域层取课口径另见 `test/schedule_board_test.dart`（那个文件是纯函数断言），
/// 本文件只看**画出来的东西**：假期列空、补课列改上被补那天的课、表头小字。
///
/// 真实样本（内置 261 校历 + 手写课表）：
/// - 第 5 周 = 2026-10-05 ~ 10-11；10-05/06/07 国庆假期；
/// - 10-10（周六）=「补第4周周五的课」→ 这一列要显示第 4 周周五的课；
/// - 周五（10-09）本身是普通上课日。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_board.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_horizontal_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_tone.dart';
import 'package:smarter_jxufe/features/school_calendar/data/wxcal_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_effect.dart';

final DateTime _week1Monday = DateTime(2026, 9, 7);

DateTime _monday(int week) => _week1Monday.add(Duration(days: (week - 1) * 7));

ScheduleCalendarContext _ctx() => ScheduleCalendarContext(
  effects: CalendarDayEffectIndex.build(terms: wxcalOfflineToDomain()),
  lastWeek: 17,
  termFirstMonday: _week1Monday,
);

ScheduleEntry _entry({
  required String code,
  required String name,
  required DayOfWeek day,
  int startPeriod = 1,
  int endPeriod = 2,
}) => ScheduleEntry(
  classCode: '$code-01',
  className: '$name(01)',
  courseCode: code,
  courseName: name,
  totalHours: 48,
  credits: 3,
  studyNature: '必修',
  teacherCode: 'T1',
  teacherName: '张三',
  selectionStatus: '已选',
  isCrossMajor: false,
  hasTextbook: true,
  classTimes: [
    ClassTime(
      startWeek: 1,
      endWeek: 16,
      weekParity: WeekParity.every,
      dayOfWeek: day,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      classroom: '麦三教101',
    ),
  ],
);

/// 周一高数（1-2 节）、周五英语（3-4 节）、周六体育（5-6 节）。
List<ScheduleEntry> _entries() => [
  _entry(code: 'M1', name: '高等数学', day: DayOfWeek.monday),
  _entry(
    code: 'E1',
    name: '大学英语',
    day: DayOfWeek.friday,
    startPeriod: 3,
    endPeriod: 4,
  ),
  _entry(
    code: 'P1',
    name: '体育',
    day: DayOfWeek.saturday,
    startPeriod: 5,
    endPeriod: 6,
  ),
];

Widget _harness(Widget child) => MaterialApp(
  theme: appLightTheme,
  home: Scaffold(
    body: SizedBox(width: 900, height: 900, child: child),
  ),
);

void main() {
  testWidgets('竖版：假期列空着、补课列改上第 4 周周五的课、表头带小字', (tester) async {
    await tester.pumpWidget(
      _harness(
        ScheduleGridView(
          entries: _entries(),
          week: 5,
          weekMonday: _monday(5),
          showToggle: false,
          calendar: _ctx(),
        ),
      ),
    );

    // 10-05 周一在国庆假期里 → 高数不显示。
    expect(find.text('高等数学'), findsNothing, reason: '假期列不排课');
    // 10-09 周五（普通日）与 10-10 周六（补课日）都该有英语。
    expect(
      find.text('大学英语'),
      findsNWidgets(2),
      reason: '补课日 = 再上一次第 4 周周五的课',
    );
    // 周六本来的体育让位给被补的那天。
    expect(find.text('体育'), findsNothing);

    // 表头小字：3 个假期列（10-05/06/07）+ 1 个补课列。
    expect(find.text('国庆节假期'), findsNWidgets(3));
    expect(find.text('补第4周周五'), findsOneWidget);

    expect(tester.takeException(), isNull, reason: '表头多一行不许溢出');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('竖版：不传校历 = 旧观感（周六还是体育、无小字）', (tester) async {
    await tester.pumpWidget(
      _harness(
        ScheduleGridView(
          entries: _entries(),
          week: 5,
          weekMonday: _monday(5),
          showToggle: false,
        ),
      ),
    );
    expect(find.text('高等数学'), findsOneWidget, reason: '10-05 照旧上课');
    expect(find.text('体育'), findsOneWidget);
    expect(find.text('国庆节假期'), findsNothing);
    expect(find.text('补第4周周五'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('横版：同一份口径（行首小字 + 同样的取课）', (tester) async {
    await tester.pumpWidget(
      _harness(
        ScheduleHorizontalView(
          entries: _entries(),
          week: 5,
          weekMonday: _monday(5),
          showToggle: false,
          calendar: _ctx(),
        ),
      ),
    );
    expect(find.text('高等数学'), findsNothing);
    expect(find.text('体育'), findsNothing);
    expect(find.text('补第4周周五'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('横版：行高被压到 40dp 以下时只丢小字，不溢出', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 760,
            height: 320, // (320 − 24 − 40) / 7 ≈ 36.5dp 行高
            child: ScheduleHorizontalView(
              entries: _entries(),
              week: 5,
              weekMonday: _monday(5),
              showToggle: false,
              calendar: _ctx(),
            ),
          ),
        ),
      ),
    );
    expect(find.text('补第4周周五'), findsNothing, reason: '矮行放下三行会溢出 → 只画两行');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  group('表头红 / 灰的判据 = 这一天有没有课（用户 2026-10-09）', () {
    /// 表头那颗 Container 的底色（表头 = 包着星期名的最近一层 Container）。
    Color? headerFill(WidgetTester tester, String dayName) {
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text(dayName), matching: find.byType(Container))
            .first,
      );
      return (container.decoration as BoxDecoration?)?.color;
    }

    testWidgets('★ 竖版第 5 周：假期里的工作日与没课的工作日都是灰，只有有课的两天是红', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ScheduleGridView(
            entries: _entries(),
            week: 5,
            weekMonday: _monday(5),
            showToggle: false,
            calendar: _ctx(),
          ),
        ),
      );

      // 10-05 ~ 10-07 国庆假期（课被校历抑制掉）→ 没有课 → 灰
      for (final day in const ['周一', '周二', '周三']) {
        expect(
          headerFill(tester, day),
          ScheduleTone.weekendHeader,
          reason: '$day 在假期里，这一天没有课 → 不许再用「工作日 = 红」',
        );
      }
      // 10-08 周四：这一周本来就没排课 → 也没有课 → 灰（同样是数据说了算）
      expect(headerFill(tester, '周四'), ScheduleTone.weekendHeader);
      // 10-09 周五（普通上课日）→ 红
      expect(headerFill(tester, '周五'), ScheduleTone.headerRed);
      // 10-10 周六（补第 4 周周五）→ 有课 → **红**（不是「周末 = 灰」）
      expect(headerFill(tester, '周六'), ScheduleTone.headerRed);
      // 10-11 周日：没课 → 灰
      expect(headerFill(tester, '周日'), ScheduleTone.weekendHeader);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('★ 不传校历 = 按课表本身有没有课算（周一有高数 → 红；周日没课 → 灰）', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ScheduleGridView(
            entries: _entries(),
            week: 5,
            weekMonday: _monday(5),
            showToggle: false,
          ),
        ),
      );
      expect(headerFill(tester, '周一'), ScheduleTone.headerRed);
      expect(headerFill(tester, '周二'), ScheduleTone.weekendHeader, reason: '没排课');
      expect(headerFill(tester, '周六'), ScheduleTone.headerRed, reason: '周六本来就有体育');
      expect(headerFill(tester, '周日'), ScheduleTone.weekendHeader);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('★ 横版：同一条判据落到行首标签（有课 = 主题红字 + 淡底；没课 = 灰字 + 深底）', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          ScheduleHorizontalView(
            entries: _entries(),
            week: 5,
            weekMonday: _monday(5),
            showToggle: false,
            calendar: _ctx(),
          ),
        ),
      );
      final ctx = tester.element(find.byType(ScheduleHorizontalView));
      final primary = appLightTheme.colorScheme.primary;

      Color? labelTextColor(String dayName) =>
          tester.widget<Text>(find.text(dayName)).style?.color;

      Color? labelFill(String dayName) => (tester
                  .widget<Container>(
                    find
                        .ancestor(
                          of: find.text(dayName),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration?)
          ?.color;

      expect(labelTextColor('周五'), primary, reason: '周五有英语');
      expect(labelTextColor('周一'), AppColors.textMuted(ctx), reason: '假期');
      expect(labelFill('周五'), AppColors.fillSoft(ctx));
      expect(labelFill('周一'), AppColors.fill(ctx));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    test('源码守卫：两个视图都不许再按星期几决定红 / 灰', () {
      String read(String rel) => File(rel).readAsStringSync();
      final grid = read(
        'lib/features/ims/schedule/presentation/schedule_grid_view.dart',
      );
      final horizontal = read(
        'lib/features/ims/schedule/presentation/schedule_horizontal_view.dart',
      );
      for (final src in [grid, horizontal]) {
        expect(
          src.contains('isWeekend'),
          isFalse,
          reason: '「周末」这个判据已从配色里彻底退场（改为 column.hasClass）',
        );
      }
      expect(grid.contains('ScheduleTone.headerFillOf('), isTrue);
      expect(horizontal.contains('ScheduleTone.columnFillOf('), isTrue);
      expect(horizontal.contains('ScheduleTone.emptyCellFillOf('), isTrue);
    });
  });
}
