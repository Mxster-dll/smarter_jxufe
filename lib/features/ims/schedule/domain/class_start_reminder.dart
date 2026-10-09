/// 课前提醒（上课前 X 分钟起、到上课时消失的常驻通知）的领域口径。
///
/// 用户 2026-09-22 原话：「我希望在任何一节课上课前x分钟(x可设置，默认30）到上课前，
/// 移动端显示一个常驻通知，下节课的名称和教室」。
///
/// 口径（改动前先读）：
/// - 每条日程（[sessionsOfDay] 的输出）排 **1 条**通知，触发时刻 = 上课时刻 − 提前量 X；
/// - 通知**常驻到上课那一刻**：Android 侧用 `ongoing: true` + `timeoutAfter: X`，
///   到点由系统自动撤下 —— App 不必常驻，也不必再排一条「撤销」；
/// - 已经进入窗口（`now >= 上课时刻 − X`，例如用户刚打开 App）时**不补历史**：
///   把触发时刻夹到「现在 + [classReminderMinLead]」，撤下时长改成到上课那一刻
///   （夹完若是空窗就整条丢掉），这样用户仍能看到这条提醒；
/// - **停课的日程不排**（与实况窗同口径：停课不参与「下一节」）；
/// - 跨天按「周一对齐」推进教学周（[teachingWeekOfDay]），否则第 7 天起会算错周次；
/// - 预排未来 [classReminderHorizonDays] 天、上限 [classReminderMaxScheduled] 条，
///   数据变动 / 回前台整段重排（幂等，见 `data/class_reminder_sync.dart`）。
///
/// 本文件**无 IO、无 Flutter 依赖**（只用 `@immutable`），便于单测。
library;

import 'package:flutter/foundation.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/live_session.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_board.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/shared/services/notification_service.dart';

/// 通知 id 区间起点。
///
/// 实况窗固定 8801、截止提醒 920000 起（[geDeadlineNotifyIdBase]），本模块从
/// 940000 起，互不重叠。
const int classStartNotifyIdBase = 940000;

/// id 区间长度（同时也是一次重排最多占用的 id 数）。
const int classStartNotifyIdSpan = 1000;

/// 单次最多排期条数（一周的课远小于它；防脏数据刷爆系统闹钟）。
const int classReminderMaxScheduled = 60;

/// 预排未来的天数（一周足够：每次回前台 / 数据变动都会整段重排）。
const int classReminderHorizonDays = 7;

/// 默认提前量：30 分钟（用户原话「默认30」）。
const int classReminderDefaultLeadMinutes = 30;

/// 设置页可选的提前量（分钟）。
const List<int> classReminderLeadOptions = <int>[5, 10, 15, 20, 30, 45, 60];

/// 提前量下限 / 上限（脏存档夹紧用）。
const int classReminderMinLeadMinutes = 1;
const int classReminderMaxLeadMinutes = 120;

/// 触发时刻至少要晚于「现在」这么久，否则夹到此刻（防止一进 App 就弹一串）。
const Duration classReminderMinLead = Duration(seconds: 20);

/// id 是否落在本模块区间内。
bool classStartIdInRange(int id) =>
    id >= classStartNotifyIdBase &&
    id < classStartNotifyIdBase + classStartNotifyIdSpan;

/// 把提前量夹进 [classReminderMinLeadMinutes]–[classReminderMaxLeadMinutes]。
int clampClassReminderLead(int minutes) {
  if (minutes < classReminderMinLeadMinutes) return classReminderMinLeadMinutes;
  if (minutes > classReminderMaxLeadMinutes) return classReminderMaxLeadMinutes;
  return minutes;
}

/// 提前量的中文文案：「提前 30 分钟」「提前 1 小时」。
String classReminderLeadLabel(int minutes) => minutes >= 60 && minutes % 60 == 0
    ? '提前 ${minutes ~/ 60} 小时'
    : '提前 $minutes 分钟';

/// [day] 当天所处的教学周（以**周一**对齐推进，跨周才 +1）。
///
/// 直接 `teachingWeek + offsetDays ~/ 7` 是错的：那样周日晚上看「下周一」的课
/// 会多算一周（周一与周日在同一 `offset ~/ 7` 桶里）。这里按两个日期各自的
/// 周一相差几周来算。
int teachingWeekOfDay({
  required DateTime now,
  required int teachingWeek,
  required DateTime day,
}) {
  final mondayOfNow = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  final mondayOfDay = DateTime(
    day.year,
    day.month,
    day.day,
  ).subtract(Duration(days: day.weekday - 1));
  return teachingWeek + mondayOfDay.difference(mondayOfNow).inDays ~/ 7;
}

/// 一条待排的课前提醒（纯数据，便于测试与对账）。
@immutable
class ClassStartReminder {
  const ClassStartReminder({
    required this.id,
    required this.courseName,
    required this.classroom,
    required this.campus,
    required this.periodLabel,
    required this.clockLabel,
    required this.startAt,
    required this.when,
    required this.dismissAfter,
    required this.lead,
  });

  /// 系统通知 id（[classStartNotifyIdBase] + 序号）。
  final int id;

  /// 课程名称。
  final String courseName;

  /// 教室（用户要求显示的第二个信息）。
  final String classroom;

  /// 校区（有才显示）。
  final String? campus;

  /// 节次文案，如「第3-4节」。
  final String periodLabel;

  /// 时间文案，如「09:55-11:30」。
  final String clockLabel;

  /// 上课时刻。
  final DateTime startAt;

  /// 通知触发时刻。
  final DateTime when;

  /// 常驻多久后自动撤下（= 到上课那一刻）。
  final Duration dismissAfter;

  /// 配置的提前量（用于文案与对账）。
  final Duration lead;

  /// 通知标题：「即将上课 · 高等数学」。
  String get title => '即将上课 · $courseName';

  /// 通知正文：「麦三教3407 · 麦庐园校区 · 第3-4节 09:55-11:30」。
  String get body {
    final parts = <String>[
      if (classroom.isNotEmpty) classroom,
      if (campus != null && campus!.isNotEmpty) campus!,
      '$periodLabel $clockLabel',
    ];
    return parts.join(' · ');
  }

  /// 排期负载：对账用（触发时刻 + 内容指纹 + 常驻时长）。
  String get payload => classStartReminderPayload(
    when: when,
    courseName: courseName,
    classroom: classroom,
    dismissAfter: dismissAfter,
  );

  @override
  bool operator ==(Object other) =>
      other is ClassStartReminder &&
      other.id == id &&
      other.courseName == courseName &&
      other.classroom == classroom &&
      other.campus == campus &&
      other.periodLabel == periodLabel &&
      other.clockLabel == clockLabel &&
      other.startAt == startAt &&
      other.when == when &&
      other.dismissAfter == dismissAfter &&
      other.lead == lead;

  @override
  int get hashCode => Object.hash(
    id,
    courseName,
    classroom,
    campus,
    periodLabel,
    clockLabel,
    startAt,
    when,
    dismissAfter,
    lead,
  );

  @override
  String toString() =>
      'ClassStartReminder(#$id $when → ${startAt.toIso8601String()} '
      '$courseName @$classroom, 常驻 ${dismissAfter.inMinutes} 分钟)';
}

/// 排期负载字符串（唯一出处；[ClassStartReminder.payload] 与对账都用它）。
String classStartReminderPayload({
  required DateTime when,
  required String courseName,
  required String classroom,
  required Duration dismissAfter,
}) =>
    '${when.millisecondsSinceEpoch}|$courseName|$classroom'
    '|${dismissAfter.inSeconds}';

/// 收集「未来 [days] 天内每节课」的课前提醒（纯函数；[now] 注入便于测试）。
///
/// 排序：触发时刻 → 课程名 → 上课时刻（稳定，便于 id 分配与对账）。
///
/// [calendar] 为校历上下文（假期 / 补课，用户 2026-10-07）：假期当天不排提醒、
/// 补课日按被补那天的课表排（与课表页、实况窗同源 —— 三处必须是同一个答案，
/// 否则会出现「课表显示放假、手机却提醒去上课」）。
List<ClassStartReminder> classStartRemindersFor({
  required List<ScheduleEntry> entries,
  required PeriodTable table,
  required int teachingWeek,
  required DateTime now,
  required Duration lead,
  List<Reschedule> reschedules = const <Reschedule>[],
  int days = classReminderHorizonDays,
  int max = classReminderMaxScheduled,
  Duration minLead = classReminderMinLead,
  ScheduleCalendarContext calendar = ScheduleCalendarContext.none,
}) {
  final base = DateTime(now.year, now.month, now.day);
  final earliest = now.add(minLead);
  final drafts = <ClassStartReminder>[];
  var seq = 0;

  for (var d = 0; d < days; d++) {
    final day = base.add(Duration(days: d));
    // 跨天按「周一对齐」推进教学周（[teachingWeekOfDay]）。
    var week = teachingWeekOfDay(
      now: now,
      teachingWeek: teachingWeek,
      day: day,
    );
    // 校历效应里的周次比「按周推」更权威（补课日可能跨到别的周上课）；
    // 拿不到就沿用按周推的结果。
    if (calendar.effects != null) {
      week = calendar.effects!.weekOf(day) ?? week;
    }
    final sessions = sessionsOfDay(
      entries: entries,
      table: table,
      teachingWeek: week,
      day: day,
      reschedules: reschedules,
      calendar: calendar,
    );
    for (final s in sessions) {
      // 停课不提醒（与实况窗「下一节」同口径）。
      if (s.isCancelled) continue;
      // 已经开始的课不排。
      if (!s.startAt.isAfter(now)) continue;

      var when = s.startAt.subtract(lead);
      var dismissAfter = lead;
      if (!when.isAfter(earliest)) {
        // 已进入窗口（用户刚打开 App）：夹到此刻，常驻到上课那一刻。
        when = earliest;
        dismissAfter = s.startAt.difference(when);
      }
      if (dismissAfter <= Duration.zero) continue;

      drafts.add(
        ClassStartReminder(
          // id 先占位，排序后统一分配。
          id: classStartNotifyIdBase + seq++,
          courseName: s.courseName,
          classroom: s.classroom,
          campus: s.campus,
          periodLabel: s.periodLabel,
          clockLabel: s.clockLabel,
          startAt: s.startAt,
          when: when,
          dismissAfter: dismissAfter,
          lead: lead,
        ),
      );
    }
  }

  drafts.sort((a, b) {
    final byWhen = a.when.compareTo(b.when);
    if (byWhen != 0) return byWhen;
    final byName = a.courseName.compareTo(b.courseName);
    if (byName != 0) return byName;
    return a.startAt.compareTo(b.startAt);
  });

  final out = <ClassStartReminder>[];
  final seen = <String>{};
  for (final r in drafts) {
    // 同一节课重复解析（同一门课多个重叠时段 / 调课记录重复）只排一条。
    if (!seen.add('${r.courseName}@${r.startAt.toIso8601String()}@${r.classroom}')) {
      continue;
    }
    if (out.length >= max) break;
    out.add(
      ClassStartReminder(
        id: classStartNotifyIdBase + out.length,
        courseName: r.courseName,
        classroom: r.classroom,
        campus: r.campus,
        periodLabel: r.periodLabel,
        clockLabel: r.clockLabel,
        startAt: r.startAt,
        when: r.when,
        dismissAfter: r.dismissAfter,
        lead: r.lead,
      ),
    );
  }
  return out;
}

/// 期望排期与系统现有排期是否一致（用 payload 对账，见 [classStartReminderPayload]）。
bool classStartScheduleMatches({
  required List<ClassStartReminder> desired,
  required List<ScheduledNotificationInfo> pending,
}) {
  final current = <int, String>{};
  for (final p in pending) {
    if (!classStartIdInRange(p.id)) continue;
    current[p.id] = p.payload ?? '';
  }
  if (current.length != desired.length) return false;
  for (final r in desired) {
    if (current[r.id] != r.payload) return false;
  }
  return true;
}
