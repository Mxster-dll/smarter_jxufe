/// 分数估计 · 总加权平均汇总（列表页与课程详情页共用同一口径）。
///
/// 口径（与成绩页一致，勿在界面层各自实现）：
/// - **教务已出成绩全量计入**（按成绩页排除名单过滤后的全部课程，含往期学期）；
/// - 本模块课程与教务同名时由真实成绩计入，不重复；
/// - 未填期末 / 学分为 0 的课程不计入，但计入 [GeSummaryData.pendingCount]；
/// - 估计侧学分按**本专业培养方案优先**（[geEffectiveCredits]），未匹配回退课程自身学分。
library;

import '../domain/ge_engine.dart';
import '../domain/ge_models.dart';
import 'ge_curriculum.dart';
import 'ge_prior_grades.dart';

/// 汇总结果。
class GeSummaryData {
  /// 学分加权汇总（平均分、参与构成、逐课贡献）。
  final GeWeightedSummary summary;

  /// 本模块中「未计入合计」的课程数：未填期末，或学分为 0。
  final int pendingCount;

  const GeSummaryData({required this.summary, this.pendingCount = 0});
}

/// 计算总加权平均（列表页顶部汇总卡 / 详情页汇总卡 / 未来他处一律走这里）。
GeSummaryData geSummarize({
  required List<GePriorGrade> prior,
  required List<GeCourse> courses,
  GeCurriculumIndex index = const GeCurriculumIndex.empty(),
}) {
  final summary = geWeightedSummary(
    geMergeWeightItems(
      priorItems: [
        for (final p in prior)
          GeWeightItem(
            name: p.courseName,
            score: p.score,
            credits: p.credits,
            fromGrades: true,
          ),
      ],
      courses: [
        for (final c in courses)
          c.copyWith(credits: geEffectiveCredits(index, c).credits),
      ],
    ),
  );

  // 与 geMergeWeightItems 的排除条件保持一致（同名由教务成绩计入 → 不算未计入）。
  final priorNames = {for (final p in prior) p.courseName.trim()};
  var pending = 0;
  for (final c in courses) {
    if (priorNames.contains(c.name.trim())) continue;
    final credits = geEffectiveCredits(index, c).credits;
    if (credits <= 0 || geTotalWithFinal(geCalc(c), c.finalScore) == null) {
      pending++;
    }
  }

  return GeSummaryData(summary: summary, pendingCount: pending);
}
