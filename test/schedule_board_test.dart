/// 课表「响应校历事件」的守卫测试（用户 2026-10-08 需求）。
///
/// 用户原话：「如果是假期就不显示课程（除非是移课移到那天），然后还有诸如 xx 天补
/// xx 周 xx 天课程，这样的课表也要动态响应」+「修改一下课表隐藏周六、周日的逻辑，
/// 隐藏生效仅当没课时才生效，如果某周周 x 有课，但是设置又是隐藏周 x，那么此时这天
/// 还是显示的」。
///
/// 覆盖 `domain/schedule_board.dart`（列计划 / 假期抑制 / 补课取源 / 可见天判据）
/// 与 `domain/schedule_display_days.dart`（`scheduleVisibleDays` 的新参数）。
/// 校历侧的判定另见 `test/schedule_calendar_effect_test.dart`。
///
/// 全部用**真实 261 校历**（内置离线快照）+ 手写课表：
/// - 第 1 教学周 = 2026-09-07 那一周；
/// - 2026-10-01 ~ 10-07 国庆假期（第 5 周）；
/// - 2026-10-10（第 5 周周六）=「补第4周周五的课」→ 该列要显示**第 4 周周五**的课。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_board.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_display_days.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/school_calendar/data/wxcal_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_effect.dart';

/// 第 1 教学周的周一（261 学期起始周）。
final DateTime _week1Monday = DateTime(2026, 9, 7);

/// 第 [week] 周的周一。
DateTime _monday(int week) => _week1Monday.add(Duration(days: (week - 1) * 7));

/// 与课表页同源的校历上下文（效应索引 + 教学周范围）。
ScheduleCalendarContext _ctx({int lastWeek = 17}) => ScheduleCalendarContext(
  effects: CalendarDayEffectIndex.build(terms: wxcalOfflineToDomain()),
  lastWeek: lastWeek,
  termFirstMonday: _week1Monday,
);

ScheduleEntry _entry({
  required String code,
  required String name,
  required DayOfWeek day,
  required int startWeek,
  required int endWeek,
  int startPeriod = 1,
  int endPeriod = 2,
  String classroom = '麦三教101',
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
      startWeek: startWeek,
      endWeek: endWeek,
      weekParity: WeekParity.every,
      dayOfWeek: day,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      classroom: classroom,
    ),
  ],
);

/// 周一高数（1-16 周）、周五英语（1-16 周）、周六体育（1-16 周）。
List<ScheduleEntry> _fullWeek() => [
  _entry(
    code: 'M1',
    name: '高等数学',
    day: DayOfWeek.monday,
    startWeek: 1,
    endWeek: 16,
    startPeriod: 1,
    endPeriod: 2,
  ),
  _entry(
    code: 'E1',
    name: '大学英语',
    day: DayOfWeek.friday,
    startWeek: 1,
    endWeek: 16,
    startPeriod: 3,
    endPeriod: 4,
  ),
  _entry(
    code: 'P1',
    name: '体育',
    day: DayOfWeek.saturday,
    startWeek: 1,
    endWeek: 16,
    startPeriod: 5,
    endPeriod: 6,
  ),
];

/// 某一周某一列显示的课程名（升序）。
List<String> _namesAt(
  List<ScheduleColumn> columns,
  int dayIndex, {
  int? period,
}) {
  final slots = columns[dayIndex].slots;
  final out = <String>[];
  for (final e in slots.entries) {
    if (period != null && e.key != period) continue;
    for (final c in e.value) {
      out.add(c.courseName);
    }
  }
  out.sort();
  return out;
}

void main() {
  group('列计划：日期 / 效应 / 取课来源', () {
    final columns = scheduleBoardColumns(
      entries: _fullWeek(),
      reschedules: const [],
      week: 5,
      weekMonday: _monday(5),
      calendar: _ctx(),
    );

    test('7 列都带日期（第 5 周 = 10-05 ~ 10-11）', () {
      expect(columns.length, 7);
      expect(columns[0].plan.date, DateTime(2026, 10, 5));
      expect(columns[6].plan.date, DateTime(2026, 10, 11));
    });

    test('假期列带假期名；补课列带补课说明与来源周', () {
      // 10-05 周一、10-06 周二、10-07 周三都在国庆假期里
      expect(columns[0].plan.isHoliday, isTrue);
      expect(columns[0].plan.effectLabel, '国庆节假期');
      expect(columns[2].plan.isHoliday, isTrue);

      // 10-10 周六 = 补第 4 周周五的课
      final sat = columns[5].plan;
      expect(sat.isMakeup, isTrue);
      expect(sat.effectLabel, '补第4周周五');
      expect(sat.sourceWeek, 4);
      expect(sat.sourceDayIndex, 4, reason: '0 = 周五');
      expect(sat.borrowsAnotherDay, isTrue);
      expect(sat.sourceHint, '按第 4 周周五的课表');

      // 10-08 周四 = 普通上课日
      expect(columns[3].plan.effect, CalendarDayEffectKind.normal);
      expect(columns[3].plan.effectLabel, isEmpty);
    });

    test('整学期模板 / 没有校历时：一律普通列，不编日期', () {
      final tpl = scheduleBoardColumns(
        entries: _fullWeek(),
        reschedules: const [],
        calendar: _ctx(),
      );
      expect(tpl.every((c) => c.plan.effect == CalendarDayEffectKind.normal), isTrue);
      expect(tpl.every((c) => c.plan.date == null), isTrue);

      final noCal = scheduleBoardColumns(
        entries: _fullWeek(),
        reschedules: const [],
        week: 5,
        weekMonday: _monday(5),
      );
      expect(
        noCal.every((c) => c.plan.effect == CalendarDayEffectKind.normal),
        isTrue,
        reason: '不传校历 = 旧行为（只是列上仍有日期）',
      );
    });
  });

  group('假期不排课', () {
    final columns = scheduleBoardColumns(
      entries: _fullWeek(),
      reschedules: const [],
      week: 5,
      weekMonday: _monday(5),
      calendar: _ctx(),
    );

    test('国庆假期里的周一不显示高数（10-05）', () {
      expect(_namesAt(columns, 0), isEmpty);
      expect(columns[0].hasClass, isFalse);
    });

    test('假期外的同一天照旧（10-12 周一在第 6 周）', () {
      final week6 = scheduleBoardColumns(
        entries: _fullWeek(),
        reschedules: const [],
        week: 6,
        weekMonday: _monday(6),
        calendar: _ctx(),
      );
      expect(_namesAt(week6, 0), ['高等数学']);
    });

    test('假期当天的课不再显示，但课表数据本身没被改动', () {
      // 第 5 周周一被隐藏的只是「这一列」——整学期模板里高数照旧在周一列。
      final tpl = scheduleBoardColumns(
        entries: _fullWeek(),
        reschedules: const [],
        calendar: _ctx(),
      );
      expect(_namesAt(tpl, 0), ['高等数学']);
    });
  });

  group('「除非是移课移到那天」', () {
    test('被调到假期里的课照常显示（10-06 周二 3-4 节）', () {
      final stamp = DateTime(2026, 9, 7);
      final move = Reschedule(
        id: 'r1',
        kind: RescheduleKind.move,
        scope: RescheduleScope.once,
        week: 5,
        courseCode: 'M1',
        courseName: '高等数学',
        originDay: DayOfWeek.monday,
        originStartPeriod: 1,
        originEndPeriod: 2,
        targetDay: DayOfWeek.tuesday,
        targetStartPeriod: 3,
        targetEndPeriod: 4,
        createdAt: stamp,
        updatedAt: stamp,
      );
      final columns = scheduleBoardColumns(
        entries: _fullWeek(),
        reschedules: [move],
        week: 5,
        weekMonday: _monday(5),
        calendar: _ctx(),
      );
      // 周一（假期）只剩「已调至…」占位 → 假期列把它也一并收掉
      expect(_namesAt(columns, 0), isEmpty);
      // 周二（假期）有课被搬进来 → 必须显示，否则这节课就人间蒸发了
      expect(_namesAt(columns, 1), ['高等数学']);
      expect(columns[1].hasClass, isTrue);
      // 角标仍是「调」（课格自带），这里只钉住「名字在」
    });

    test('补课（extra）搬到假期同样显示', () {
      final stamp = DateTime(2026, 9, 7);
      final extra = Reschedule(
        id: 'r2',
        kind: RescheduleKind.extra,
        scope: RescheduleScope.once,
        week: 5,
        courseCode: 'X1',
        courseName: '形势与政策',
        targetDay: DayOfWeek.wednesday,
        targetStartPeriod: 7,
        targetEndPeriod: 8,
        targetClassroom: '麦三教305',
        createdAt: stamp,
        updatedAt: stamp,
      );
      final columns = scheduleBoardColumns(
        entries: _fullWeek(),
        reschedules: [extra],
        week: 5,
        weekMonday: _monday(5),
        calendar: _ctx(),
      );
      expect(_namesAt(columns, 2), ['形势与政策']);
    });
  });

  group('补课日按被补那天上课（10-10 补第 4 周周五）', () {
    final columns = scheduleBoardColumns(
      entries: _fullWeek(),
      reschedules: const [],
      week: 5,
      weekMonday: _monday(5),
      calendar: _ctx(),
    );

    test('周六列显示第 4 周周五的英语，而不是本来的体育', () {
      expect(_namesAt(columns, 5), ['大学英语']);
      expect(_namesAt(columns, 5, period: 3), ['大学英语']);
      expect(_namesAt(columns, 5, period: 5), isEmpty, reason: '体育（周六 5-6 节）让位');
    });

    test('第 4 周周五自己（10-02）在国庆假期里 → 那天不显示', () {
      final week4 = scheduleBoardColumns(
        entries: _fullWeek(),
        reschedules: const [],
        week: 4,
        weekMonday: _monday(4),
        calendar: _ctx(),
      );
      expect(week4[4].plan.isHoliday, isTrue);
      expect(_namesAt(week4, 4), isEmpty, reason: '被补的那天正是国庆假期');
    });

    test('补课列也被算作「有课」（隐藏周六时不能把它藏掉）', () {
      final days = scheduleDaysWithClass(
        entries: _fullWeek(),
        week: 5,
        weekMonday: _monday(5),
        calendar: _ctx(),
      );
      expect(days.contains(scheduleSaturdayIndex), isTrue);
    });

    test('不传校历 → 周六仍是体育（旧行为）', () {
      final plain = scheduleBoardColumns(
        entries: _fullWeek(),
        reschedules: const [],
        week: 5,
        weekMonday: _monday(5),
      );
      expect(_namesAt(plain, 5), ['体育']);
    });
  });

  group('某一天「到底有没有课」：隐藏周六 / 周日的判据', () {
    // 只在第 1-4 周有周六课，第 5 周起没有。
    List<ScheduleEntry> satEarly() => [
      _entry(
        code: 'P1',
        name: '体育',
        day: DayOfWeek.saturday,
        startWeek: 1,
        endWeek: 4,
        startPeriod: 5,
        endPeriod: 6,
      ),
    ];

    test('周视图：这一周有课 → 这天要显示（哪怕设置里关着）', () {
      // ⚠ 别用第 3 周：09-25~09-27 是中秋假期，那一周的周六本来就该是空的。
      final days = scheduleDaysWithClass(
        entries: satEarly(),
        week: 2,
        weekMonday: _monday(2),
        calendar: _ctx(),
      );
      expect(days, {scheduleSaturdayIndex});
      expect(
        scheduleVisibleDays(
          showSaturday: false,
          daysWithClass: days,
        ),
        contains(scheduleSaturdayIndex),
        reason: '用户原话：某周周六有课，设置又是隐藏周六，此时这天还是显示的',
      );
    });

    test('周视图：这一周没课 → 开关真的把它收起来', () {
      final days = scheduleDaysWithClass(
        entries: satEarly(),
        week: 8,
        weekMonday: _monday(8),
        calendar: _ctx(),
      );
      expect(days.contains(scheduleSaturdayIndex), isFalse);
      expect(
        scheduleVisibleDays(showSaturday: false, daysWithClass: days),
        isNot(contains(scheduleSaturdayIndex)),
      );
    });

    test('整学期视图：逐周扫 —— 只要有一周真有课就留着这一天', () {
      final days = scheduleDaysWithClass(
        entries: satEarly(),
        calendar: _ctx(),
      );
      expect(days, contains(scheduleSaturdayIndex));
      expect(
        scheduleVisibleDays(showSaturday: false, daysWithClass: days),
        contains(scheduleSaturdayIndex),
      );
    });

    test('整学期视图：课全落在假期里 → 算没课（这一天被收起）', () {
      // 体育只在第 5 周周六（10-10）——那天是补课日，本日的课让位给第 4 周周五。
      final onlyMakeupSaturday = [
        _entry(
          code: 'P1',
          name: '体育',
          day: DayOfWeek.saturday,
          startWeek: 5,
          endWeek: 5,
          startPeriod: 5,
          endPeriod: 6,
        ),
      ];
      final days = scheduleDaysWithClass(
        entries: onlyMakeupSaturday,
        calendar: _ctx(),
      );
      expect(
        days.contains(scheduleSaturdayIndex),
        isFalse,
        reason: '第 5 周周六改上第 4 周周五的课（那天没有课）→ 这一列确实空的',
      );
      expect(
        scheduleVisibleDays(showSaturday: false, daysWithClass: days),
        isNot(contains(scheduleSaturdayIndex)),
      );
    });

    test('没有校历 / 没有日期时退回旧口径（任意一周有课即算有课）', () {
      // 不传 week（整学期模板）、也不传校历 → 模板列本身有课就算有课。
      final days = scheduleDaysWithClass(entries: satEarly());
      expect(days, contains(scheduleSaturdayIndex), reason: '不认校历 → 整学期模板口径');
    });

    test('scheduleVisibleDays 不传 daysWithClass = 旧行为（开关一刀切）', () {
      expect(scheduleVisibleDays(showSaturday: false), [0, 1, 2, 3, 4, 6]);
      expect(
        scheduleVisibleDays(showSaturday: false, daysWithClass: {5}),
        [0, 1, 2, 3, 4, 5, 6],
      );
      expect(
        scheduleVisibleDays(showSunday: false, daysWithClass: {6}),
        [0, 1, 2, 3, 4, 5, 6],
      );
    });
  });

  group('「今天该上什么课」（首页 / 实况窗 / 提醒共用）', () {
    test('假期当天：常规课全没，只剩被搬进来的', () {
      final holiday = effectiveClassesOfDate(
        entries: _fullWeek(),
        reschedules: const [],
        week: 5,
        date: DateTime(2026, 10, 5),
        calendar: _ctx(),
      );
      expect(holiday, isEmpty);

      final normal = effectiveClassesOfDate(
        entries: _fullWeek(),
        reschedules: const [],
        week: 5,
        date: DateTime(2026, 10, 8),
        calendar: _ctx(),
      );
      expect(normal.map((c) => c.courseName), isEmpty, reason: '周四本来就没课');
    });

    test('补课日：按被补那天给课（10-10 周六 → 第 4 周周五的英语）', () {
      final makeup = effectiveClassesOfDate(
        entries: _fullWeek(),
        reschedules: const [],
        week: 5,
        date: DateTime(2026, 10, 10),
        calendar: _ctx(),
      );
      expect(makeup.map((c) => c.courseName), ['大学英语']);
      expect(makeup.first.startPeriod, 3);
    });

    test('不传校历 = 旧口径（只按星期过滤）', () {
      final sat = effectiveClassesOfDate(
        entries: _fullWeek(),
        reschedules: const [],
        week: 5,
        date: DateTime(2026, 10, 10),
      );
      expect(sat.map((c) => c.courseName), ['体育']);
    });
  });
}
