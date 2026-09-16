/// 「多班对照找无课时间」的纯领域引擎。
///
/// 输入是若干**已展开**的占用槽（每个班课表里的「第 X-Y 周 周 Z[A-B] 节」= 一条槽），
/// 输出是「所有班都空」的连续时段。刻意不依赖 Flutter、不依赖任何接口格式，
/// 因此可以脱离网络单测（见 `test/public_free_time_test.dart`）。
///
/// 口径约定（改动前先读）：
/// - 周次、星期、节次一律 **1 起**；星期 1 = 周一。
/// - 连续判定**只在一个半日块内**：上午 / 下午 / 晚上之间**不合并**，
///   否则「上午 1-2 节空 + 下午 5-6 节空」会被并成一个 1-6 节的假窗口。
/// - 占用槽可能跨出 [maxPeriod]：越界部分直接裁掉，不报错。
library;

import '../../schedule/domain/class_time.dart';

/// 一次上课占用（一个班、一门课的一条时间安排）。
class ScheduleSlot {
  /// 星期，1 = 周一 … 7 = 周日。
  final int weekday;

  /// 起始节次、结束节次（含），1 起。
  final int startPeriod;
  final int endPeriod;

  /// 生效周次区间（含），1 起。
  final int startWeek;
  final int endWeek;

  /// 单双周。教务「1-16周(单)」这类安排必须带上，否则第 2 周会被误判成占用。
  final WeekParity parity;

  /// 展示用：课程名 / 归属（班级、教师、教室…）。
  final String courseName;
  final String owner;

  const ScheduleSlot({
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    this.startWeek = 1,
    this.endWeek = 30,
    this.parity = WeekParity.every,
    this.courseName = '',
    this.owner = '',
  });

  /// 由既有课表模型 [ClassTime] 转换（学生课表与公共查询共用同一套时间格式）。
  factory ScheduleSlot.fromClassTime(
    ClassTime time, {
    String owner = '',
    String courseName = '',
  }) => ScheduleSlot(
    weekday: time.dayOfWeek.dayIndex,
    startPeriod: time.startPeriod,
    endPeriod: time.endPeriod,
    startWeek: time.startWeek,
    endWeek: time.endWeek,
    parity: time.weekParity,
    courseName: courseName,
    owner: owner,
  );

  /// 该槽在第 [week] 教学周是否生效（含单双周判定）。
  bool coversWeek(int week) {
    if (week < startWeek || week > endWeek) return false;
    return switch (parity) {
      WeekParity.every => true,
      WeekParity.odd => week.isOdd,
      WeekParity.even => week.isEven,
    };
  }

  /// 该槽在第 [week] 周的星期 [weekday]、第 [period] 节是否占用。
  bool occupies(int weekday, int period, {required int week}) =>
      this.weekday == weekday &&
      coversWeek(week) &&
      period >= startPeriod &&
      period <= endPeriod;

  @override
  String toString() =>
      'ScheduleSlot(周$weekday $startPeriod-$endPeriod 节, '
      '$startWeek-$endWeek 周${parity.displayName}, $owner/$courseName)';
}

/// 把一批 [ClassTime] 批量转成占用槽（同一门课/同一对象的多个时间安排）。
List<ScheduleSlot> slotsFromClassTimes(
  Iterable<ClassTime> times, {
  String owner = '',
  String courseName = '',
}) => [
  for (final t in times)
    ScheduleSlot.fromClassTime(t, owner: owner, courseName: courseName),
];

/// 一段「全部对照对象都空」的连续时段。
class FreeWindow {
  /// 星期，1 = 周一 … 7 = 周日。
  final int weekday;

  /// 起始节次、结束节次（含）。
  final int startPeriod;
  final int endPeriod;

  /// 该窗口所属教学周。
  final int week;

  const FreeWindow({
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.week,
  });

  /// 连续节数。
  int get periods => endPeriod - startPeriod + 1;

  /// `周三 3-4 节`。
  String get label => '周${_weekdayLabel(weekday)} $startPeriod-$endPeriod 节';

  /// 单节时显示成 `周三 3 节`。
  String get compactLabel => startPeriod == endPeriod
      ? '周${_weekdayLabel(weekday)} $startPeriod 节'
      : label;

  @override
  String toString() => 'FreeWindow($label, 第 $week 周, $periods节)';
}

const List<String> _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

String _weekdayLabel(int weekday) =>
    (weekday >= 1 && weekday <= 7) ? _weekdayNames[weekday - 1] : '?';

/// 一个半日块（含首尾节次），默认上午 1-4 / 下午 5-8 / 晚上 9-12。
typedef PeriodBlock = (int start, int end);

/// 默认半日块 = **江财实际作息表**推出来的三段（别照抄「上午 4 节」的直觉）：
///
/// `PeriodTable.builtin`（`lib/features/ims/schedule/domain/period_time.dart:153`）里
/// 第 5 节是 `11:35-12:20`（仍在上午），第 6 节才是 `14:00` 起（午休 100 分钟），
/// 第 10 节 `18:40` 起（晚饭 70 分钟）。因此块边界是 **1-5 / 6-9 / 10-12**。
///
/// 运行时若拿到教务实时作息表，用 [periodBlocksFromTimes] 现场推导更稳
/// （学校改过作息表，内置表只是兜底）。
const List<PeriodBlock> kDefaultPeriodBlocks = [
  (1, 5),
  (6, 9),
  (10, 12),
];

/// 由「节次 → 上课时刻」推出半日块：相邻节次间隔 > [gapMinutes] 视为分块。
///
/// 交给作息表用时，能自动适配不同学期的作息变化（学校改过作息表）。
List<PeriodBlock> periodBlocksFromTimes(
  List<({int index, String start, String end})> periods, {
  int gapMinutes = 45,
}) {
  final sorted = [...periods]..sort((a, b) => a.index.compareTo(b.index));
  if (sorted.isEmpty) return const [];
  final blocks = <PeriodBlock>[];
  var blockStart = sorted.first.index;
  var previousEnd = _minutes(sorted.first.end);
  for (var i = 1; i < sorted.length; i++) {
    final p = sorted[i];
    final start = _minutes(p.start);
    if (start - previousEnd > gapMinutes) {
      blocks.add((blockStart, sorted[i - 1].index));
      blockStart = p.index;
    }
    previousEnd = _minutes(p.end);
  }
  blocks.add((blockStart, sorted.last.index));
  return blocks;
}

int _minutes(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return 0;
  return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
}

/// 为某一教学周构造占用矩阵：`grid[weekday][period]` = 该格被占用的对照对象数。
///
/// 返回 7 行（周一…周日）× `maxPeriod + 1` 列（第 0 列占位，便于直接用节次索引）。
List<List<int>> buildOccupancyGrid({
  required List<ScheduleSlot> slots,
  required int week,
  int maxPeriod = 12,
}) {
  final grid = [
    for (var d = 0; d <= 7; d++) List<int>.filled(maxPeriod + 1, 0),
  ];
  final owners = [
    for (var d = 0; d <= 7; d++) List<Set<String>>.generate(
      maxPeriod + 1,
      (_) => <String>{},
    ),
  ];
  for (final s in slots) {
    if (s.weekday < 1 || s.weekday > 7) continue;
    if (!s.coversWeek(week)) continue;
    final from = s.startPeriod < 1 ? 1 : s.startPeriod;
    final to = s.endPeriod > maxPeriod ? maxPeriod : s.endPeriod;
    for (var p = from; p <= to; p++) {
      // 同一对象在同一格重复占用只算一次（同班两门课撞同一格）
      final key = s.owner.isEmpty ? s.courseName : s.owner;
      if (owners[s.weekday][p].add(key)) grid[s.weekday][p]++;
    }
  }
  return grid;
}

/// 找出第 [week] 教学周里「所有对照对象都空」的连续时段。
///
/// - [slots]：所有对照对象的占用槽（多个班/教师/教室的全部槽合并传入）；
/// - [maxPeriod]：一天最大节次（默认 12）；
/// - [blocks]：半日块，跨块不合并（默认 [kDefaultPeriodBlocks]）；
/// - [weekdays]：纳入计算的星期（默认周一~周五）；
/// - [minPeriods]：只保留连续节数 ≥ 该值的窗口（默认 1，即单节空也算）；
/// - [ignoreBeyondMaxPeriod] 语义：占用槽超出 [maxPeriod] 的部分被裁掉。
List<FreeWindow> findFreeWindows({
  required List<ScheduleSlot> slots,
  required int week,
  int maxPeriod = 12,
  List<PeriodBlock> blocks = kDefaultPeriodBlocks,
  Set<int> weekdays = const {1, 2, 3, 4, 5},
  int minPeriods = 1,
}) {
  final grid = buildOccupancyGrid(
    slots: slots,
    week: week,
    maxPeriod: maxPeriod,
  );
  final result = <FreeWindow>[];
  final days = weekdays.toList()..sort();
  for (final day in days) {
    if (day < 1 || day > 7) continue;
    for (final (blockStart, blockEnd) in blocks) {
      final from = blockStart < 1 ? 1 : blockStart;
      final to = blockEnd > maxPeriod ? maxPeriod : blockEnd;
      var runStart = -1;
      for (var p = from; p <= to + 1; p++) {
        final free = p <= to && grid[day][p] == 0;
        if (free && runStart < 0) {
          runStart = p;
        } else if (!free && runStart >= 0) {
          final length = p - runStart;
          if (length >= minPeriods) {
            result.add(
              FreeWindow(
                weekday: day,
                startPeriod: runStart,
                endPeriod: p - 1,
                week: week,
              ),
            );
          }
          runStart = -1;
        }
      }
    }
  }
  return result;
}

/// 按「连续节数多 → 星期靠前 → 节次靠前」排序（挑时间时最想先看到大块空闲）。
List<FreeWindow> rankFreeWindows(List<FreeWindow> windows) {
  final sorted = [...windows];
  sorted.sort((a, b) {
    if (a.periods != b.periods) return b.periods.compareTo(a.periods);
    if (a.weekday != b.weekday) return a.weekday.compareTo(b.weekday);
    return a.startPeriod.compareTo(b.startPeriod);
  });
  return sorted;
}

/// 在 [weeks] 每一周都成立的窗口（= 整段时间固定空闲），用于「长期固定的碰头时间」。
///
/// 只保留在**所有**给定周次里都出现的完全相同窗口（星期+节次）。
List<FreeWindow> commonFreeWindows({
  required List<ScheduleSlot> slots,
  required Iterable<int> weeks,
  int maxPeriod = 12,
  List<PeriodBlock> blocks = kDefaultPeriodBlocks,
  Set<int> weekdays = const {1, 2, 3, 4, 5},
  int minPeriods = 1,
}) {
  final weekList = weeks.toList()..sort();
  if (weekList.isEmpty) return const [];
  Map<String, FreeWindow>? intersection;
  for (final w in weekList) {
    final windows = findFreeWindows(
      slots: slots,
      week: w,
      maxPeriod: maxPeriod,
      blocks: blocks,
      weekdays: weekdays,
      minPeriods: minPeriods,
    );
    final map = {
      for (final f in windows) '${f.weekday}|${f.startPeriod}|${f.endPeriod}': f,
    };
    if (intersection == null) {
      intersection = map;
    } else {
      intersection = {
        for (final e in intersection.entries)
          if (map.containsKey(e.key)) e.key: e.value,
      };
    }
    if (intersection.isEmpty) return const [];
  }
  final result = intersection!.values.toList();
  result.sort((a, b) {
    if (a.weekday != b.weekday) return a.weekday.compareTo(b.weekday);
    return a.startPeriod.compareTo(b.startPeriod);
  });
  return result;
}

/// 每个对照对象在指定周的空闲节数统计（用于「哪个班最空」这类结论）。
Map<String, int> freePeriodsByOwner({
  required List<ScheduleSlot> slots,
  required int week,
  int maxPeriod = 12,
  Set<int> weekdays = const {1, 2, 3, 4, 5},
}) {
  final owners = <String>{};
  for (final s in slots) {
    if (s.coversWeek(week)) owners.add(s.owner.isEmpty ? s.courseName : s.owner);
  }
  final result = <String, int>{};
  final total = weekdays.length * maxPeriod;
  for (final owner in owners) {
    final own = slots
        .where((s) => (s.owner.isEmpty ? s.courseName : s.owner) == owner)
        .toList();
    final grid = buildOccupancyGrid(
      slots: own,
      week: week,
      maxPeriod: maxPeriod,
    );
    var busy = 0;
    for (final d in weekdays) {
      if (d < 1 || d > 7) continue;
      for (var p = 1; p <= maxPeriod; p++) {
        if (grid[d][p] > 0) busy++;
      }
    }
    result[owner] = total - busy;
  }
  return result;
}
