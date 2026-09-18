/// 课表「大间隔矮行」的领域口径（用户 2026-09-17 需求）。
///
/// 用户原话：「我希望课表显示时，任意两行之间的时间间隔一旦超过了 1h，
/// 就在这两行之间插一个矮行」。
///
/// 判定依据**只能是真实作息表**（[PeriodTable]：教务公开页 `SchoolTimetable.jsp`
/// → 按学期缓存 → 内置兜底，见 `data/period_table_repository.dart`）：课表 HTML
/// 只给节次（如 `一[6-8]`）、不给钟点，所以「空了多久」必须由作息表算出来，
/// **不许在视图里写死「第 5 节之后」** —— 作息表实测随学年变化（2020–2026 出现
/// 过 3 种表格）。
///
/// 内置兜底表正好两处超过 1h，也就是「上午/下午」与「下午/晚上」的分界：
/// - 5 节 12:20 → 6 节 14:00（100 分钟，午休）
/// - 9 节 17:30 → 10 节 18:40（70 分钟，晚饭）
library;

import 'package:flutter/foundation.dart';

import 'period_time.dart';

/// 长间隔阈值（分钟）：相邻两节的空档**超过** 60 分钟才算「大间隔」。
const int scheduleGapThresholdMinutes = 60;

/// 课表行序列里的一项：一个节次，或一个大间隔矮行。
///
/// 竖版课表按它**逐行**渲染、横版按它**逐列**渲染，两个视图共用同一序列 ——
/// 一旦一边多插一边少插，节次格与课格就会整列错位。
@immutable
class ScheduleRow {
  /// 节次行（矮行时为**其前**那一节，见 [ScheduleRow.gap]）。
  const ScheduleRow.period(this.period) : gapMinutes = null;

  /// 矮行：插在第 [period] 节**之后**，[gapMinutes] 为该空档的分钟数。
  ///
  /// `gapMinutes` 收窄成非空 `int`：矮行必须带时长，传 null 就不是矮行了。
  const ScheduleRow.gap(this.period, int this.gapMinutes);

  /// 节次行的节次；矮行则是「它跟在哪一节后面」。
  final int period;

  /// 矮行的空档分钟数；节次行为 null。
  final int? gapMinutes;

  bool get isGap => gapMinutes != null;

  @override
  String toString() => isGap
      ? 'ScheduleRow.gap(after $period, $gapMinutes min)'
      : 'ScheduleRow.period($period)';
}

/// [period] 与 [period]+1 两节之间的空档分钟数。
///
/// 任一侧在作息表里缺失 → 返回 null（**不猜**：缺节的表不该凭空造出矮行）。
int? scheduleBreakMinutes(PeriodTable? table, int period) {
  if (table == null) return null;
  final before = table.periodOf(period);
  final after = table.periodOf(period + 1);
  if (before == null || after == null) return null;
  final minutes = after.startMinutes - before.endMinutes;
  return minutes > 0 ? minutes : null;
}

/// 课表行序列：12 个节次行 + 大间隔处的矮行。
List<ScheduleRow> scheduleRows(PeriodTable? table) {
  final rows = <ScheduleRow>[];
  for (var period = 1; period <= schedulePeriodCount; period++) {
    rows.add(ScheduleRow.period(period));
    if (period >= schedulePeriodCount) continue;
    final minutes = scheduleBreakMinutes(table, period);
    if (minutes != null && minutes > scheduleGapThresholdMinutes) {
      rows.add(ScheduleRow.gap(period, minutes));
    }
  }
  return rows;
}

/// 需要在第 p 节**之后**插矮行的节次（升序）。
List<int> scheduleGapAfterPeriods(PeriodTable? table) => <int>[
  for (final row in scheduleRows(table))
    if (row.isGap) row.period,
];

/// 空档时长文案：`1h40` / `2h` / `55m`。
///
/// 节次列只有 30~36dp 宽（手机 30），`1小时40分` 放不下 —— 只能用紧凑写法，
/// 与同格的 `08:00` / `12:20` 一起看语义已足够（上=上课、下=下课）。
String scheduleGapLabel(int minutes) {
  if (minutes <= 0) return '';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '${rest}m';
  if (rest == 0) return '${hours}h';
  return '${hours}h${rest.toString().padLeft(2, '0')}';
}
