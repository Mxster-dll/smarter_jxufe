/// 学期教学周范围（第 1 周 / 最后一周）口径。
///
/// 用户 2026-09-15 要求「移动端左右滑动切换周数，第一周和最后一周不允许再滑动」，
/// 边界**一律取教务侧已有数据，不要写死**：
/// - **第 1 周** = 学期起始周：`resolveTeachingWeek()` 的 `firstMonday`
///   （见 `lib/features/school_calendar/domain/teaching_week.dart`，
///   教务校历周次表的第 1 周，261 → 09-07）。课表页已在用它。
/// - **最后一周** = 教务校历周次表的**最大周次**：项目已在
///   `schoolCalendarProvider((xn:, xq:))` 取到 `SchoolCalendar.months[].rows[].weekNo`
///   （与课表周次同源，261 → 17）；取不到时回退**课表自身周次范围**
///   （`ClassTime.endWeek` 的最大值），再回退 [fallbackTeachingWeeks]。
library;

import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';

/// 校历与课表都拿不到周次时的兜底教学周数。
const int fallbackTeachingWeeks = 20;

/// 从教务校历的周次表取最后教学周。
///
/// `weekNo` 解析器存的是该行首格原文（形如 `'1'`、`'17'`，也可能是 `'第3周'`），
/// 故统一抽其中数字；一行都取不到返回 null。
int? lastWeekFromCalendar(SchoolCalendar? calendar) {
  if (calendar == null) return null;
  var max = 0;
  for (final month in calendar.months) {
    for (final row in month.rows) {
      final raw = row.weekNo;
      if (raw == null) continue;
      final digits = RegExp(r'\d+').firstMatch(raw)?.group(0);
      final week = digits == null ? null : int.tryParse(digits);
      if (week != null && week > max) max = week;
    }
  }
  return max > 0 ? max : null;
}

/// 从课表自身的周次范围取最后教学周（各时段 `endWeek` 的最大值）。
int? lastWeekFromEntries(List<ScheduleEntry> entries) {
  var max = 0;
  for (final entry in entries) {
    for (final time in entry.classTimes) {
      if (time.endWeek > max) max = time.endWeek;
    }
  }
  return max > 0 ? max : null;
}

/// 把目标教学周夹到合法范围 `[1, lastWeek]`。
///
/// 课表页的「上一周 / 下一周」按钮与移动端左右滑动都走这里 ——
/// 用户 2026-09-15 要求「第一周和最后一周不允许再滑动」。
int clampTeachingWeek(int target, {required int lastWeek}) {
  if (lastWeek < 1) return 1;
  if (target < 1) return 1;
  return target > lastWeek ? lastWeek : target;
}

/// 本学期最后教学周：教务校历优先 → 课表周次兜底 → [fallbackTeachingWeeks]。
int resolveLastTeachingWeek({
  SchoolCalendar? calendar,
  List<ScheduleEntry> entries = const [],
  int fallback = fallbackTeachingWeeks,
}) =>
    lastWeekFromCalendar(calendar) ?? lastWeekFromEntries(entries) ?? fallback;
