/// 分数估计 · 课程「截止日期」领域模型（网课 / 作业 / 考试等）。
///
/// 语义（2026-09-15 立，改动前先读）：
/// - 每条截止日期**只属于一门课程**（`GeCourse.deadlines`），入口在课程详情页。
/// - 单次条目：`dueAt` 就是截止时刻，过期即「已过期」。
/// - 重复条目（每周 / 每两周）：`dueAt` 是**规则锚点**（首次截止时刻），
///   展示与提醒一律用 [geDeadlineEffectiveDue] 推出的「下一个未来截止时刻」，
///   因此**永远不会变成「已过期」**——错过的周期直接跳过，不做补记。
/// - 「本期已完成」= `doneAt` 落在当前周期内（[geDeadlinePeriodStart] 之后）；
///   周期一滚过去，完成状态**自动失效**，不需要任何后台任务重置。
library;

import 'ge_memo.dart' show geMemoStringOf;

/// 截止事项类型（决定角标文案与配色）。
enum GeDeadlineKind {
  /// 网课（在线课程的学习 / 测验截止）。
  onlineCourse('网课'),

  /// 作业提交。
  homework('作业'),

  /// 考试 / 测验。
  exam('考试'),

  /// 其它（实验报告、论文、报名等）。
  other('其它');

  const GeDeadlineKind(this.label);

  /// 中文短标签（角标 / chip 用）。
  final String label;

  /// 从持久化字符串还原，未知值回落 [GeDeadlineKind.homework]。
  static GeDeadlineKind fromName(Object? name) {
    final s = geMemoStringOf(name);
    for (final k in GeDeadlineKind.values) {
      if (k.name == s) return k;
    }
    return GeDeadlineKind.homework;
  }
}

/// 重复规则。
enum GeDeadlineRepeat {
  /// 只此一次。
  none('不重复', null),

  /// 每周重复。
  weekly('每周', Duration(days: 7)),

  /// 每两周重复。
  biweekly('每两周', Duration(days: 14));

  const GeDeadlineRepeat(this.label, this.interval);

  /// 中文标签。
  final String label;

  /// 重复间隔；[GeDeadlineRepeat.none] 为 null。
  final Duration? interval;

  /// 是否重复。
  bool get isRepeating => interval != null;

  /// 从持久化字符串还原，未知值回落 [GeDeadlineRepeat.none]。
  static GeDeadlineRepeat fromName(Object? name) {
    final s = geMemoStringOf(name);
    for (final r in GeDeadlineRepeat.values) {
      if (r.name == s) return r;
    }
    return GeDeadlineRepeat.none;
  }
}

/// 默认提醒提前量：提前 1 天 + 提前 1 小时。
const List<Duration> geDeadlineDefaultLeads = [
  Duration(days: 1),
  Duration(hours: 1),
];

/// 重复条目**预排**的未来次数（每次 N 条提醒）：覆盖约一个月，
/// 之后每次 App 回前台 / 数据变动都会重排（见 `data/ge_deadline_reminders.dart`）。
const int geDeadlineScheduleHorizon = 4;

/// 「临近」阈值：剩余时间不超过它就进入 [GeDeadlineStatus.soon]。
const Duration geDeadlineSoonWindow = Duration(days: 3);

/// 一条课程截止日期。
class GeDeadline {
  /// 稳定 id（uuid），提醒排期与去重都靠它。
  final String id;

  /// 标题，如「第 3 章习题」「网课第 2 讲测验」。
  final String title;

  /// 类型。
  final GeDeadlineKind kind;

  /// 截止时刻；重复条目为**规则锚点**（首次截止时刻）。
  final DateTime dueAt;

  /// 重复规则。
  final GeDeadlineRepeat repeat;

  /// 备注（可选），如「超星学习通 · 需提交 PDF」。
  final String note;

  /// 完成时刻：单次 = 完成于；重复 = **本期**完成于（滚到下一期自动失效）。
  final DateTime? doneAt;

  /// 是否提醒（默认开）。
  final bool remind;

  /// 创建时间（epoch ms），同刻排序用。
  final int createdAt;

  const GeDeadline({
    required this.id,
    required this.title,
    required this.dueAt,
    this.kind = GeDeadlineKind.homework,
    this.repeat = GeDeadlineRepeat.none,
    this.note = '',
    this.doneAt,
    this.remind = true,
    this.createdAt = 0,
  });

  /// 是否重复。
  bool get isRepeating => repeat.isRepeating;

  /// 展示用标题（空标题兜底）。
  String get displayTitle => title.trim().isEmpty ? '未命名截止' : title.trim();

  /// 角标文案 = 类型标签。
  String get badge => kind.label;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'dueAt': dueAt.toIso8601String(),
    'repeat': repeat.name,
    'note': note,
    'doneAt': doneAt?.toIso8601String(),
    'remind': remind,
    'createdAt': createdAt,
  };

  /// 单条容错还原（脏数据不抛异常；`id` 或 `dueAt` 不可用时返回 null）。
  static GeDeadline? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, dynamic>();
    final due = _dateOf(json['dueAt']);
    if (due == null) return null;
    final id = geMemoStringOf(json['id']);
    final title = geMemoStringOf(json['title']);
    return GeDeadline(
      id: id.isEmpty ? '${due.microsecondsSinceEpoch}' : id,
      title: title,
      kind: GeDeadlineKind.fromName(json['kind']),
      dueAt: due,
      repeat: GeDeadlineRepeat.fromName(json['repeat']),
      note: geMemoStringOf(json['note']),
      doneAt: _dateOf(json['doneAt']),
      remind: json['remind'] is bool ? json['remind'] as bool : true,
      createdAt: _intOf(json['createdAt']),
    );
  }

  GeDeadline copyWith({
    String? id,
    String? title,
    GeDeadlineKind? kind,
    DateTime? dueAt,
    GeDeadlineRepeat? repeat,
    String? note,
    DateTime? doneAt,
    bool? remind,
    int? createdAt,
    bool clearDone = false,
  }) => GeDeadline(
    id: id ?? this.id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    dueAt: dueAt ?? this.dueAt,
    repeat: repeat ?? this.repeat,
    note: note ?? this.note,
    doneAt: clearDone ? null : (doneAt ?? this.doneAt),
    remind: remind ?? this.remind,
    createdAt: createdAt ?? this.createdAt,
  );

  @override
  bool operator ==(Object other) =>
      other is GeDeadline &&
      other.id == id &&
      other.title == title &&
      other.kind == kind &&
      other.dueAt == dueAt &&
      other.repeat == repeat &&
      other.note == note &&
      other.doneAt == doneAt &&
      other.remind == remind &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    kind,
    dueAt,
    repeat,
    note,
    doneAt,
    remind,
    createdAt,
  );
}

/// 列表容错还原（非 List / 脏项一律跳过，不抛异常）。
List<GeDeadline> geDeadlinesFromJson(Object? raw) {
  if (raw is! List) return const [];
  final out = <GeDeadline>[];
  for (final item in raw) {
    final d = GeDeadline.fromJson(item);
    if (d != null) out.add(d);
  }
  return out;
}

// ---------------------------------------------------------------- 时间推算

/// 重复条目的第 [index] 次截止时刻（[index] = 0 即下一次）；
/// 单次条目恒返回 [GeDeadline.dueAt]。
///
/// 单次条目的「下一次」= 它自己（可能已过期）。
DateTime geDeadlineOccurrence(GeDeadline d, DateTime now, int index) {
  final step = d.repeat.interval;
  if (step == null) return d.dueAt;
  final base = _nextOccurrence(d.dueAt, step, now);
  return base.add(step * (index < 0 ? 0 : index));
}

/// 「下一个未来截止时刻」：单次 = `dueAt`（可能已过期）；重复 = 锚点向后滚动。
DateTime geDeadlineEffectiveDue(GeDeadline d, DateTime now) =>
    geDeadlineOccurrence(d, now, 0);

/// 当前周期起点（= 下一次截止 − 间隔）；单次条目返回 null。
DateTime? geDeadlinePeriodStart(GeDeadline d, DateTime now) {
  final step = d.repeat.interval;
  if (step == null) return null;
  return geDeadlineEffectiveDue(d, now).subtract(step);
}

/// 本期是否已完成：
/// - 单次：`doneAt != null` 即已完成（永久）；
/// - 重复：`doneAt` 落在当前周期内——周期滚过去后**自动**变回未完成。
bool geDeadlineDoneNow(GeDeadline d, DateTime now) {
  final done = d.doneAt;
  if (done == null) return false;
  final start = geDeadlinePeriodStart(d, now);
  if (start == null) return true;
  return !done.isBefore(start);
}

/// 截止状态。
enum GeDeadlineStatus {
  /// 本期已完成。
  done('已完成'),

  /// 已过截止（仅单次条目会出现）。
  overdue('已过期'),

  /// 今天内截止。
  today('今天截止'),

  /// 3 天内截止。
  soon('即将截止'),

  /// 还早。
  upcoming('进行中');

  const GeDeadlineStatus(this.label);

  /// 中文标签。
  final String label;
}

/// 状态判定（[now] 注入，便于测试）。
GeDeadlineStatus geDeadlineStatus(GeDeadline d, DateTime now) {
  if (geDeadlineDoneNow(d, now)) return GeDeadlineStatus.done;
  final due = geDeadlineEffectiveDue(d, now);
  final left = due.difference(now);
  if (left.isNegative) return GeDeadlineStatus.overdue;
  if (_sameDay(due, now)) return GeDeadlineStatus.today;
  if (left <= geDeadlineSoonWindow) return GeDeadlineStatus.soon;
  return GeDeadlineStatus.upcoming;
}

/// 剩余 / 过期时长的中文文案，如「还剩 2 天 3 小时」「已过期 5 小时」。
String geDeadlineRemainingText(Duration delta) {
  final overdue = delta.isNegative;
  final abs = overdue ? -delta : delta;
  final days = abs.inDays;
  final hours = abs.inHours % 24;
  final minutes = abs.inMinutes % 60;
  final String amount;
  if (days > 0) {
    amount = hours > 0 ? '$days 天 $hours 小时' : '$days 天';
  } else if (hours > 0) {
    amount = minutes > 0 ? '$hours 小时 $minutes 分' : '$hours 小时';
  } else if (minutes > 0) {
    amount = '$minutes 分钟';
  } else {
    amount = '不到 1 分钟';
  }
  return overdue ? '已过期 $amount' : '还剩 $amount';
}

/// 卡片上的倒计时文案：
/// 已完成 → 「本期已完成」/「已完成」；今天截止 → 「今天 23:59 截止」；其余 → 剩余时长。
String geDeadlineCountdownText(GeDeadline d, DateTime now) {
  if (geDeadlineDoneNow(d, now)) {
    return d.isRepeating ? '本期已完成' : '已完成';
  }
  final due = geDeadlineEffectiveDue(d, now);
  if (_sameDay(due, now) && !due.isBefore(now)) {
    return '今天 ${geDeadlineClockText(due)} 截止';
  }
  return geDeadlineRemainingText(due.difference(now));
}

/// 时刻文案 `HH:mm`。
String geDeadlineClockText(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 日期文案：同年省略年份（`10-08` / `2027-01-01`）。
String geDeadlineDateText(DateTime t, DateTime now) {
  final md = '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
  return t.year == now.year ? md : '${t.year}-$md';
}

/// 截止时刻完整文案：`10-08 23:59`。
String geDeadlineDueText(DateTime due, DateTime now) =>
    '${geDeadlineDateText(due, now)} ${geDeadlineClockText(due)}';

/// 重复规则的补充说明：`每周 · 下次 10-08 23:59`。
String geDeadlineRepeatText(GeDeadline d, DateTime now) {
  if (!d.isRepeating) return geDeadlineDueText(d.dueAt, now);
  return '${d.repeat.label} · 下次 ${geDeadlineDueText(geDeadlineEffectiveDue(d, now), now)}';
}

/// 排序：未完成在前（截止越近越靠前），已完成/已过期沉底（越近越靠前）。
List<GeDeadline> geSortedDeadlines(Iterable<GeDeadline> items, DateTime now) {
  final list = items.toList();
  list.sort((a, b) {
    final rankA = _sortRank(a, now);
    final rankB = _sortRank(b, now);
    if (rankA != rankB) return rankA.compareTo(rankB);
    final dueA = geDeadlineEffectiveDue(a, now);
    final dueB = geDeadlineEffectiveDue(b, now);
    final byDue = dueA.compareTo(dueB);
    if (byDue != 0) return byDue;
    return a.id.compareTo(b.id);
  });
  return list;
}

/// 未完成 = 0；已完成 / 已过期 = 1（沉底）。
int _sortRank(GeDeadline d, DateTime now) {
  final status = geDeadlineStatus(d, now);
  return (status == GeDeadlineStatus.done || status == GeDeadlineStatus.overdue)
      ? 1
      : 0;
}

// ---------------------------------------------------------------- 内部工具

/// 锚点向后滚到**严格晚于** [now] 的第一个时刻。
DateTime _nextOccurrence(DateTime anchor, Duration step, DateTime now) {
  final stepUs = step.inMicroseconds;
  if (stepUs <= 0) return anchor;
  if (anchor.isAfter(now)) return anchor;
  final deltaUs = now.difference(anchor).inMicroseconds;
  // +1 保证严格晚于 now（差值为整数倍时不能停在 now 上）。
  var k = deltaUs ~/ stepUs + 1;
  if (k < 0) k = 0;
  var next = anchor.add(step * k);
  // 极端边界（时钟回拨 / 亚微秒误差）兜底。
  while (!next.isAfter(now)) {
    k += 1;
    next = anchor.add(step * k);
  }
  return next;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 容错取时间：ISO8601 字符串 / epoch 毫秒数字 / DateTime 本体都接受。
DateTime? _dateOf(Object? raw) {
  if (raw is DateTime) return raw;
  if (raw is num) {
    final ms = raw.toInt();
    if (ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
  final s = geMemoStringOf(raw);
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed != null) return parsed;
  final ms = int.tryParse(s);
  if (ms != null && ms > 0) return DateTime.fromMillisecondsSinceEpoch(ms);
  return null;
}

int _intOf(Object? raw) {
  if (raw is num) return raw.toInt();
  return int.tryParse(geMemoStringOf(raw)) ?? 0;
}
