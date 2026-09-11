/// 分数估计 · 估算引擎（纯函数，无 IO / 无 UI 依赖，全部可单测）。
///
/// ## 口径定义
/// 分项 i：得分率 r_i = clamp(当前值 / 目标值, 0, 1)（正计数超额同样封顶），
/// 得分 s_i = r_i × 分值上限 c_i。
/// 「当前值」按计分方式取：正/负计数取次数，直接分数取实际得分（目标值即该项满分）。
///
/// 平时：分值合计 C = Σc_i，得分合计 S = Σs_i，
/// 平时均分 M = S / C × 100（百分制；无分项时视为 0）。
///
/// 总评 = M × 平时占比 + F × 期末占比，F 为期末成绩（百分制）。
/// 例：平时占 30%、分项满分合计 30、已得 25 → M = 83.33，
/// 总评（期末 80）= 83.33×0.3 + 80×0.7 = 25 + 56 = 81。
///
/// 注：「可达上限」＝把还能再挣的分项补满后的最好情况：正计数与直接分数
/// 未拿满的部分算可补（次数还能再刷、分数还能再挣），负计数已扣减的部分
/// 不可挽回（维持现状）。
library;

import 'ge_models.dart';

/// 分项得分率（0~1，封顶）；[target] 非法（≤0）时视为「无目标 = 满分」。
///
/// - 正/负计数：计数 / 目标（负计数的「当前」即剩余次数）；
/// - 直接分数：实际得分 / 该项满分（如 85 / 100 → 0.85）。
double gePartRatio(GePart p) {
  switch (p.mode) {
    case GePartMode.up:
    case GePartMode.down:
      return p.target <= 0 ? 1.0 : (p.current / p.target).clamp(0.0, 1.0);
    case GePartMode.score:
      return p.target <= 0 ? 1.0 : (p.score / p.target).clamp(0.0, 1.0);
  }
}

/// 分项得分 = 得分率 × 分值上限。
double gePartScore(GePart p) => gePartRatio(p) * p.cap;

/// 一次课程静态测算快照（由 [geCalc] 纯函数生成）。
class GeCalc {
  /// 平时分项分值合计（平时满分）。
  final double capSum;

  /// 平时分项已得合计。
  final double scoreSum;

  /// 平时均分（百分制，0~100）。
  final double dailyMean;

  /// 平时折算总评点 = 平时均分 × 平时占比。
  final double dailyContrib;

  /// 还可再挣的分值合计（= Σ (1−r_i)c_i，正计数与直接分数项；负计数不回）。
  final double gainableCap;

  /// 均分可达上限：把可补分项（正计数 / 直接分数）拿满后的平时均分。
  final double meanCeiling;

  /// 平时折算可达上限（总评点）。
  final double dailyCeiling;

  /// 期末占比权重（如 0.7）。
  final double finalWeight;

  /// 期末折算 = 期末分 × 期末占比。
  double finalContrib(double finalScore) => finalScore * finalWeight;

  const GeCalc({
    required this.capSum,
    required this.scoreSum,
    required this.dailyMean,
    required this.dailyContrib,
    required this.gainableCap,
    required this.meanCeiling,
    required this.dailyCeiling,
    required this.finalWeight,
  });
}

/// 计算课程当前静态测算快照。
GeCalc geCalc(GeCourse c) {
  var capSum = 0.0;
  var scoreSum = 0.0;
  var gainableCap = 0.0;
  for (final p in c.parts) {
    final s = gePartScore(p);
    capSum += p.cap;
    scoreSum += s;
    if (p.mode != GePartMode.down && p.target > 0) {
      gainableCap += (1 - gePartRatio(p)) * p.cap;
    }
  }
  final dailyMean = capSum > 0 ? scoreSum / capSum * 100 : 0.0;
  final gainableMean = capSum > 0 ? gainableCap / capSum * 100 : 0.0;
  final dp = c.dailyPercent.clamp(0.0, 100.0) / 100;
  return GeCalc(
    capSum: capSum,
    scoreSum: scoreSum,
    dailyMean: dailyMean,
    dailyContrib: dailyMean * dp,
    gainableCap: gainableCap,
    meanCeiling: dailyMean + gainableMean,
    dailyCeiling: (dailyMean + gainableMean) * dp,
    finalWeight: (100 - c.dailyPercent.clamp(0.0, 100.0)) / 100,
  );
}

/// 当前估计总评（期末已填时），否则 null（表示期末未出分）。
double? geTotalWithFinal(GeCalc calc, double? finalScore) => finalScore == null
    ? null
    : calc.dailyContrib + calc.finalContrib(finalScore.clamp(0.0, 100.0));

/// 目标反推结果状态。
enum GeGoalStatus {
  /// 平时折算已达标：期末 ≥ 0 即可（requiredFinal = 0）。
  reached,

  /// 可行：期末需要达到 requiredFinal（0~100）。
  ok,

  /// 期末满分也不够，但把还能再挣的平时分项拿满后可补齐（dailyGap 即缺口
  /// 折算总评点，剩余可补 = dailyCeiling − dailyContrib）。
  recoverByDaily,

  /// 无论如何不可达：最大总评 = maxTotal（负计数损失或占比所致）。
  impossible,
}

/// 目标总评反推结果。
class GeGoalNeed {
  final GeGoalStatus status;

  /// 期末所需最低分（仅 [GeGoalStatus.ok] / [GeGoalStatus.reached] 有意义）。
  final double requiredFinal;

  /// 期末满分下仍差的总评点（仅 recoverByDaily）。
  final double dailyGap;

  /// 全局最大可达总评（impossible 时的天花板）。
  final double maxTotal;

  const GeGoalNeed({
    required this.status,
    this.requiredFinal = 0,
    this.dailyGap = 0,
    this.maxTotal = 0,
  });
}

/// 反推：为达到 [goal]（总评，0~100）期末最低需考多少分。
///
/// 期末占比为 0 时按纯平时课处理：平时折算已够 → [GeGoalStatus.reached]，
/// 否则按平时能否补足判定 recoverByDaily / impossible。
GeGoalNeed geRequiredFinal(GeCalc calc, double goal) {
  final fw = calc.finalWeight;
  final needed = (goal - calc.dailyContrib) / (fw > 0 ? fw : 1);
  if (needed <= 0) {
    return const GeGoalNeed(status: GeGoalStatus.reached);
  }
  if (fw > 0 && needed <= 100) {
    return GeGoalNeed(status: GeGoalStatus.ok, requiredFinal: needed);
  }
  // 期末满分也达不到：看平时还能再挣的分项（正计数 / 直接分数）能否补上缺口。
  final gap = goal - (calc.dailyContrib + 100 * fw);
  if (gap <= calc.dailyCeiling - calc.dailyContrib + 1e-9) {
    return GeGoalNeed(status: GeGoalStatus.recoverByDaily, dailyGap: gap);
  }
  return GeGoalNeed(
    status: GeGoalStatus.impossible,
    maxTotal: calc.dailyCeiling + 100 * fw,
  );
}

/// 期末未填时的总评区间下/上限（F ∈ [0, 100]）。
(double, double) geTotalRange(GeCalc calc) =>
    (calc.dailyContrib, calc.dailyContrib + 100 * calc.finalWeight);

// ─────────────────────── 学分加权平均（对齐成绩页口径） ───────────────────────

/// 加权平均的一个参与项：一门「分数已确定」的课程。
///
/// 分数来源两类：[fromGrades] 为 true 表示来自教务成绩缓存（已出成绩），
/// false 表示来自本模块估计（已填期末的估计总评）。同名课程只保留一条
/// （教务成绩优先，避免同一门课被重复计入）。
class GeWeightItem {
  /// 课程名。
  final String name;

  /// 百分制分数。
  final double score;

  /// 学分（权重）。
  final double credits;

  /// 是否来自教务成绩（false = 本模块估计分）。
  final bool fromGrades;

  const GeWeightItem({
    required this.name,
    required this.score,
    this.credits = 1,
    this.fromGrades = false,
  });
}

/// 学分加权平均汇总（与成绩页「课程加权」同口径：Σ 分数×学分 / Σ 学分）。
class GeWeightedSummary {
  /// 参与合计的学分合计（credits ≤ 0 的项不参与）。
  final double totalCredits;

  /// 参与合计的课程门数。
  final int count;

  /// 加权平均分；无有效项时 null。
  final double? average;

  /// 其中来自教务已出成绩的门数与学分。
  final int gradesCount;
  final double gradesCredits;

  /// 其中来自本模块估计的门数与学分。
  final int estimateCount;
  final double estimateCredits;

  const GeWeightedSummary({
    required this.totalCredits,
    required this.count,
    this.average,
    this.gradesCount = 0,
    this.gradesCredits = 0,
    this.estimateCount = 0,
    this.estimateCredits = 0,
  });

  bool get isEmpty => count == 0;

  /// 某参与项对加权平均的贡献（百分点，即该课在总平均中占的份额）。
  /// 全部参与项的贡献之和恰好等于 [average]（学分加权可加性）。
  double contribution(GeWeightItem item) => totalCredits <= 0
      ? 0
      : item.score.clamp(0.0, 100.0) * item.credits / totalCredits;
}

/// 汇总参与项为学分加权平均。
///
/// 例：高数 3 学分 90 分、英语 2 学分 80 分 →
/// 平均 = (90×3 + 80×2) / 5 = 86；两课贡献分别为 54、32，合计 86。
GeWeightedSummary geWeightedSummary(List<GeWeightItem> items) {
  var totalCredits = 0.0;
  var weighted = 0.0;
  var count = 0;
  var gradesCount = 0;
  var estimateCount = 0;
  var gradesCredits = 0.0;
  var estimateCredits = 0.0;
  for (final item in items) {
    if (item.credits <= 0) continue;
    final score = item.score.clamp(0.0, 100.0);
    totalCredits += item.credits;
    weighted += score * item.credits;
    count++;
    if (item.fromGrades) {
      gradesCount++;
      gradesCredits += item.credits;
    } else {
      estimateCount++;
      estimateCredits += item.credits;
    }
  }
  return GeWeightedSummary(
    totalCredits: totalCredits,
    count: count,
    average: totalCredits > 0 ? weighted / totalCredits : null,
    gradesCount: gradesCount,
    gradesCredits: gradesCredits,
    estimateCount: estimateCount,
    estimateCredits: estimateCredits,
  );
}

/// 合并「教务已出成绩」与「本模块估计」为加权平均参与项。
///
/// 规则：
/// - [priorItems]（教务已出成绩）**全部计入**——调用方负责按成绩页口径
///   过滤排除名单（军事训练 / 毕业设计 等）；
/// - [courses] 中与 [priorItems] 同名的课**跳过**：同一门课已由真实成绩
///   计入，不再用估计值重复计入；
/// - 其余课程：已填期末 → 按估计总评计入；未填期末或学分为 0 → 不计入
///   （用户口径：未填期末暂不计入总平均）。
List<GeWeightItem> geMergeWeightItems({
  required List<GeWeightItem> priorItems,
  required List<GeCourse> courses,
}) {
  final priorNames = {for (final p in priorItems) p.name.trim()};
  final items = <GeWeightItem>[...priorItems];
  for (final c in courses) {
    if (priorNames.contains(c.name.trim())) continue;
    final item = _geEstimateItem(c);
    if (item != null) items.add(item);
  }
  return items;
}

/// 本模块课程的估计参与项；null = 不计入（未填期末 / 学分为 0）。
GeWeightItem? _geEstimateItem(GeCourse c) {
  final total = geTotalWithFinal(geCalc(c), c.finalScore);
  if (total == null || c.credits <= 0) return null;
  return GeWeightItem(name: c.name, score: total, credits: c.credits);
}
