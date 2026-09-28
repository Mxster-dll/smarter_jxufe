import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/school_calendar/data/providers/school_calendar_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_time.dart';

/// 学校时间轴（学年 / 学期 / 假期）—— **其它模块取学校时间的唯一入口**。
///
/// 领域口径全在 [SchoolTimeTable] 等（`domain/school_time.dart`），这里只负责
/// 把教务校历页的页面攒成一张表：
///
/// - 一个学年 = 4 页校历：`(xn,0)`、`(xn,1)`、`(xn,2)` + **下学年 `(xn+1,0)`**
///   （下学年第一学段第一天决定本学年最后一天，见 [SchoolYear.lastDay]）；
/// - **未公布的学段直接跳过**（教务页是 723 字节空壳 → 仓库抛异常）→ 对应字段
///   留 null，绝不猜（用户 2026-09-27 裁定：「取不到就留 null」）。
///
/// 用法：
/// ```dart
/// final table = await ref.watch(schoolTimeTableProvider(2026).future);
/// final year = table.yearOf(2026);      // 2026-09-07 起，结束日 null
/// final breaks = table.breaksOf(2026);  // 寒假 / 暑假
/// ```
export 'package:smarter_jxufe/features/school_calendar/domain/school_time.dart';

/// 一个学年要问的三个学段（0 第一学期 / 1 第二学期 / 2 第二阶段）。
const List<int> schoolYearTermSegments = [0, 1, 2];

/// [xn] 学年的学校时间表。
final schoolTimeTableProvider =
    FutureProvider.family<SchoolTimeTable, int>((ref, xn) async {
  Future<SchoolCalendar?> take(int yn, int xq) async {
    try {
      return await ref.read(
        schoolCalendarProvider((xn: yn, xq: xq)).future,
      );
    } catch (_) {
      // 未公布（空壳页 → SchoolCalendarException）或网络失败：跳过该学段。
      return null;
    }
  }

  final calendars = <SchoolCalendar>[];
  for (final xq in schoolYearTermSegments) {
    final calendar = await take(xn, xq);
    if (calendar != null) calendars.add(calendar);
  }
  final nextFirst = await take(xn + 1, 0);
  if (nextFirst != null) calendars.add(nextFirst);

  return SchoolTimeTable.fromCalendars(calendars);
});

/// 单个学年（[schoolTimeTableProvider] 的便捷投影）。
final schoolYearProvider =
    FutureProvider.family<SchoolYear, int>((ref, xn) async {
  final table = await ref.watch(schoolTimeTableProvider(xn).future);
  return table.yearOf(xn);
});

/// 一个学年的假期（寒假 / 暑假）。
final schoolBreaksProvider =
    FutureProvider.family<List<SchoolBreak>, int>((ref, xn) async {
  final table = await ref.watch(schoolTimeTableProvider(xn).future);
  return table.breaksOf(xn);
});
