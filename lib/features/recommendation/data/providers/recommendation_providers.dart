/// 推免成绩模块 —— providers（资料库定位 → 解析 → 推免加权取数）。
///
/// 「自动从资料库获取」的落点就在本文件：**文档不是写死的资产路径**，而是先读
/// `rulesCatalogProvider`（`assets/rules/meta/rules_catalog.json` 的运行时形态），
/// 按分类/家族名找到那份办法，再用它的 `mdAsset` 读正文（见用户 2026-09-17 口径：
/// 「自动从资料库里获取加分项 / 具体加分项参考 app 目前『规章制度』部分」）。
/// 学校把新版办法放回资料库后，这里无需改代码即可跟着更新。
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/grades/data/providers/curriculum_importance_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/recommendation_weighted.dart';
import 'package:smarter_jxufe/features/rules/data/rules_repository.dart';
import 'package:smarter_jxufe/features/rules/domain/rule_doc.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_providers.dart';

import '../../domain/bonus_catalog.dart';
import '../bonus_catalog_parser.dart';

/// 资料库中承载「推免附加分标准」的那份文档。
///
/// 定位顺序：① 分类「升学推免」下的家族 → ② 家族名含「推免」→ ③ 标题含「免试攻读」。
/// 取家族的 `defaultDoc`（catalog 里标注的最新修订版正文，不是印发通知）。
final recommendationRuleDocProvider = FutureProvider<RuleDoc?>((ref) async {
  final catalog = await ref.watch(rulesCatalogProvider.future);
  for (final family in catalog.families) {
    if (family.group == '升学推免' || family.name.contains('推免')) {
      return family.defaultDoc;
    }
  }
  for (final doc in catalog.docs) {
    if (doc.title.contains('免试攻读') || doc.title.contains('推免')) return doc;
  }
  return null;
});

/// 推免附加分目录（解析自资料库文档；解析失败 = [BonusCatalog.empty]）。
final bonusCatalogProvider = FutureProvider<BonusCatalog>((ref) async {
  final doc = await ref.watch(recommendationRuleDocProvider.future);
  if (doc == null) return BonusCatalog.empty;
  try {
    return parseBonusCatalog(await rootBundle.loadString(doc.mdAsset));
  } catch (e) {
    return BonusCatalog.empty;
  }
});

/// 推免加权取数结果（含「培养方案是否就绪」这一必需信息）。
class RecommendationWeightedResult {
  final RecommendationWeighted weighted;

  /// 培养方案（课程地位）是否可用；false 时 [weighted] 无意义，页面必须提示。
  final bool importanceAvailable;

  /// 参与计算的门数（供页面显示「N 门主干 + M 门非主干」）。
  int get courseCount => weighted.totalCount;

  const RecommendationWeightedResult({
    required this.weighted,
    required this.importanceAvailable,
  });

  static const RecommendationWeightedResult unavailable =
      RecommendationWeightedResult(
        weighted: RecommendationWeighted.zero,
        importanceAvailable: false,
      );
}

/// 推免加权平均成绩（主干×0.7 + 非主干×0.3）——**离线**取数：
/// 成绩来自成绩缓存（`gePriorGradesProvider`，账号隔离、已排除名单），
/// 课程地位来自本专业培养方案缓存（`curriculumImportanceMapProvider`）。
final recommendationWeightedResultProvider =
    FutureProvider<RecommendationWeightedResult>((ref) async {
      final grades = await ref.watch(gePriorGradesProvider.future);
      final importance = await ref.watch(curriculumImportanceMapProvider.future);
      if (importance == null) return RecommendationWeightedResult.unavailable;
      final weighted = recommendationWeightedOf(
        courses: [
          for (final g in grades)
            RecommendationCourse(
              courseCode: g.courseCode,
              courseName: g.courseName,
              score: g.score,
              credits: g.credits,
            ),
        ],
        importance: importance,
      );
      return RecommendationWeightedResult(
        weighted: weighted,
        importanceAvailable: true,
      );
    });
