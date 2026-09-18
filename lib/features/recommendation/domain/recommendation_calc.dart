/// 推免成绩模块 —— 附加分与综合成绩计算（**纯函数，唯一实现**）。
///
/// 办法原文（《推免工作办法（2024年修订）》）：
/// - 第十五条：`综合成绩 = 推免加权平均成绩 + 附加分`；
/// - 第十条：附加分分竞赛类、专利类、著作权类、综合类、学术科研类，
///   **每一类别只计一项，不累加**；**附加分总分 10 分封顶**（超过者以 10 分计算）；
/// - 竞赛类：分值按获奖等级（金奖 10 / 银奖 7 / …）× 排名系数
///   （第 1 名 1.0、第 2 名 0.9 … 第 11-15 名 0.1、第 16 名及以后不加分）；
///   2025-01-01 **之前**取得的获奖，排名第 6 及以后者为满分 ×0.5（注 2）；
///   竞赛类「以最高分计入，不累加」（注 3）。
///
/// 计算分三层（页面三块卡就按这三层展示，别在 UI 里再算一遍）：
/// 1. [BonusItemOutcome]：每条自己的结算分（含排名系数）；
/// 2. `categoryBest`：每类只留最高的一条 = 办法口径；
/// 3. `categorySum`：同一条目**若按累加**会是多少（含小类上限），仅作对照展示，
///    并在 UI 注明「办法规定不累加，此列仅供对照」。
library;

import 'bonus_catalog.dart';
import 'recommendation_item.dart';

/// 单条加分项的结算结果。
class BonusItemOutcome {
  final RecommendationBonusItem item;

  /// 目录里的基准分（未乘排名系数）；资料库里找不到该项时为 null。
  final double? basePoints;

  /// 排名系数（仅竞赛类）。
  final double factor;

  /// 最终分值（未计入时为 0）。
  final double points;

  /// 是否被计入「办法口径」的附加分（每类只取最高的一条）。
  final bool counted;

  /// 结果说明（计入 / 不累加 / 排名不加分 / 项目已失效…）。
  final String reason;

  /// 该条同类里是否存在更高的条目（用于「被舍去」的展示）。
  final double? categoryMax;

  const BonusItemOutcome({
    required this.item,
    required this.basePoints,
    required this.factor,
    required this.points,
    required this.counted,
    required this.reason,
    this.categoryMax,
  });

  bool get superseded => !counted && points > 0;

  String get label => item.optionLabel.isEmpty ? '(未命名项目)' : item.optionLabel;
}

/// 推免成绩总结果。
class RecommendationOutcome {
  /// 推免加权平均成绩（来自 [recommendationWeightedOf]，本函数不自己算）。
  final double weightedAverage;

  /// 附加分（**已封顶**）。
  final double bonusTotal;

  /// 附加分（封顶前）。
  final double uncappedBonus;

  /// 是否触发了 10 分封顶。
  final bool capped;

  /// 综合成绩 = [weightedAverage] + [bonusTotal]。
  final double total;

  final List<BonusItemOutcome> items;

  /// 办法口径：每类只计一项（取最高）后的各类分值。
  final Map<BonusCategory, double> categoryBest;

  /// 对照口径：同类条目累加（专利/著作权/学术科研的小类上限已生效）。
  final Map<BonusCategory, double> categorySum;

  /// 需要提醒用户的点（未填排名按第 1 名、项目已不在资料库、按旧规则折算…）。
  final List<String> warnings;

  const RecommendationOutcome({
    required this.weightedAverage,
    required this.bonusTotal,
    required this.uncappedBonus,
    required this.capped,
    required this.total,
    required this.items,
    required this.categoryBest,
    required this.categorySum,
    this.warnings = const [],
  });

  bool get hasItems => items.isNotEmpty;
}

/// 计算推免成绩。
RecommendationOutcome recommendationOutcomeOf({
  required double weightedAverage,
  required List<RecommendationBonusItem> items,
  required BonusCatalog catalog,
}) {
  final warnings = <String>[];
  final perItem = <BonusItemOutcome>[];

  // 第一层：逐条结算。
  final temp = <({RecommendationBonusItem item, double? base, double factor, double points, String? reason})>[];
  for (final item in items) {
    final option = catalog.optionById(item.optionId);
    if (option == null) {
      temp.add((
        item: item,
        base: null,
        factor: 1,
        points: 0,
        reason: '资料库里已找不到该项目（加分标准可能已更新）',
      ));
      continue;
    }
    final base = option.pointsOf(item.tierLabel);
    if (base == null) {
      temp.add((
        item: item,
        base: null,
        factor: 1,
        points: 0,
        reason: '未选择获奖等级，无法计分',
      ));
      continue;
    }
    var factor = 1.0;
    String? reason;
    if (item.category == BonusCategory.contest) {
      var rank = item.rank;
      if (rank == null) {
        rank = 1;
        warnings.add('「${item.optionLabel}」未填排名，已按第 1 名（满分）计算');
      }
      factor = catalog.contestFactor(rank: rank, awardDate: item.awardDate);
      if (factor == 0) {
        reason = '排名第 $rank 名及以后不加分';
      } else if (item.awardDate != null &&
          item.awardDate!.isBefore(catalog.legacyCutoff) &&
          rank >= 6) {
        reason = '2025-01-01 前获奖，排名第 6 及以后按满分 ×${_f(catalog.legacyFactor)}';
      } else {
        reason = '排名第 $rank 名，系数 ×${_f(factor)}';
      }
    }
    temp.add((
      item: item,
      base: base,
      factor: factor,
      points: base * factor,
      reason: reason,
    ));
  }

  // 第二层：每类取最高（办法口径）+ 同类累加（对照口径）。
  final categoryBest = <BonusCategory, double>{};
  final categorySum = <BonusCategory, double>{};
  for (final c in BonusCategory.values) {
    final ofCategory = [
      for (final t in temp)
        if (t.item.category == c) t,
    ];
    if (ofCategory.isEmpty) continue;
    var best = 0.0;
    for (final t in ofCategory) {
      if (t.points > best) best = t.points;
    }
    categoryBest[c] = best;
    categorySum[c] = _categorySum(c, ofCategory, catalog);
  }

  final countedCategories = <BonusCategory>{};
  for (final t in temp) {
    final best = categoryBest[t.item.category] ?? 0;
    final isTop = t.points > 0 && t.points >= best;
    // 同分并列时只算**第一条**（其余标注为不累加），避免同一类被重复计入展示。
    final counted = isTop && !countedCategories.contains(t.item.category);
    if (counted) countedCategories.add(t.item.category);
    final reason = t.reason ??
        (t.points > 0 ? '计入附加分' : '该项分值 0，未计入');
    perItem.add(
      BonusItemOutcome(
        item: t.item,
        basePoints: t.base,
        factor: t.factor,
        points: t.points,
        counted: counted,
        reason: counted ? reason : '$reason（同类只计一项，不累加）',
        categoryMax: best,
      ),
    );
  }

  // 第三层：封顶。
  final uncapped = categoryBest.values.fold<double>(0, (a, b) => a + b);
  final capped = uncapped > catalog.cap;
  return RecommendationOutcome(
    weightedAverage: weightedAverage,
    bonusTotal: capped ? catalog.cap : uncapped,
    uncappedBonus: uncapped,
    capped: capped,
    total: weightedAverage + (capped ? catalog.cap : uncapped),
    items: perItem,
    categoryBest: categoryBest,
    categorySum: categorySum,
    warnings: warnings,
  );
}

/// 同类累加（对照口径）：专利/著作权有「小类上限」，其余按条累加。
double _categorySum(
  BonusCategory category,
  List<({RecommendationBonusItem item, double? base, double factor, double points, String? reason})> items,
  BonusCatalog catalog,
) {
  if (category == BonusCategory.patent) {
    // 按小类分别累加并各自封顶（发明专利无上限，实用新型 0.6，外观设计 1）。
    final byGroup = <String, double>{};
    final byGroupCap = <String, double?>{};
    for (final t in items) {
      final option = catalog.optionById(t.item.optionId);
      final group = option?.group ?? '发明专利';
      byGroup[group] = (byGroup[group] ?? 0) + t.points;
      byGroupCap[group] = option?.capNote ?? byGroupCap[group];
    }
    var total = 0.0;
    for (final e in byGroup.entries) {
      final cap = byGroupCap[e.key];
      total += (cap != null && e.value > cap) ? cap : e.value;
    }
    return total;
  }
  var total = 0.0;
  double? cap;
  for (final t in items) {
    total += t.points;
    cap ??= catalog.optionById(t.item.optionId)?.capNote;
  }
  if (cap != null && total > cap) return cap;
  return total;
}

String _f(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
