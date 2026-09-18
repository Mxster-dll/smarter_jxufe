/// 推免加权平均成绩口径 —— **唯一实现**（成绩页与推免成绩页共用）。
///
/// 2026-09-17 从 `lib/features/ims/grades/presentation/grades_screen.dart` 的
/// `_calcRecommendationScore` 原样抽出：新功能「推免成绩」要显示同一个数字，
/// 两处各写一份必然漂移（成绩页显示 91.86、推免页显示别的值 = 用户不信任）。
///
/// 口径（与成绩页逐值一致）：
/// 1. 先按 [kExcludedGradeCourses] 排除军事训练 / 创新创业实践活动 / 毕业设计 / 毕业论文；
/// 2. 按培养方案的「课程地位」(`CourseImportance`) 分**主干**与**非主干**
///    （`core` 归主干，其余含 `general`/`unknown` 归非主干）；
/// 3. 主干加权 = Σ(成绩×学分)/Σ学分，非主干同理；
/// 4. **推免加权 = 主干×0.7 + 非主干×0.3**。
///
/// ⚠ 这与「课程加权（全部课程）」不是一个口径，也与综测的智育口径不同
/// （用户 2026-09-17 裁定：综测智育用课程加权，不是推免加权）。
library;

import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';

import 'grades_exclusions.dart';

/// 参与推免加权计算的一门课（把 `Grade` / `GePriorGrade` 归一到这里，
/// 避免本函数依赖任一模块的模型）。
class RecommendationCourse {
  final String courseCode;
  final String courseName;
  final double score;
  final double credits;

  const RecommendationCourse({
    required this.courseCode,
    required this.courseName,
    required this.score,
    required this.credits,
  });
}

/// 推免加权结果（含主干/非主干明细，供页面展开说明）。
class RecommendationWeighted {
  final double coreAverage;
  final double nonCoreAverage;
  final double coreCredits;
  final double nonCoreCredits;
  final int coreCount;
  final int nonCoreCount;

  /// 推免加权平均成绩（= [coreAverage]×0.7 + [nonCoreAverage]×0.3）。
  final double score;

  /// 参与计算的课程总学分（主干 + 非主干）。
  double get totalCredits => coreCredits + nonCoreCredits;

  int get totalCount => coreCount + nonCoreCount;

  const RecommendationWeighted({
    required this.coreAverage,
    required this.nonCoreAverage,
    required this.coreCredits,
    required this.nonCoreCredits,
    required this.coreCount,
    required this.nonCoreCount,
    required this.score,
  });

  static const RecommendationWeighted zero = RecommendationWeighted(
    coreAverage: 0,
    nonCoreAverage: 0,
    coreCredits: 0,
    nonCoreCredits: 0,
    coreCount: 0,
    nonCoreCount: 0,
    score: 0,
  );

  bool get hasData => totalCount > 0;
}

/// 主干/非主干权重（办法：推免加权 = 主干×0.7 + 非主干×0.3）。
const double kRecommendationCoreWeight = 0.7;
const double kRecommendationNonCoreWeight = 0.3;

/// 计算推免加权平均成绩。
RecommendationWeighted recommendationWeightedOf({
  required Iterable<RecommendationCourse> courses,
  required Map<String, CourseImportance> importance,
  Set<String>? excludedCourseNames,
}) {
  final excluded = excludedCourseNames ?? kExcludedGradeCourses;
  double coreCredit = 0, coreScoreCredit = 0;
  double nonCoreCredit = 0, nonCoreScoreCredit = 0;
  var coreCount = 0, nonCoreCount = 0;

  for (final c in courses) {
    if (excluded.contains(c.courseName)) continue;
    final credit = c.credits;
    if (credit <= 0) continue;
    final score = c.score;
    if (importance[c.courseCode] == CourseImportance.core) {
      coreCredit += credit;
      coreScoreCredit += score * credit;
      coreCount++;
    } else {
      nonCoreCredit += credit;
      nonCoreScoreCredit += score * credit;
      nonCoreCount++;
    }
  }

  final coreAverage = coreCredit > 0 ? coreScoreCredit / coreCredit : 0.0;
  final nonCoreAverage = nonCoreCredit > 0
      ? nonCoreScoreCredit / nonCoreCredit
      : 0.0;
  return RecommendationWeighted(
    coreAverage: coreAverage,
    nonCoreAverage: nonCoreAverage,
    coreCredits: coreCredit,
    nonCoreCredits: nonCoreCredit,
    coreCount: coreCount,
    nonCoreCount: nonCoreCount,
    score:
        coreAverage * kRecommendationCoreWeight +
        nonCoreAverage * kRecommendationNonCoreWeight,
  );
}
