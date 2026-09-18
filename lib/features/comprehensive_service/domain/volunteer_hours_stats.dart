/// 志愿时长统计口径：全部累计 + 本学年（+ 上一学年对照）。
///
/// **「本学年」= 当下教学学年**（`currentSchoolTerm` 给出的学年起始年 `xn`，
/// 口径与课表 / 校历 / 今日课程一致），窗口 `[xn]-09-01 ~ [xn+1]-08-31`。
/// ⚠ 别用综测模块的 `zcDefaultYear`（那是**测评学年**：9 月起评的是刚结束的
/// 那一学年，2026-09 时它给 2025-2026）—— 2026-09-16 实测踩过：卡片标着「本学年」
/// 却显示上学年的 24 小时，属口径错用。
///
/// 活动日期来自列表页逐行「详情」页的 `startTime`/`endTime`（列表本身没有时间列），
/// 一条都取不到时 [VolunteerHoursStats.yearKnown] 为 false，界面应显示「—」
/// 而不是 0（避免把「取不到日期」误报成「本学年 0 小时」）。
library;

import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart'
    show xnDisplayName;

/// 志愿时长统计结果。
class VolunteerHoursStats {
  /// 全部活动认定时长合计（小时）。
  final double total;

  /// 归入**本学年**的活动认定时长合计（小时）。
  final double currentYear;

  /// 归入**上一学年**的活动认定时长合计（小时）——仅用于界面对照说明，
  /// 避免「本学年 0 小时」被误读成「平台里什么都没有」。
  final double previousYear;

  /// 本学年起始年（`xn`）：2026 → 2026-2027 学年。
  final int xn;

  /// 是否至少有一条活动能解析出日期（false = 本学年无法判定）。
  final bool yearKnown;

  const VolunteerHoursStats({
    required this.total,
    required this.currentYear,
    required this.previousYear,
    required this.xn,
    required this.yearKnown,
  });

  /// 如「2026-2027学年」（走校历侧的 `xnDisplayName`，不加空格）。
  String get yearLabel => xnDisplayName(xn);

  /// 上一学年标签，如「2025-2026学年」。
  String get previousYearLabel => xnDisplayName(xn - 1);
}

/// 学年窗口：`[xn]-09-01 ~ [xn+1]-08-31`（含首尾两天）。
bool _inYear(DateTime d, int xn) {
  final start = DateTime(xn, 9, 1);
  final end = DateTime(xn + 1, 8, 31, 23, 59, 59);
  return !d.isBefore(start) && !d.isAfter(end);
}

/// 按活动日期归集「全部 / 本学年 / 上一学年」志愿时长。
///
/// [xn] = 当下学年起始年（由 `currentSchoolTerm(now).xn` 传入）。
VolunteerHoursStats volunteerHoursStats(
  List<VolunteerActivity> activities, {
  required int xn,
}) {
  var total = 0.0;
  var currentYear = 0.0;
  var previousYear = 0.0;
  var yearKnown = false;
  for (final activity in activities) {
    total += activity.hours;
    final date = activity.activityDate;
    if (date == null) continue;
    yearKnown = true;
    if (_inYear(date, xn)) {
      currentYear += activity.hours;
    } else if (_inYear(date, xn - 1)) {
      previousYear += activity.hours;
    }
  }
  return VolunteerHoursStats(
    total: total,
    currentYear: currentYear,
    previousYear: previousYear,
    xn: xn,
    yearKnown: yearKnown,
  );
}
