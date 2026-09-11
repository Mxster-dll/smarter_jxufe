/// 「上课中 / 下一节课」实况窗的状态机。
///
/// 纯粹的领域逻辑：输入课表 + 作息表 + 教学周 + 当前时刻，输出此刻该显示的
/// 实况窗状态。**无 IO、无 Flutter 依赖**，便于单测。
///
/// 三种状态构成一个回路：`LiveInClass`（上课中）→ 下课后变为
/// `LiveUpcoming`（下一节）或 `LiveIdle`（今日无更多课）。
library;

import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';

/// 一节课的完整日程：课程信息 + 时段 + 推算出的起止时刻。
class ScheduledSession {
  final ScheduleEntry entry;
  final ClassTime classTime;

  /// 该次课当天的开始时刻（由 [PeriodTable] 推算）。
  final DateTime startAt;

  /// 该次课当天的结束时刻。
  final DateTime endAt;

  /// 调课后的任课教师（null = 用课表原教师）。
  final String? teacherOverride;

  /// 调课标记（原课表原样时为 [EffectiveMark.normal]）。
  final EffectiveMark mark;

  /// 来源调课记录（无调课时为 null）。
  final Reschedule? reschedule;

  const ScheduledSession({
    required this.entry,
    required this.classTime,
    required this.startAt,
    required this.endAt,
    this.teacherOverride,
    this.mark = EffectiveMark.normal,
    this.reschedule,
  });

  String get courseName => entry.courseName;

  /// 生效后的任课教师（调课换了老师时给出新老师）。
  String get teacherName => teacherOverride ?? entry.teacherName;

  /// 是否停课（不参与「上课中 / 下一节」，但仍在今日列表里显示）。
  bool get isCancelled => mark == EffectiveMark.cancelled;

  /// 是否因调课改变（调课或补课）。
  bool get isRescheduled =>
      mark == EffectiveMark.moved || mark == EffectiveMark.extra;

  String get classroom => classTime.classroom;

  String? get campus => classTime.campus;

  int get startPeriod => classTime.startPeriod;

  int get endPeriod => classTime.endPeriod;

  /// 如「第3-4节」；单节时为「第3节」。
  String get periodLabel => startPeriod == endPeriod
      ? '第$startPeriod节'
      : '第$startPeriod-$endPeriod节';

  /// 如「09:55-11:30」。
  String get clockLabel => '${formatHhmm(startAt)}-${formatHhmm(endAt)}';

  /// 这条日程的周次描述，如「1-16周(单)」。
  String get weekLabel => classTime.fullWeekText;

  Duration get duration => endAt.difference(startAt);

  /// [now] 时刻是否处于本节课内。
  bool isInClassAt(DateTime now) =>
      !now.isBefore(startAt) && now.isBefore(endAt);

  /// 距下课还有多久（已下课返回 [Duration.zero]）。
  Duration remainingAt(DateTime now) {
    final d = endAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  /// 距上课还有多久（已上课返回 [Duration.zero]）。
  Duration untilStartAt(DateTime now) {
    final d = startAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  /// 已上课比例 0.0–1.0（用于通知进度条）。
  double progressAt(DateTime now) {
    final total = duration.inSeconds;
    if (total <= 0) return 1;
    final elapsed = now.difference(startAt).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  /// 已上课分钟数与总分钟数（`showProgress` 用）。
  (int elapsed, int total) progressMinutesAt(DateTime now) {
    final total = duration.inMinutes;
    final elapsed = now.difference(startAt).inMinutes.clamp(0, total);
    return (elapsed, total);
  }

  @override
  String toString() =>
      'ScheduledSession($courseName $periodLabel $clockLabel @$classroom)';
}

/// 实况窗状态。
sealed class LiveSession {
  const LiveSession();
}

/// 正在上课。
class LiveInClass extends LiveSession {
  final ScheduledSession session;

  /// 紧接着的下一节课（今天还有的话），供展开态显示。
  final ScheduledSession? next;

  const LiveInClass(this.session, {this.next});
}

/// 下一节课尚未开始。
class LiveUpcoming extends LiveSession {
  final ScheduledSession session;

  const LiveUpcoming(this.session);
}

/// 今天已无更多课程。
class LiveIdle extends LiveSession {
  /// 今天的全部课程（含已结束的），供界面展示。
  final List<ScheduledSession> todaySessions;

  const LiveIdle(this.todaySessions);
}

/// 判断某个 [ClassTime] 在指定的教学周是否成立（周次区间 + 单双周）。
///
/// 实现已下沉到 [ClassTime.appliesInWeek]，此处保留旧签名以免改动既有调用方。
bool classTimeAppliesInWeek(ClassTime ct, int week) => ct.appliesInWeek(week);

/// 取 [day] 当天的全部课程，按开始时刻升序。
///
/// [teachingWeek] 为 0（开学前）时天然返回空列表，因为课表的周次从 1 起。
/// [reschedules] 为本地调课记录：调课/停课/补课在此一次性生效，
/// 因而实况窗、通知、今日课程与课表页看到的永远是同一份安排。
List<ScheduledSession> sessionsOfDay({
  required List<ScheduleEntry> entries,
  required PeriodTable table,
  required int teachingWeek,
  required DateTime day,
  List<Reschedule> reschedules = const [],
}) {
  final out = <ScheduledSession>[];

  final classes = effectiveClassesOfDay(
    entries: entries,
    reschedules: reschedules,
    week: teachingWeek,
    day: day,
  );

  for (final c in classes) {
    // 「已调走」占位不属于当天——课已经挪到别的时段了
    if (c.isMovedAway) continue;

    final span = table.span(
      day,
      c.classTime.startPeriod,
      c.classTime.endPeriod,
    );
    final start = span.start;
    final end = span.end;
    // 作息表缺该节次时跳过——宁可不显示，也不给出错误的倒计时
    if (start == null || end == null) continue;

    out.add(
      ScheduledSession(
        entry: c.entry,
        classTime: c.classTime,
        startAt: start,
        endAt: end,
        teacherOverride: c.teacherOverride,
        mark: c.mark,
        reschedule: c.reschedule,
      ),
    );
  }
  out.sort((a, b) => a.startAt.compareTo(b.startAt));
  return out;
}

/// 解析此刻的实况窗状态。
///
/// 依次判定：① 有课正在进行 → [LiveInClass]；② 稍后还有课 → [LiveUpcoming]；
/// ③ 今天没课了 → [LiveIdle]。
///
/// 停课的课不参与①②（不会推送「下一节」提醒），但仍留在 [LiveIdle] 的
/// 今日列表里，界面上以「停课」标出。
LiveSession resolveLiveSession({
  required List<ScheduleEntry> entries,
  required PeriodTable table,
  required int teachingWeek,
  required DateTime now,
  List<Reschedule> reschedules = const [],
}) {
  final today = sessionsOfDay(
    entries: entries,
    table: table,
    teachingWeek: teachingWeek,
    day: now,
    reschedules: reschedules,
  );
  final live = today.where((s) => !s.isCancelled).toList();

  // ① 上课中（可能有多节重叠，取最先开始的那节）
  for (var i = 0; i < live.length; i++) {
    final s = live[i];
    if (s.isInClassAt(now)) {
      final next = i + 1 < live.length ? live[i + 1] : null;
      return LiveInClass(s, next: next);
    }
  }

  // ② 下一节课
  for (final s in live) {
    if (s.startAt.isAfter(now)) return LiveUpcoming(s);
  }

  // ③ 今日无更多课
  return LiveIdle(today);
}

/// `DateTime` → `HH:mm`。
String formatHhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// `Duration` → 人类可读的倒计时文本，如「23 分钟」「1 小时 5 分钟」。
String formatCountdown(Duration d) {
  if (d.inSeconds <= 0) return '已结束';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h <= 0) return '$m 分钟';
  if (m == 0) return '$h 小时';
  return '$h 小时 $m 分钟';
}

/// 实况窗的稳定标识：同一节课的同一状态返回相同 key。
///
/// 界面层用它做**通知去重**——每秒重算状态，但只在 key 变化时才真正推送。
String liveSessionKey(LiveSession session) => switch (session) {
  LiveInClass(:final session) =>
    'in:${session.entry.courseCode}@${session.startAt.toIso8601String()}',
  LiveUpcoming(:final session) =>
    'up:${session.entry.courseCode}@${session.startAt.toIso8601String()}',
  LiveIdle() => 'idle',
};

/// 实况窗通知的内容描述。[LiveIdle] 返回 null（此时应撤销通知）。
class LiveNotificationContent {
  /// 通知标题，如「高等数学 · 麦三教3407」。
  final String title;

  /// 通知副标题，如「09:55-11:30 第3-4节」。
  final String body;

  /// 系统计时器目标时刻（下一节课开始 / 本节课结束）。
  final DateTime countdownTo;

  /// 已上课分钟数。
  final int elapsedMinutes;

  /// 本节课总分钟数。
  final int totalMinutes;

  const LiveNotificationContent({
    required this.title,
    required this.body,
    required this.countdownTo,
    required this.elapsedMinutes,
    required this.totalMinutes,
  });
}

/// 由实况窗状态构造通知内容；[LiveIdle] 返回 null。
LiveNotificationContent? liveNotificationContent(
  LiveSession state,
  DateTime now,
) => switch (state) {
  LiveInClass(:final session) => LiveNotificationContent(
    title:
        '${session.courseName} · ${session.classroom}'
        '${session.isRescheduled ? '（调课）' : ''}',
    body:
        '上课中 · ${session.periodLabel} ${session.clockLabel}'
        ' · 距下课 ${formatCountdown(session.remainingAt(now))}',
    countdownTo: session.endAt,
    elapsedMinutes: session.progressMinutesAt(now).$1,
    totalMinutes: session.progressMinutesAt(now).$2,
  ),
  LiveUpcoming(:final session) => LiveNotificationContent(
    title:
        '下一节 ${formatHhmm(session.startAt)} · ${session.courseName}'
        '${session.isRescheduled ? '（调课）' : ''}',
    body:
        '${session.classroom}'
        '${session.campus == null ? '' : ' · ${session.campus}'}'
        ' · ${session.periodLabel} · ${formatCountdown(session.untilStartAt(now))}后开始',
    countdownTo: session.startAt,
    elapsedMinutes: 0,
    totalMinutes: 0,
  ),
  LiveIdle() => null,
};
