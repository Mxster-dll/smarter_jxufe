/// 课表 ↔ 校历的结合部：把「校历事件」翻译成**课表每一列该显示什么**。
///
/// 用户 2026-10-07 原话：「关于课表的显示，应该响应校历里的事件。具体为如果是假期就
/// 不显示课程（除非是移课移到那天），然后还有诸如 xx 天补 xx 周 xx 天课程，这样的课表
/// 也要动态响应。」
///
/// 三条口径（都在这里实现，页面不许再写一份）：
/// 1. **假期列不排课**：该日期的常规课次全部不显示（含「已调至…」「本次停课」这类
///    占位格）—— 那天学生根本不在上课；
/// 2. **「除非是移课移到那天」**：被调课 / 补课搬到该日期的课次**照常显示**
///    （角标仍是「调 / 补」），这样「老师把课挪到假期」不会变成隐形课；
/// 3. **补课日按被补那天上课**：`补第4周周五的课` → 这一列显示**第 4 周周五**的课表
///    （解析见 `calendar_day_effect.dart` 的 `parseMakeupTarget`），本日原本的课让位。
///
/// 判假 / 判班的**唯一实现**是 `school_calendar` 的 `CalendarMarkIndex`
/// （本模块只做语义转译，绝不重新判一次）；日期 → 教学周的算术也复用
/// `teaching_week.dart` 的锚点。课表页、横版、首页今日课程、实况窗、课前提醒
/// 全部走这里，保证「App 说的时间和地点」在多处一致。
library;

import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_display_days.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/term_weeks.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_effect.dart';

/// 课表按校历显示所需的上下文（页面算一次、两个视图共用）。
class ScheduleCalendarContext {
  /// 校历效应索引（假期 / 补课）；null = 不按校历调整（旧行为，测试与离线场景）。
  final CalendarDayEffectIndex? effects;

  /// 本学期最后教学周（整学期视图逐周扫「这一天到底有没有课」要用）。
  ///
  /// 口径见 `term_weeks.dart`（教务校历周次表 → 课表周次 → 兜底 20 周）。
  final int lastWeek;

  /// 第 1 教学周的周一（同上；整学期视图没有具体日期，靠它推出每一周的日期）。
  final DateTime? termFirstMonday;

  const ScheduleCalendarContext({
    this.effects,
    this.lastWeek = fallbackTeachingWeeks,
    this.termFirstMonday,
  });

  /// 没有任何校历信息。
  static const none = ScheduleCalendarContext();

  /// 某一周的周一（[termFirstMonday] + (week − 1) 周）。
  DateTime? mondayOfWeek(int week) =>
      termFirstMonday?.add(Duration(days: (week - 1) * 7));
}

/// 课表**某一列**（某一天）要显示什么：日期、校历效应、取课的来源。
class ScheduleDayPlan {
  /// 列的星期下标（0 = 周一）。
  final int dayIndex;

  /// 该列日期；整学期模板视图 / 校历不可用时为 null。
  final DateTime? date;

  /// 该日期所属教学周；整学期模板视图为 null。
  final int? week;

  /// 校历效应（普通 / 假期 / 补课）。
  final CalendarDayEffectKind effect;

  /// 表头小字：假期名（「国庆节假期」）或补课说明（「补第4周周五」）；普通日空串。
  final String effectLabel;

  /// 补课日「按谁上课」的提示（「按第 4 周周五的课表」）；非补课日空串。
  final String sourceHint;

  /// 补课日要上的课取自哪一周；null = 与补课日同一周。
  final int? sourceWeek;

  /// 补课日要上的课取自哪个星期（**0 = 周一**）；null = 与补课日同一星期。
  final int? sourceDayIndex;

  const ScheduleDayPlan({
    required this.dayIndex,
    this.date,
    this.week,
    this.effect = CalendarDayEffectKind.normal,
    this.effectLabel = '',
    this.sourceHint = '',
    this.sourceWeek,
    this.sourceDayIndex,
  });

  bool get isHoliday => effect == CalendarDayEffectKind.holiday;

  bool get isMakeup => effect == CalendarDayEffectKind.makeup;

  /// 是否有表头标记（假期 / 补课）。
  bool get hasEffectLabel => effectLabel.isNotEmpty;

  /// 这一列是否「按别的星期上课」（补课日）。
  bool get borrowsAnotherDay => isMakeup && sourceDayIndex != null;

  @override
  String toString() =>
      'ScheduleDayPlan(${scheduleDayNames[dayIndex]}$date ${effect.name}'
      '${effectLabel.isEmpty ? '' : ' $effectLabel'})';
}

/// 课表某一列的渲染数据（列计划 + 课格）。
class ScheduleColumn {
  final ScheduleDayPlan plan;

  /// 起始节次 → 该节次开始的课次（与两个视图 `_buildGrid` 的产物同构）。
  final Map<int, List<EffectiveClass>> slots;

  /// 本列涉及的课程门数（按课程名去重；含调课产生的课次）。
  final int courseCount;

  const ScheduleColumn({
    required this.plan,
    required this.slots,
    required this.courseCount,
  });

  int get dayIndex => plan.dayIndex;

  /// 本列有课格 → 隐藏周六 / 周日的开关对它不生效（用户 2026-10-07 口径）。
  bool get hasClass => courseCount > 0;
}

/// 一页课表（某一周 7 列 / 整学期模板 7 列）的列数据。
///
/// [week] 为 null = 整学期模板：**不按校历调整**（模板没有具体日期，「某一列」是
/// 整学期的汇总，谈不上某天放假），只有 [ScheduleDayPlan.effect] 保持普通。
List<ScheduleColumn> scheduleBoardColumns({
  required List<ScheduleEntry> entries,
  required List<Reschedule> reschedules,
  int? week,
  DateTime? weekMonday,
  ScheduleCalendarContext calendar = ScheduleCalendarContext.none,
}) {
  final plans = scheduleDayPlans(
    week: week,
    weekMonday: weekMonday,
    calendar: calendar,
  );

  // 一周的生效课次只算一次；补课日会取「另一周」的课，故按周缓存。
  final byWeek = <int, List<EffectiveClass>>{};
  List<EffectiveClass> weekClasses(int? w) => byWeek.putIfAbsent(
    w ?? 0,
    () => effectiveClasses(entries: entries, reschedules: reschedules, week: w),
  );

  return [
    for (final plan in plans)
      _columnOf(
        plan,
        week == null
            ? weekClasses(null).where((c) => c.dayIndex - 1 == plan.dayIndex)
            : _classesForPlan(
                plan,
                week: week,
                weekClasses: weekClasses,
              ),
      ),
  ];
}

/// [plan] 这一列实际要显示的课次（假期抑制 + 补课取源，见文件头）。
Iterable<EffectiveClass> _classesForPlan(
  ScheduleDayPlan plan, {
  required int week,
  required List<EffectiveClass> Function(int?) weekClasses,
}) {
  final actual = weekClasses(
    week,
  ).where((c) => c.dayIndex - 1 == plan.dayIndex);

  if (plan.effect == CalendarDayEffectKind.normal) return actual;

  // 「除非是移课移到那天」：调课 / 补课搬到这一天的课，放假也照常显示。
  final landed = actual.where(
    (c) =>
        c.mark == EffectiveMark.moved || c.mark == EffectiveMark.extra,
  );

  if (plan.isHoliday) return landed;

  // 补课日：本日原本的课让位，改上「被补的那一周那一星期」的课。
  final sourceWeek = plan.sourceWeek ?? week;
  final sourceDay = plan.sourceDayIndex ?? plan.dayIndex;
  if (sourceWeek == week && sourceDay == plan.dayIndex) return actual;

  final base = weekClasses(
    sourceWeek,
  ).where((c) => c.dayIndex - 1 == sourceDay);

  // 两批可能撞上（同一门课既在被补的那天、又被搬到本日）→ 按身份去重。
  final out = <EffectiveClass>[];
  final seen = <String>{};
  for (final c in [...base, ...landed]) {
    if (seen.add(_classKey(c))) out.add(c);
  }
  return out;
}

String _classKey(EffectiveClass c) =>
    '${c.courseCode}|${c.startPeriod}|${c.endPeriod}|${c.mark.name}'
    '|${c.reschedule?.id ?? ''}';

ScheduleColumn _columnOf(ScheduleDayPlan plan, Iterable<EffectiveClass> classes) {
  final slots = <int, List<EffectiveClass>>{};
  final names = <String>{};
  for (final c in classes) {
    slots.putIfAbsent(c.startPeriod, () => <EffectiveClass>[]).add(c);
    names.add(c.courseName);
  }
  return ScheduleColumn(plan: plan, slots: slots, courseCount: names.length);
}

/// 7 列（周一 ~ 周日）的列计划。
///
/// [week] 为 null（整学期模板）或没有日期 / 校历 → 全部按普通日处理。
List<ScheduleDayPlan> scheduleDayPlans({
  int? week,
  DateTime? weekMonday,
  ScheduleCalendarContext calendar = ScheduleCalendarContext.none,
}) {
  final effects = calendar.effects;
  return [
    for (var day = 0; day < scheduleDayNames.length; day++)
      _planOf(
        dayIndex: day,
        week: week,
        date: weekMonday?.add(Duration(days: day)),
        effects: effects,
      ),
  ];
}

ScheduleDayPlan _planOf({
  required int dayIndex,
  required int? week,
  required DateTime? date,
  required CalendarDayEffectIndex? effects,
}) {
  if (week == null || date == null || effects == null) {
    return ScheduleDayPlan(dayIndex: dayIndex, date: date, week: week);
  }
  final effect = effects.effectOf(date);
  return ScheduleDayPlan(
    dayIndex: dayIndex,
    date: date,
    week: week,
    effect: effect.kind,
    effectLabel: effect.badge,
    sourceHint: effect.sourceText,
    sourceWeek: effect.sourceWeek,
    sourceDayIndex: effect.sourceWeekday == null
        ? null
        : effect.sourceWeekday! - 1,
  );
}

/// 某一天（含校历效应与调课）实际要上的课，按节次排序。
///
/// 与 `effectiveClassesOfDay`（只按星期过滤）的区别：这个认校历 —— 假期只剩
/// 「搬到这一天」的课，补课日改取被补那一周那一星期的课。首页今日课程、
/// 实况窗、课前提醒都走它。
List<EffectiveClass> effectiveClassesOfDate({
  required List<ScheduleEntry> entries,
  required List<Reschedule> reschedules,
  required int week,
  required DateTime date,
  ScheduleCalendarContext calendar = ScheduleCalendarContext.none,
}) {
  final day = DateTime(date.year, date.month, date.day);
  final plan = _planOf(
    dayIndex: day.weekday - 1,
    week: week,
    date: day,
    effects: calendar.effects,
  );
  final out = _classesForPlan(
    plan,
    week: week,
    weekClasses: (w) =>
        effectiveClasses(entries: entries, reschedules: reschedules, week: w),
  ).toList();
  out.sort((a, b) {
    if (a.startPeriod != b.startPeriod) {
      return a.startPeriod.compareTo(b.startPeriod);
    }
    return a.courseName.compareTo(b.courseName);
  });
  return out;
}

/// 本次展示范围里**真的有课**的星期（0 = 周一）——隐藏周六 / 周日的判据。
///
/// ⚠ **视图侧的调用点由页面统一负责**：`schedule_screen.dart` 按「**已落定的那一周**」
/// （`_layoutWeek`，分页器停稳才更新）算好，再通过 `visibleDays:` 传给两个视图 ——
/// 分页器的静态表头与相邻页共用同一份列集合，判据若跟着「正在看第几周」逐页变，
/// 翻页途中列数就会 6↔5、列宽重排（用户 2026-10-08：「一旦切换周数时，起点或终点
/// 是本周，就会动画错乱」）。所以：
///
/// - [week] 非空 = **只看这一周**（用户原话「如果某周周 x 有课…此时这天还是显示的」
///   → 第 5 周周六是补课日就显示，其它周该收就收）；
/// - [week] 为空 = **整学期**：有日期与校历时**逐周扫过整学期**，
///   「周六只有国庆那几周有课」算有课、「周六的课全落在假期里」算没课；拿不到日期
///   （历史学期 / 离线）时退化为模板列本身（= 任意一周有课就算有课）。
Set<int> scheduleDaysWithClass({
  required List<ScheduleEntry> entries,
  List<Reschedule> reschedules = const <Reschedule>[],
  int? week,
  DateTime? weekMonday,
  ScheduleCalendarContext calendar = ScheduleCalendarContext.none,
}) {
  final out = <int>{};

  void collect(int? w, DateTime? monday) {
    for (final c in scheduleBoardColumns(
      entries: entries,
      reschedules: reschedules,
      week: w,
      weekMonday: monday,
      calendar: calendar,
    )) {
      if (c.hasClass) out.add(c.dayIndex);
    }
  }

  if (week != null) {
    collect(week, weekMonday);
    return out;
  }

  final anchor = weekMonday ?? calendar.termFirstMonday;
  if (anchor == null || calendar.effects == null) {
    collect(null, null);
    return out;
  }
  for (var w = 1; w <= calendar.lastWeek; w++) {
    collect(w, anchor.add(Duration(days: (w - 1) * 7)));
  }
  return out;
}
