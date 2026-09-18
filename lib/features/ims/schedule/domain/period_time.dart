/// 作息时间表（节次 → 钟点）。
///
/// 教务课表的「上课时间地点」列只给节次（如 `一[6-8]`），**不含钟点**；
/// 要做「上课中 / 下一节课」的倒计时，必须先有这张节次→时刻的映射。
///
/// 数据来源：教务系统公开页 `SchoolTimetable.jsp`（免登录，见
/// `data/datasources/period_table_remote_datasource.dart`）。
/// 实测该页随学年学期变化，2020–2026 的 15 个学期里出现过 3 种表格，
/// 因此这里内置 [PeriodTable.builtin] 作兜底，实时值按学期拉取并缓存。
library;

/// 一天里的节次总数（1..12）。
///
/// 课表网格的行数、作息表的完整性判定（[PeriodTable.isUsable]）、大间隔矮行的
/// 扫描范围都以它为准 —— 从前这几个 12 是各自写死的字面量。
const int schedulePeriodCount = 12;

/// 单个节次的作息时刻。
class ClassPeriod {
  /// 节次序号（1–12）。
  final int index;

  /// 开始时刻，`HH:mm`。
  final String start;

  /// 结束时刻，`HH:mm`。
  final String end;

  const ClassPeriod({
    required this.index,
    required this.start,
    required this.end,
  });

  /// 开始时刻距 00:00 的分钟数。格式非法时返回 0。
  int get startMinutes => parseHhmm(start);

  /// 结束时刻距 00:00 的分钟数。格式非法时返回 0。
  int get endMinutes => parseHhmm(end);

  /// 本节的分钟数。
  int get durationMinutes => endMinutes - startMinutes;

  /// `HH:mm` → 距 00:00 的分钟数；非法输入返回 0。
  static int parseHhmm(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return 0;
    return h * 60 + m;
  }

  Map<String, dynamic> toJson() => {'index': index, 'start': start, 'end': end};

  /// 容错解析：字段缺失或类型不符时返回 null（旧数据不得导致崩溃）。
  static ClassPeriod? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final index = raw['index'];
    final start = raw['start'];
    final end = raw['end'];
    if (index is! num || start is! String || end is! String) return null;
    if (start.isEmpty || end.isEmpty) return null;
    return ClassPeriod(index: index.toInt(), start: start, end: end);
  }

  @override
  String toString() => 'ClassPeriod($index $start-$end)';
}

/// 一张完整的作息时间表。
class PeriodTable {
  /// 按节次升序排列的作息项。
  final List<ClassPeriod> periods;

  /// 表格标题，如「江西财经大学2026-2027学年第一学期作息时间」。
  final String label;

  /// 所属学年学期，格式 `学年-学期`（如 `2026-0`）；内置兜底表为 null 表示「通用」。
  final String? termCode;

  /// 来源：`builtin`（内置兜底）或 `remote`（教务实时拉取）。
  final String source;

  const PeriodTable({
    required this.periods,
    required this.label,
    this.termCode,
    this.source = 'builtin',
  });

  /// 是否可用：12 个节次齐备才算完整表。
  bool get isUsable => periods.length >= 12;

  /// 取第 [index] 节的作息；不存在返回 null。
  ClassPeriod? periodOf(int index) {
    for (final p in periods) {
      if (p.index == index) return p;
    }
    return null;
  }

  /// 第 [index] 节在 [day] 那天的开始时刻；该节次缺失时返回 null。
  DateTime? startAt(DateTime day, int index) {
    final p = periodOf(index);
    if (p == null) return null;
    return _atMinutes(day, p.startMinutes);
  }

  /// 第 [index] 节在 [day] 那天的结束时刻；该节次缺失时返回 null。
  DateTime? endAt(DateTime day, int index) {
    final p = periodOf(index);
    if (p == null) return null;
    return _atMinutes(day, p.endMinutes);
  }

  /// 连续节次段 `[fromPeriod, toPeriod]` 在 [day] 那天的起止时刻。
  ///
  /// 任一端的节次缺失时返回 `(null, null)`。
  ({DateTime? start, DateTime? end}) span(
    DateTime day,
    int fromPeriod,
    int toPeriod,
  ) {
    final s = startAt(day, fromPeriod);
    final e = endAt(day, toPeriod);
    if (s == null || e == null) return (start: null, end: null);
    return (start: s, end: e);
  }

  static DateTime _atMinutes(DateTime day, int minutes) =>
      DateTime(day.year, day.month, day.day).add(Duration(minutes: minutes));

  Map<String, dynamic> toJson() => {
    'periods': periods.map((p) => p.toJson()).toList(),
    'label': label,
    'termCode': termCode,
    'source': source,
  };

  /// 容错解析：解析不出任何节次时返回 null。
  static PeriodTable? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rawPeriods = raw['periods'];
    if (rawPeriods is! List) return null;
    final periods = <ClassPeriod>[];
    for (final item in rawPeriods) {
      final p = ClassPeriod.fromJson(item);
      if (p != null) periods.add(p);
    }
    if (periods.isEmpty) return null;
    periods.sort((a, b) => a.index.compareTo(b.index));
    return PeriodTable(
      periods: periods,
      label: raw['label'] is String ? raw['label'] as String : '',
      termCode: raw['termCode'] is String ? raw['termCode'] as String : null,
      source: raw['source'] is String ? raw['source'] as String : 'remote',
    );
  }

  /// 内置兜底表 —— 主流版作息（实测覆盖 2026-0、2025-0/1、2024-1、
  /// 2023-1、2022-0/1、2021-0/1、2020-1 共 10 个学期）。
  ///
  /// 仅在两处使用：① 实时拉取失败时的兜底；② 单元测试。
  /// 注意 2024-0/2023-0 的第 11 节结束于 20:10（本表为 20:15），
  /// 2020-0 为结构完全不同的 10 节制 —— 故不可长期依赖内置表。
  static const PeriodTable builtin = PeriodTable(
    label: '江西财经大学作息时间（内置兜底表）',
    source: 'builtin',
    periods: [
      ClassPeriod(index: 1, start: '08:00', end: '08:45'),
      ClassPeriod(index: 2, start: '08:50', end: '09:35'),
      ClassPeriod(index: 3, start: '09:55', end: '10:40'),
      ClassPeriod(index: 4, start: '10:45', end: '11:30'),
      ClassPeriod(index: 5, start: '11:35', end: '12:20'),
      ClassPeriod(index: 6, start: '14:00', end: '14:45'),
      ClassPeriod(index: 7, start: '14:50', end: '15:35'),
      ClassPeriod(index: 8, start: '15:55', end: '16:40'),
      ClassPeriod(index: 9, start: '16:45', end: '17:30'),
      ClassPeriod(index: 10, start: '18:40', end: '19:25'),
      ClassPeriod(index: 11, start: '19:30', end: '20:15'),
      ClassPeriod(index: 12, start: '20:20', end: '21:05'),
    ],
  );
}

/// 节次所属时段名称（上午/下午/晚上），用于界面分组。
String periodSectionName(int index) {
  if (index <= 5) return '上午';
  if (index <= 9) return '下午';
  return '晚上';
}
