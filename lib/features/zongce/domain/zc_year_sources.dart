/// 综测自动源的**学年口径**（用户 2026-09-16 裁定：「综测按学年算」）。
///
/// 与材料归属同一套窗口：测评学年 `yearEnd` 覆盖
/// `[yearEnd-1]-09-01 ~ [yearEnd]-08-31`（见 `zc_models.dart` 的
/// [zcYearWindowContains] / [zcDefaultYear] / [zcYearLabel]）。
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

/// 学期标识 → **学年起始年**（如 `'251'` → 2025，即 2025-2026 学年）。
///
/// 支持两种写法：
/// - 成绩数据里的**短编号** `'yy' + 学段(1|2|3)`，如 `'251'`（2025-2026 第一学期）、
///   `'252'`（第二学期）；学段 3 = 第二阶段，仍属同一学年。
/// - 完整学期名 `'2025-2026学年第一学期'`。
///
/// 认不出（空串 / 其它格式）→ null（调用方按「不属于该学年」处理，
/// **不要**当成默认年份，否则会把别的学年的课算进来）。
int? zcSemesterStartYear(String semester) {
  final raw = semester.trim();
  if (raw.isEmpty) return null;
  final short = RegExp(r'^(\d{2})[1-3]$').firstMatch(raw);
  if (short != null) return 2000 + int.parse(short.group(1)!);
  final full = RegExp(r'^(\d{4})-\d{4}\s*学年').firstMatch(raw);
  if (full != null) return int.parse(full.group(1)!);
  return null;
}

/// 测评学年 [yearEnd] 的**课程加权平均**（Σ 成绩×学分 ÷ Σ 学分）。
///
/// 口径 = 成绩页「课程加权」（`grades_screen.dart` 的 `_calcAvgScore`：
/// 教务已出成绩按学分加权、排除名单内的课程不计入），**再收窄到该学年**。
/// 用户 2026-09-17 裁定：「综测页智育部分自动获取的成绩应该是课程加权，
/// 而不是推免加权」——推免口径是 `_calcRecommendationScore` 的
/// `0.7×主干课均分 + 0.3×非主干课均分`，与本函数无关。
///
/// - 只统计学期落在该学年的课程（学期起始年 == `yearEnd - 1`）；
/// - **学期认不出的课程并入该学年**（成绩页「课程加权」从不按学年过滤，
///   漏掉它们智育就会与成绩页对不上：实测该账号漏 1 门 2 学分的实训课 →
///   91.89091，而成绩页课程加权是 91.85965）；但若该学年**一门学期码明确的
///   课都没有**，仍是 null —— 免得一门认不出学期的课把每个学年都凑出一个分；
/// - 学分为 0（缺学分）的课程不计入权重，避免一票 0 分拉垮；
/// - 没有任何有效课程（或总学分为 0）→ null → 界面回退手动填写，
///   **不要报 0 分**（与 [zcVolunteerHoursForYear] 同一约定）。
///
/// 学期与学年的对应关系注意：`yearEnd` 2026（= 2025-2026 学年）看的是
/// 学期码 `'251'/'252'/'253'`，即**起始年 2025**。
double? zcWeightedForYear(List<GePriorGrade> grades, {required int yearEnd}) {
  var weighted = 0.0;
  var credits = 0.0;
  var unknownWeighted = 0.0;
  var unknownCredits = 0.0;
  var known = 0;
  for (final g in grades) {
    if (g.credits <= 0) continue;
    final startYear = zcSemesterStartYear(g.semester);
    if (startYear == null) {
      unknownWeighted += g.score * g.credits;
      unknownCredits += g.credits;
      continue;
    }
    if (startYear != yearEnd - 1) continue;
    known++;
    weighted += g.score * g.credits;
    credits += g.credits;
  }
  // 该学年没有学期码明确的课 → 无从判定，界面回退手动填写。
  if (known == 0) return null;
  weighted += unknownWeighted;
  credits += unknownCredits;
  return credits > 0 ? weighted / credits : null;
}

/// 测评学年 [yearEnd] 内认定的志愿时长（小时，第二课堂活动口径）。
///
/// 活动按**活动日期**（详情页的开始/结束时间）归入学年窗口
/// `[yearEnd-1]-09-01 ~ [yearEnd]-08-31`；一条日期都取不到 → null
/// （无法判定，界面回退手动填写，**别显示 0**）。
double? zcVolunteerHoursForYear(
  List<VolunteerActivity> activities, {
  required int yearEnd,
}) {
  final stats = volunteerHoursStats(activities, xn: yearEnd - 1);
  if (!stats.yearKnown) return null;
  return stats.currentYear;
}
