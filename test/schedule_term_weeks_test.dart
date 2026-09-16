import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/term_weeks.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';

/// 用户 2026-09-15：「第一周和最后一周不允许再滑动，具体第一周和最后一周的界定
/// 教务系统应该有接口……你找找然后复用」—— 本文件守住最后一周的取数口径。
void main() {
  SchoolCalendar calendarWith(List<String?> weekNos) => SchoolCalendar(
    title: '江西财经大学2026-2027学年第一学期校历',
    xn: 2026,
    xq: 0,
    months: [
      CalendarMonth(
        year: 2026,
        month: 9,
        rows: [
          for (final w in weekNos)
            CalendarWeekRow(weekNo: w, days: const [1, 2, 3, 4, 5, 6, 7]),
        ],
      ),
    ],
    notes: const [],
  );

  ScheduleEntry entryWith(int startWeek, int endWeek) => ScheduleEntry(
    classCode: 'C1-01',
    className: '高等数学(01)',
    courseCode: 'C1',
    courseName: '高等数学',
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
        startWeek: startWeek,
        endWeek: endWeek,
        weekParity: WeekParity.every,
        dayOfWeek: DayOfWeek.monday,
        startPeriod: 1,
        endPeriod: 2,
        classroom: '麦三教101',
      ),
    ],
  );

  group('最后教学周：教务校历周次表', () {
    test('取周次表里的最大周次', () {
      final calendar = calendarWith(['1', '2', '17', null, '']);
      expect(lastWeekFromCalendar(calendar), 17);
    });

    test('周次格可能是「第N周」形态，抽数字', () {
      expect(lastWeekFromCalendar(calendarWith(['第1周', '第9周'])), 9);
    });

    test('无校历 / 全空行 → null', () {
      expect(lastWeekFromCalendar(null), isNull);
      expect(lastWeekFromCalendar(calendarWith([null, '  '])), isNull);
    });
  });

  group('最后教学周：课表周次兜底', () {
    test('取各时段 endWeek 最大值', () {
      final entries = [entryWith(1, 16), entryWith(2, 17), entryWith(1, 8)];
      expect(lastWeekFromEntries(entries), 17);
    });

    test('空课表 → null', () {
      expect(lastWeekFromEntries(const []), isNull);
    });
  });

  group('resolveLastTeachingWeek 优先级', () {
    test('校历优先于课表', () {
      expect(
        resolveLastTeachingWeek(
          calendar: calendarWith(['1', '17']),
          entries: [entryWith(1, 20)],
        ),
        17,
      );
    });

    test('校历取不到时用课表', () {
      expect(
        resolveLastTeachingWeek(calendar: null, entries: [entryWith(1, 18)]),
        18,
      );
    });

    test('两者都取不到 → 兜底周数', () {
      expect(
        resolveLastTeachingWeek(calendar: null, entries: const []),
        fallbackTeachingWeeks,
      );
      expect(fallbackTeachingWeeks, 20);
    });
  });

  group('clampTeachingWeek：首/末周不允许再滑动', () {
    test('第一周往前（0 / 负数）夹到 1', () {
      expect(clampTeachingWeek(0, lastWeek: 17), 1);
      expect(clampTeachingWeek(-3, lastWeek: 17), 1);
    });

    test('最后一周往后夹到 lastWeek', () {
      expect(clampTeachingWeek(18, lastWeek: 17), 17);
      expect(clampTeachingWeek(99, lastWeek: 17), 17);
    });

    test('范围之内原样通过', () {
      expect(clampTeachingWeek(9, lastWeek: 17), 9);
      expect(clampTeachingWeek(1, lastWeek: 17), 1);
      expect(clampTeachingWeek(17, lastWeek: 17), 17);
    });

    test('异常 lastWeek（0 / 负）也返回合法周次', () {
      expect(clampTeachingWeek(5, lastWeek: 0), 1);
      expect(clampTeachingWeek(5, lastWeek: -1), 1);
    });
  });
}
