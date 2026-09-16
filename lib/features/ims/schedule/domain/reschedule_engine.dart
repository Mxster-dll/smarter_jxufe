/// 调课覆盖层的应用引擎。
///
/// 纯领域逻辑：输入「教务课表 + 调课记录 + 教学周」，输出**生效后的课节**。
/// 无 IO、无 Flutter 依赖，便于单测。
///
/// 课表网格、横版列表、实况窗、通知、今日课程全部走这里，
/// 保证「App 说的时间地点」在四处完全一致。
library;

import 'package:collection/collection.dart';

import 'class_time.dart';
import 'reschedule.dart';
import 'schedule_entry.dart';

/// 一节课在界面上的标记语义。
enum EffectiveMark {
  /// 原课表原样。
  normal,

  /// 被调课搬到此处（显示「调」角标）。
  moved,

  /// 原位残留的「已调走」占位（提示这门课为什么不在原时段）。
  movedAway,

  /// 停课占位。
  cancelled,

  /// 补课（原课表没有这一次）。
  extra,
}

/// 应用调课覆盖层之后的一节课。
class EffectiveClass {
  /// 所属课表条目；补课时为按记录合成的条目（见 [extraEntryFor]）。
  final ScheduleEntry entry;

  /// 生效后的时段（含周次区间与教室/校区）。
  final ClassTime classTime;

  final EffectiveMark mark;

  /// 覆盖后的任课教师（null = 用 [ScheduleEntry.teacherName]）。
  final String? teacherOverride;

  /// 来源调课记录；[EffectiveMark.normal] 时为 null。
  final Reschedule? reschedule;

  const EffectiveClass({
    required this.entry,
    required this.classTime,
    this.mark = EffectiveMark.normal,
    this.teacherOverride,
    this.reschedule,
  });

  String get courseCode => entry.courseCode;

  String get courseName => entry.courseName;

  String get teacherName => teacherOverride ?? entry.teacherName;

  String get classroom => classTime.classroom;

  String? get campus => classTime.campus;

  bool get isCancelled => mark == EffectiveMark.cancelled;

  bool get isMovedAway => mark == EffectiveMark.movedAway;

  bool get isExtra => mark == EffectiveMark.extra;

  /// 是否属于「因调课而改变时间/地点」的课（补课也算）。
  bool get isRescheduled =>
      mark == EffectiveMark.moved || mark == EffectiveMark.extra;

  /// 是否参与实况窗/通知（停课与「已调走」占位都不参与）。
  bool get isLive =>
      mark != EffectiveMark.cancelled && mark != EffectiveMark.movedAway;

  /// 星期几（1 = 周一）。
  int get dayIndex => classTime.dayOfWeek.dayIndex;

  int get startPeriod => classTime.startPeriod;

  int get endPeriod => classTime.endPeriod;

  String get periodText => periodRangeText(startPeriod, endPeriod);

  @override
  String toString() =>
      'EffectiveClass(${mark.name} $courseName $periodText @$classroom)';
}

/// 计算生效课节。
///
/// - [week] 为具体教学周 → 单次调课与长期调课**都**生效（周视图）；
/// - [week] 为 null → 整学期模板视图：只应用长期调课，忽略单次调课与补课
///   （单次调课的位置用 [onceMarksBySlot] 出角标提示）。
///
/// 停课 → 原时段留一个 [EffectiveMark.cancelled] 占位；
/// 调课 → 原时段留 [EffectiveMark.movedAway] 占位 + 目标时段出 [EffectiveMark.moved]。
List<EffectiveClass> effectiveClasses({
  required List<ScheduleEntry> entries,
  required List<Reschedule> reschedules,
  int? week,
}) {
  final out = <EffectiveClass>[];

  for (final entry in entries) {
    for (final ct in entry.classTimes) {
      if (week != null && !ct.appliesInWeek(week)) continue;

      final hits = <Reschedule>[];
      for (final r in reschedules) {
        if (r.isExtra) continue;
        if (!coversCourse(r, entry)) continue;
        if (!r.matchesOriginSlot(ct)) continue;
        // 整学期视图只认长期调课；单次调课的位置改由 onceMarksBySlot 出角标
        if (week == null && r.isOnce) continue;
        if (week != null && !r.appliesInWeek(week)) continue;
        hits.add(r);
      }

      // 停课优先于调课（同一次课既有停课又有调课时，以停课为准）
      final cancel = hits.firstWhereOrNull((r) => r.isCancel);
      if (cancel != null) {
        out.add(
          EffectiveClass(
            entry: entry,
            classTime: ct,
            mark: EffectiveMark.cancelled,
            reschedule: cancel,
          ),
        );
        continue;
      }

      final move = hits.firstWhereOrNull((r) => r.isMove);
      if (move != null) {
        out.add(
          EffectiveClass(
            entry: entry,
            classTime: ct,
            mark: EffectiveMark.movedAway,
            reschedule: move,
          ),
        );
        out.add(
          EffectiveClass(
            entry: entry,
            classTime: movedTimeFor(move, origin: ct, week: week),
            mark: EffectiveMark.moved,
            teacherOverride: move.newTeacher,
            reschedule: move,
          ),
        );
        continue;
      }

      out.add(EffectiveClass(entry: entry, classTime: ct));
    }
  }

  // 补课：只在周视图出现（模板视图没有「哪一周」的概念）
  if (week != null) {
    for (final r in reschedules) {
      if (!r.isExtra || !r.appliesInWeek(week)) continue;
      out.add(
        EffectiveClass(
          entry: extraEntryFor(r),
          classTime: extraTimeFor(r, week),
          mark: EffectiveMark.extra,
          teacherOverride: r.newTeacher,
          reschedule: r,
        ),
      );
    }
  }

  out.sort((a, b) {
    if (a.dayIndex != b.dayIndex) return a.dayIndex.compareTo(b.dayIndex);
    if (a.startPeriod != b.startPeriod) {
      return a.startPeriod.compareTo(b.startPeriod);
    }
    return a.courseName.compareTo(b.courseName);
  });
  return out;
}

/// [day] 当天生效的课节。
List<EffectiveClass> effectiveClassesOfDay({
  required List<ScheduleEntry> entries,
  required List<Reschedule> reschedules,
  required int week,
  required DateTime day,
}) => effectiveClasses(
  entries: entries,
  reschedules: reschedules,
  week: week,
).where((c) => c.dayIndex == day.weekday).toList();

/// 原课位标识：课程代码 + 星期 + 首末节次。
String classSlotKey(String courseCode, ClassTime ct) =>
    '${courseCode.trim().toLowerCase()}'
    '|${ct.dayOfWeek.name}|${ct.startPeriod}|${ct.endPeriod}';

/// 整学期视图的单次调课角标：原课位 → 该课位上的单次记录数。
Map<String, int> onceMarksBySlot(List<Reschedule> reschedules) {
  final out = <String, int>{};
  for (final r in reschedules) {
    if (r.isExtra || !r.isOnce) continue;
    final d = r.originDay;
    final s = r.originStartPeriod;
    final e = r.originEndPeriod;
    if (d == null || s == null || e == null || r.courseCode.isEmpty) continue;
    final key = '${r.courseCode.trim().toLowerCase()}|${d.name}|$s|$e';
    out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

/// [r] 是否覆盖课表条目 [e]（课程代码 + 上课班代码）。
bool coversCourse(Reschedule r, ScheduleEntry e) {
  if (r.courseCode.isEmpty) return false;
  if (r.courseCode.trim().toLowerCase() != e.courseCode.trim().toLowerCase()) {
    return false;
  }
  // 上课班代码只在两边都有时才比对（旧缓存可能没有）
  if (r.classCode.isNotEmpty &&
      e.classCode.isNotEmpty &&
      r.classCode != e.classCode) {
    return false;
  }
  return true;
}

/// 调课后的时段。
///
/// - 单次：`[week, week]`、去掉单双周（就是这一周）；
/// - 长期：周次区间从生效周起接到原结束周，单双周沿用原课。
ClassTime movedTimeFor(Reschedule r, {required ClassTime origin, int? week}) {
  final day = r.targetDay ?? origin.dayOfWeek;
  final sp = r.targetStartPeriod ?? origin.startPeriod;
  final ep = r.targetEndPeriod ?? origin.endPeriod;
  final room = r.targetClassroom.isEmpty ? origin.classroom : r.targetClassroom;
  final campus = r.targetCampus ?? origin.campus;

  if (r.isOnce) {
    final w = week ?? r.week;
    return ClassTime(
      startWeek: w,
      endWeek: w,
      weekParity: WeekParity.every,
      dayOfWeek: day,
      startPeriod: sp,
      endPeriod: ep,
      classroom: room,
      campus: campus,
    );
  }

  final start = r.week > origin.startWeek ? r.week : origin.startWeek;
  final end = origin.endWeek < start ? start : origin.endWeek;
  return ClassTime(
    startWeek: start,
    endWeek: end,
    weekParity: origin.weekParity,
    dayOfWeek: day,
    startPeriod: sp,
    endPeriod: ep,
    classroom: room,
    campus: campus,
  );
}

/// 补课记录对应的时段（只存在于 [week] 这一周）。
ClassTime extraTimeFor(Reschedule r, int week) {
  final sp = r.targetStartPeriod ?? 1;
  return ClassTime(
    startWeek: week,
    endWeek: week,
    weekParity: WeekParity.every,
    dayOfWeek: r.targetDay ?? DayOfWeek.monday,
    startPeriod: sp,
    endPeriod: r.targetEndPeriod ?? sp,
    classroom: r.targetClassroom.isEmpty ? '教室待定' : r.targetClassroom,
    campus: r.targetCampus,
  );
}

/// 按补课记录合成一条课表条目（用于课名、颜色、教师显示）。
ScheduleEntry extraEntryFor(Reschedule r) {
  final code = r.courseCode.isEmpty ? 'extra-${r.id}' : r.courseCode;
  return ScheduleEntry(
    classCode: r.classCode.isEmpty ? 'extra-${r.id}' : r.classCode,
    className: '',
    courseCode: code,
    courseName: r.courseName,
    totalHours: 0,
    credits: 0,
    studyNature: '',
    teacherCode: '',
    teacherName: r.originTeacher,
    selectionStatus: '',
    isCrossMajor: false,
    hasTextbook: false,
    classTimes: const [],
    remark: r.note.isEmpty ? null : r.note,
  );
}
