/// 调课记录 —— 叠在教务课表之上的一层**本地覆盖**。
///
/// 教务系统没有个人调课接口（只有全校性的教学周调整），所以临时调课、
/// 停课、补课都由用户手工录入，存本地 Hive，**不修改教务课表缓存本身**：
/// 教务刷新、换学期、缓存重建都不会破坏这层记录。
///
/// ## 定位原课的方式
/// 「课程代码 + 上课班代码 + 星期 + 首末节次」，**刻意不含教室与周次区间** ——
/// 教务刷新后换教室、或同一门课存在多种周次区间（1-8 周 / 9-16 周）时，
/// 记录仍然对得上。
///
/// ## 两种生效范围
/// - [RescheduleScope.once]：只作用于 [week] 这一教学周（「第 10 周周三这次」）；
/// - [RescheduleScope.recurring]：从 [week] 起每周生效（「第 10 周起一直换到新楼」）。
library;

import 'class_time.dart';

/// 调课类型。
enum RescheduleKind {
  /// 改时间 / 地点 / 教师。
  move('调课'),

  /// 停课（这一次不上）。
  cancel('停课'),

  /// 补课（原课表之外额外加的一次课）。
  extra('补课');

  final String label;

  const RescheduleKind(this.label);

  /// 格子上角标用的单字。
  String get badge => switch (this) {
    RescheduleKind.move => '调',
    RescheduleKind.cancel => '停',
    RescheduleKind.extra => '补',
  };

  static RescheduleKind byName(Object? name) {
    for (final k in RescheduleKind.values) {
      if (k.name == name) return k;
    }
    return RescheduleKind.move;
  }
}

/// 生效范围。
enum RescheduleScope {
  /// 仅 [Reschedule.week] 这一教学周。
  once('仅一次'),

  /// 从 [Reschedule.week] 起每周生效。
  recurring('长期');

  final String label;

  const RescheduleScope(this.label);

  static RescheduleScope byName(Object? name) {
    for (final s in RescheduleScope.values) {
      if (s.name == name) return s;
    }
    return RescheduleScope.once;
  }
}

/// 一条调课记录（immutable）。
class Reschedule {
  /// 稳定标识（uuid），编辑/删除按它定位。
  final String id;

  final RescheduleKind kind;
  final RescheduleScope scope;

  /// 生效教学周：`once` 取该周；`recurring` 取起始周（含）。
  final int week;

  // ── 原课定位（[RescheduleKind.extra] 时只有课名/教师有意义）

  /// 课程代码；补课时可为空串。
  final String courseCode;

  /// 课程名称（冗余存一份：课表缓存换学期后仍能显示）。
  final String courseName;

  /// 上课班代码，如 `001567-056`。
  final String classCode;

  /// 原任课教师（显示用，也是「不改教师」时的取值）。
  final String originTeacher;

  /// 原上课星期几；补课时为 null。
  final DayOfWeek? originDay;

  /// 原起始节次；补课时为 null。
  final int? originStartPeriod;

  /// 原结束节次；补课时为 null。
  final int? originEndPeriod;

  /// 原教室（仅展示，不参与匹配）。
  final String originClassroom;

  // ── 调整后（[RescheduleKind.move] / [RescheduleKind.extra]）

  /// 目标星期几。
  final DayOfWeek? targetDay;

  /// 目标起始节次。
  final int? targetStartPeriod;

  /// 目标结束节次。
  final int? targetEndPeriod;

  /// 目标教室；空串表示「沿用原教室」（补课时显示「教室待定」）。
  final String targetClassroom;

  /// 目标校区。
  final String? targetCampus;

  /// 覆盖任课教师（null = 沿用 [originTeacher]）。
  final String? newTeacher;

  /// 备注，如「老师出差，顺延到周五」。
  final String note;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Reschedule({
    required this.id,
    required this.kind,
    required this.scope,
    required this.week,
    required this.courseCode,
    required this.courseName,
    this.classCode = '',
    this.originTeacher = '',
    this.originDay,
    this.originStartPeriod,
    this.originEndPeriod,
    this.originClassroom = '',
    this.targetDay,
    this.targetStartPeriod,
    this.targetEndPeriod,
    this.targetClassroom = '',
    this.targetCampus,
    this.newTeacher,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isExtra => kind == RescheduleKind.extra;

  bool get isCancel => kind == RescheduleKind.cancel;

  bool get isMove => kind == RescheduleKind.move;

  bool get isOnce => scope == RescheduleScope.once;

  /// 是否需要目标时段（调课/补课需要，停课不需要）。
  bool get needsTarget => kind != RescheduleKind.cancel;

  /// 生效范围描述，如「第 10 周」/「第 10 周起」。
  String get weekText => isOnce ? '第 $week 周' : '第 $week 周起';

  /// 列表页的副标题，如「长期 · 第 10 周起」。
  String get scopeText => '${scope.label} · $weekText';

  /// 原时段描述，如「周三 3-4节 · 麦三教3407」；补课返回空串。
  String get originText {
    final d = originDay;
    final s = originStartPeriod;
    final e = originEndPeriod;
    if (d == null || s == null || e == null) return '';
    final room = originClassroom.isEmpty ? '' : ' · $originClassroom';
    return '${d.displayName} ${periodRangeText(s, e)}$room';
  }

  /// 调整后时段描述，如「周五 6-8节 · 麦三教3501」。
  String get targetText {
    final d = targetDay;
    final s = targetStartPeriod;
    final e = targetEndPeriod ?? s;
    if (d == null || s == null || e == null) return '';
    final room = targetClassroom.isEmpty ? '' : ' · $targetClassroom';
    final teacher = newTeacher == null || newTeacher!.isEmpty
        ? ''
        : ' · ${newTeacher!}';
    return '${d.displayName} ${periodRangeText(s, e)}$room$teacher';
  }

  /// 一行变更摘要（列表页与详情用）。
  String get summary => switch (kind) {
    RescheduleKind.move =>
      originText.isEmpty ? targetText : '$originText → $targetText',
    RescheduleKind.cancel => '${originText.isEmpty ? courseName : originText} 停课',
    RescheduleKind.extra => '补课 $targetText',
  };

  /// 是否作用于 [w] 这一教学周。
  bool appliesInWeek(int w) => isOnce ? w == week : w >= week;

  /// 原时段是否与本记录指向同一次课（星期 + 首末节次）。
  bool matchesOriginSlot(ClassTime ct) {
    final d = originDay;
    final s = originStartPeriod;
    final e = originEndPeriod;
    if (d == null || s == null || e == null) return false;
    return ct.dayOfWeek == d && ct.startPeriod == s && ct.endPeriod == e;
  }

  /// 本记录是否描述「同一个原课位」（课程代码 + 星期 + 首末节次）。
  bool sameOriginSlotAs(Reschedule other) =>
      courseCode.trim().toLowerCase() ==
          other.courseCode.trim().toLowerCase() &&
      originDay == other.originDay &&
      originStartPeriod == other.originStartPeriod &&
      originEndPeriod == other.originEndPeriod;

  Reschedule copyWith({
    RescheduleKind? kind,
    RescheduleScope? scope,
    int? week,
    String? courseName,
    DayOfWeek? targetDay,
    int? targetStartPeriod,
    int? targetEndPeriod,
    String? targetClassroom,
    String? targetCampus,
    String? newTeacher,
    String? note,
    DateTime? updatedAt,
  }) => Reschedule(
    id: id,
    kind: kind ?? this.kind,
    scope: scope ?? this.scope,
    week: week ?? this.week,
    courseCode: courseCode,
    courseName: courseName ?? this.courseName,
    classCode: classCode,
    originTeacher: originTeacher,
    originDay: originDay,
    originStartPeriod: originStartPeriod,
    originEndPeriod: originEndPeriod,
    originClassroom: originClassroom,
    targetDay: targetDay ?? this.targetDay,
    targetStartPeriod: targetStartPeriod ?? this.targetStartPeriod,
    targetEndPeriod: targetEndPeriod ?? this.targetEndPeriod,
    targetClassroom: targetClassroom ?? this.targetClassroom,
    targetCampus: targetCampus ?? this.targetCampus,
    newTeacher: newTeacher ?? this.newTeacher,
    note: note ?? this.note,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'scope': scope.name,
    'week': week,
    'courseCode': courseCode,
    'courseName': courseName,
    'classCode': classCode,
    'originTeacher': originTeacher,
    'originDay': originDay?.name,
    'originStartPeriod': originStartPeriod,
    'originEndPeriod': originEndPeriod,
    'originClassroom': originClassroom,
    'targetDay': targetDay?.name,
    'targetStartPeriod': targetStartPeriod,
    'targetEndPeriod': targetEndPeriod,
    'targetClassroom': targetClassroom,
    'targetCampus': targetCampus,
    'newTeacher': newTeacher,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// 容错解析：课程名缺失或关键字段缺失时返回 null（旧数据不得导致崩溃）。
  static Reschedule? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final courseName = raw['courseName'];
    if (id is! String || id.isEmpty) return null;
    if (courseName is! String || courseName.isEmpty) return null;

    final week = raw['week'];
    if (week is! num) return null;

    final kind = RescheduleKind.byName(raw['kind']);
    final scope = RescheduleScope.byName(raw['scope']);

    int? intOf(String key) {
      final v = raw[key];
      return v is num ? v.toInt() : null;
    }

    String str(String key) => raw[key] is String ? raw[key] as String : '';

    final now = DateTime.now();
    return Reschedule(
      id: id,
      kind: kind,
      scope: scope,
      week: week.toInt(),
      courseCode: str('courseCode'),
      courseName: courseName,
      classCode: str('classCode'),
      originTeacher: str('originTeacher'),
      originDay: _dayByName(raw['originDay']),
      originStartPeriod: intOf('originStartPeriod'),
      originEndPeriod: intOf('originEndPeriod'),
      originClassroom: str('originClassroom'),
      targetDay: _dayByName(raw['targetDay']),
      targetStartPeriod: intOf('targetStartPeriod'),
      targetEndPeriod: intOf('targetEndPeriod'),
      targetClassroom: str('targetClassroom'),
      targetCampus: raw['targetCampus'] is String
          ? raw['targetCampus'] as String
          : null,
      newTeacher: raw['newTeacher'] is String && (raw['newTeacher'] as String).isNotEmpty
          ? raw['newTeacher'] as String
          : null,
      note: str('note'),
      createdAt: _dateTimeOf(raw['createdAt']) ?? now,
      updatedAt: _dateTimeOf(raw['updatedAt']) ?? now,
    );
  }

  static DateTime? _dateTimeOf(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  static DayOfWeek? _dayByName(Object? name) {
    if (name is! String) return null;
    for (final d in DayOfWeek.values) {
      if (d.name == name) return d;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Reschedule && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Reschedule(${kind.name}/${scope.name} $courseName $weekText)';
}

/// 节次区间描述：`3-4节`；单节时为 `第 3 节`。
String periodRangeText(int start, int end) =>
    start == end ? '第 $start 节' : '$start-$end节';
