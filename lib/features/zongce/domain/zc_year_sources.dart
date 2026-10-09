/// 综测自动源的**学年口径**（用户 2026-09-16 裁定：「综测按学年算」）。
///
/// 与材料归属同一套窗口：测评学年 `yearEnd` 覆盖
/// `[yearEnd-1]` 学年第一学期第一天 ~ `[yearEnd]` 学年第一学期第一天 − 1 天
/// （校历取不到时退回 `[yearEnd-1]-09-01 ~ [yearEnd]-08-31`）。
/// **窗口与学期标识的唯一出处 = `school_calendar/domain/school_time.dart`**
/// （`schoolYearOrFallback` / `schoolYearStartOf`；本模块只转发）。
///
/// 从前两处自动源用的是**跨学年累计**：智育加权走教务「全部课程加权」
/// （typeId 1）、劳育志愿走第二课堂全部活动的时长求和 —— 与综测「评的是
/// 某一个学年」的口径不符。这里把两者都收窄到**单个测评学年**。
///
/// 本文件是纯函数（不碰 provider / 不联网），便于单测。
library;

import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';
import 'package:smarter_jxufe/features/comprehensive_service/domain/volunteer_hours_stats.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_prior_grades.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_time.dart'
    show SchoolTimeTable, schoolYearOfTermText;

/// 学期标识 → **学年起始年**（如 `'251'` → 2025，即 2025-2026 学年）。
///
/// ⚠ 2026-09-27 起**唯一实现在 `school_calendar/domain/school_time.dart`**
/// （`schoolYearOfTermText`）—— 本函数只是转发别名，别再往这里加分支。
int? zcSemesterStartYear(String semester) => schoolYearOfTermText(semester);

/// 把成绩按**测评学年**归年：该学年的课 + 学期码认不出的课。
///
/// ⚠ **「哪些课属于这个学年」的唯一实现**（[zcWeightedForYear] 与
/// [zcYearGradeStats] 都走它，别再各写一套判据）。
///
/// - [graded]：学期码认得出且起始年 == `yearEnd - 1` 的课；
/// - [unknown]：学期码认不出的课 —— 成绩页「课程加权」从不按学年过滤，
///   漏掉它们智育就会与成绩页对不上（实测该账号漏 1 门 2 学分的实训课）；
/// - [yearKnown]：该学年**至少有一门**学期码明确的课。false 时不要拿
///   `unknown` 去凑数 —— 否则一门认不出学期的课会把每个学年都凑出一个分。
({List<GePriorGrade> graded, List<GePriorGrade> unknown, bool yearKnown})
zcGradesOfYear(List<GePriorGrade> grades, {required int yearEnd}) {
  final graded = <GePriorGrade>[];
  final unknown = <GePriorGrade>[];
  for (final g in grades) {
    final startYear = zcSemesterStartYear(g.semester);
    if (startYear == null) {
      unknown.add(g);
      continue;
    }
    if (startYear == yearEnd - 1) graded.add(g);
  }
  return (graded: graded, unknown: unknown, yearKnown: graded.isNotEmpty);
}

/// 测评学年 [yearEnd] 的**课程加权平均**（Σ 成绩×学分 ÷ Σ 学分）。
///
/// 口径 = 成绩页「课程加权」（`grades_screen.dart` 的 `_calcAvgScore`：
/// 教务已出成绩按学分加权、排除名单内的课程不计入），**再收窄到该学年**。
/// 用户 2026-09-17 裁定：「综测页智育部分自动获取的成绩应该是课程加权，
/// 而不是推免加权」——推免口径是 `_calcRecommendationScore` 的
/// `0.7×主干课均分 + 0.3×非主干课均分`，与本函数无关。
///
/// - 学分为 0（缺学分）的课程不计入权重，避免一票 0 分拉垮；
/// - 该学年一门学期码明确的课都没有 → null → 界面回退手动填写，
///   **不要报 0 分**（与 [zcVolunteerHoursForYear] 同一约定）。
///
/// 学期与学年的对应关系注意：`yearEnd` 2026（= 2025-2026 学年）看的是
/// 学期码 `'251'/'252'/'253'`，即**起始年 2025**。
double? zcWeightedForYear(List<GePriorGrade> grades, {required int yearEnd}) {
  final split = zcGradesOfYear(grades, yearEnd: yearEnd);
  if (!split.yearKnown) return null;
  var weighted = 0.0;
  var credits = 0.0;
  for (final g in [...split.graded, ...split.unknown]) {
    if (g.credits <= 0) continue;
    weighted += g.score * g.credits;
    credits += g.credits;
  }
  return credits > 0 ? weighted / credits : null;
}

/// 测评学年 [yearEnd] 的**成绩单统计**（填《先进个人登记表》那一行要用）。
///
/// [minScore] = 最低单科成绩、[credits] = 学年所修学分总数（Σ 学分）、
/// [hasFail] = 有没有挂科。三者都只在 [zcGradesOfYear] 归出来的课上算。
///
/// ⚠ **`score <= 0` 的课一律跳过**：`gePriorGradesFromBox` 把认不出的成绩
/// （`优秀` / `合格` / `缓考`）按 0 分存（`double.tryParse(...) ?? 0`），
/// 拿它们去取最小值会把「最低单科成绩」算成 0、还会谎报挂科。
List<GePriorGrade> zcYearGrades(
  List<GePriorGrade> grades, {
  required int yearEnd,
}) {
  final split = zcGradesOfYear(grades, yearEnd: yearEnd);
  if (!split.yearKnown) return const [];
  return [...split.graded, ...split.unknown];
}

/// 学年成绩三项统计（见 [zcYearGrades] 的口径）。
({double? minScore, double? credits, bool hasFail}) zcYearGradeStats(
  List<GePriorGrade> grades, {
  required int yearEnd,
}) {
  final list = zcYearGrades(grades, yearEnd: yearEnd);
  double? min;
  var credits = 0.0;
  var hasFail = false;
  for (final g in list) {
    if (g.credits > 0) credits += g.credits;
    if (g.score <= 0) continue; // 非数字成绩（优秀/合格/缓考）按 0 存 → 不算
    if (min == null || g.score < min) min = g.score;
    if (g.score < 60) hasFail = true;
  }
  return (
    minScore: min,
    credits: credits > 0 ? credits : null,
    hasFail: hasFail,
  );
}

/// 测评学年 [yearEnd] 内认定的志愿时长（小时，第二课堂活动口径）。
///
/// 活动按**活动日期**（详情页的开始/结束时间）归入学年窗口 ——
/// 窗口的唯一实现在 `school_calendar/domain/school_time.dart`：
/// 传了 [table] 用真实窗口 `[yearEnd-1] 第一学期第一天 ~ [yearEnd] 学年第一天前一天`，
/// 没传则退回 `[yearEnd-1]-09-01 ~ [yearEnd]-08-31`（纯函数调用方的兜底）。
/// 一条日期都取不到 → null（无法判定，界面回退手动填写，**别显示 0**）。
double? zcVolunteerHoursForYear(
  List<VolunteerActivity> activities, {
  required int yearEnd,
  SchoolTimeTable? table,
}) {
  final stats = volunteerHoursStats(
    activities,
    xn: yearEnd - 1,
    table: table,
  );
  if (!stats.yearKnown) return null;
  return stats.currentYear;
}
