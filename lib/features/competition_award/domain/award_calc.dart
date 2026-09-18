/// 竞赛奖励模块 —— 奖励金额计算（**纯函数，唯一实现**）。
///
/// 口径全部来自资料库《学科竞赛管理办法（2024年修订）》：
/// - 第九条奖励标准表（`AwardStandard`）；
/// - 第九条注（1）「个人或团队只分别奖励金额最高的 1 个竞赛获奖项目，不累计奖励」（**Ⅱ/Ⅲ类**）；
/// - 第九条注（1）「Ⅳ类学科竞赛只奖励指导教师（组），不奖励学生」；
/// - 第十条「只奖励最高的 3 个获奖等级…同一年度同一作品在同一竞赛不同级别获奖，
///   取最高奖项进行奖励；没有明确规定特、一、二、三等奖的奖项一律按三等奖；
///   入围奖、晋级奖、参与奖和优秀奖等不计入奖项」。
///
/// 用户 2026-09-17 口径：「时间范围不是按学年，而是手动选择时间范围」→ 时间范围
/// **只作用于获奖记录筛选**（[AwardDateRange]），与目录版本无关；选了区间后
/// 缺日期的记录会被明确标为「未计入」而不是静默丢弃。
library;

import 'award_coefficient.dart';
import 'competition_catalog.dart';
import 'award_record.dart';
import 'award_standard.dart';

/// 手选时间范围（含首尾日期，按日比较，忽略时刻）。
class AwardDateRange {
  final DateTime start;
  final DateTime end;

  const AwardDateRange(this.start, this.end);

  bool containsDate(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return !day.isBefore(s) && !day.isAfter(e);
  }

  String get label => '${fmtAwardDate(start)} ~ ${fmtAwardDate(end)}';
}

/// 单条记录的计算结果。
class AwardRecordOutcome {
  final CompetitionAwardRecord record;

  /// 金额（元）；未计入时为 0。**已含**赛事经验系数。
  final double amount;

  /// 乘系数**之前**的金额（办法标准 × 折减口径）；行内明算用
  /// （`6000 元 × 0.6 = 3600 元` 里的 6000）。未计入时为 0。
  final double baseAmount;

  /// 该记录命中的赛事经验系数（1 = 没设 / 不缩减）。
  final double coefficient;

  final bool counted;
  final String reason;

  /// **被「取最高」挤掉**（③ 第十条同年同赛事取最高 / ④ Ⅱ Ⅲ类只奖最高一项不累计），
  /// 与「压根算不出来」（缺日期 / 超范围 / 奖励标准里没金额 / Ⅳ类不奖学生 / 等次认不出）
  /// 区分开。
  ///
  /// 用户 2026-09-18 口径：「不计入的项变暗，而不是显示那个什么第九条的提示」→
  /// 页面遇到 `suppressed` 只把该行**变暗**、不印 `reason`（取舍是正常结果，不是异常）；
  /// 其余未计入的 `reason` 是唯一能解释「为什么没算钱」的信息，必须照旧显示。
  final bool suppressed;

  /// 实际采用的类别（非主体赛道折减后可能是Ⅱ类）。
  final CompetitionClass effectiveKlass;

  const AwardRecordOutcome({
    required this.record,
    required this.amount,
    required this.counted,
    required this.reason,
    required this.effectiveKlass,
    this.baseAmount = 0,
    this.coefficient = 1,
    this.suppressed = false,
  });

  /// 是否被赛事经验系数缩减过（行内明算的开关）。
  bool get scaled => counted && coefficient != 1;
}

/// 合计结果。
class CompetitionAwardOutcome {
  final List<AwardRecordOutcome> items;

  /// 合计奖励金额（元）。
  final double total;

  /// 计入的记录数。
  final int countedCount;

  /// 本次计算触发的口径提示（去重；页面照原样展示）。
  final List<String> appliedRules;

  const CompetitionAwardOutcome({
    required this.items,
    required this.total,
    required this.countedCount,
    this.appliedRules = const [],
  });

  static const CompetitionAwardOutcome empty = CompetitionAwardOutcome(
    items: [],
    total: 0,
    countedCount: 0,
  );

  List<AwardRecordOutcome> get countedItems =>
      [for (final i in items) if (i.counted) i];

  /// 未计入的记录（页面**全部**展示：`suppressed` 的只变暗，其余还要显示原因）。
  List<AwardRecordOutcome> get excludedItems =>
      [for (final i in items) if (!i.counted) i];
}

/// Ⅰ类等次归一（表里只有特等奖（金奖）/一等奖（银奖）/二等奖（铜奖）/三等奖）。
String? classITierOf(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s（(].*$'), '');
  if (s.isEmpty) return null;
  if (s.contains('特等') || s.startsWith('金')) return '特等奖';
  if (s.contains('一等') || s.startsWith('银')) return '一等奖';
  if (s.contains('二等') || s.startsWith('铜')) return '二等奖';
  if (s.contains('三等')) return '三等奖';
  return null;
}

/// 计算获奖记录的奖励合计。
///
/// [coefficients] = 赛事经验系数（用户 2026-09-18 要求手动设置，见
/// `domain/award_coefficient.dart`）：命中某赛事的记录按其系数等比缩减，
/// **乘在折减后的金额上、且在第十条 / 第九条注的「取最高」之前** ——
/// 学校比的是实际发放金额，先缩后比才与办法一致。
CompetitionAwardOutcome competitionAwardOutcomeOf({
  required List<CompetitionAwardRecord> records,
  required AwardStandard standard,
  AwardDateRange? range,
  AwardCoefficientTable coefficients = AwardCoefficientTable.empty,
}) {
  final appliedRules = <String>[];
  final outcomes = <AwardRecordOutcome>[];

  // ① 时间范围过滤（手选区间：缺日期 / 超范围都明确标出）。
  final inRange = <CompetitionAwardRecord>[];
  for (final r in records) {
    if (range == null) {
      inRange.add(r);
      continue;
    }
    final d = r.date;
    if (d == null) {
      outcomes.add(
        AwardRecordOutcome(
          record: r,
          amount: 0,
          counted: false,
          reason: '缺获奖日期，无法计入所选时间范围',
          effectiveKlass: r.klass,
        ),
      );
      continue;
    }
    if (!range.containsDate(d)) {
      outcomes.add(
        AwardRecordOutcome(
          record: r,
          amount: 0,
          counted: false,
          reason: '不在所选时间范围内（${range.label}）',
          effectiveKlass: r.klass,
        ),
      );
      continue;
    }
    inRange.add(r);
  }

  // ② 逐条按办法算金额。
  final computed =
      <({
        CompetitionAwardRecord r,
        double amount,
        double base,
        double coefficient,
        String reason,
        CompetitionClass klass,
      })>[];
  for (final r in inRange) {
    if (!r.klass.rewardsStudents) {
      outcomes.add(
        AwardRecordOutcome(
          record: r,
          amount: 0,
          counted: false,
          reason: '办法第九条注（1）：Ⅳ类只奖励指导教师（组），不奖励学生',
          effectiveKlass: r.klass,
        ),
      );
      appliedRules.add('Ⅳ类竞赛不奖励学生（第九条注）');
      continue;
    }

    var klass = r.klass;
    if (r.adjustment == AwardAdjustment.nonMainTrackAsClassII &&
        klass == CompetitionClass.i) {
      klass = CompetitionClass.ii;
      appliedRules.add('“挑战杯”主体赛道外项目按Ⅱ类标准（第九条注）');
    }

    String? tier;
    if (klass == CompetitionClass.i) {
      tier = classITierOf(r.tierLabel);
      if (tier == null) {
        outcomes.add(
          AwardRecordOutcome(
            record: r,
            amount: 0,
            counted: false,
            reason: '等次认不出（第十条：没有明确规定特/一/二/三等奖的按三等奖）',
            effectiveKlass: klass,
          ),
        );
        continue;
      }
    } else {
      final index = awardTierIndex(
        r.tierLabel,
        hasSpecialTier: r.hasSpecialTier,
      );
      if (index == null) {
        outcomes.add(
          AwardRecordOutcome(
            record: r,
            amount: 0,
            counted: false,
            reason: r.hasSpecialTier
                ? '第十条：设特等奖的赛事里，特等奖对应一等奖并依此类推，该项落到第 4 档 → 不奖励'
                : '第十条：入围奖 / 晋级奖 / 参与奖 / 优秀奖不计入奖项',
            effectiveKlass: klass,
          ),
        );
        appliedRules.add('第十条奖励等级认定');
        continue;
      }
      tier = awardTierLabelOf(index);
    }

    final base = standard.studentAmountFor(
      klass: klass,
      competitionName: r.competitionName,
      tier: tier,
      scope: r.scope,
    );
    if (base == null) {
      outcomes.add(
        AwardRecordOutcome(
          record: r,
          amount: 0,
          counted: false,
          reason: '奖励标准里没有对应金额（请核对等次 / 赛别）',
          effectiveKlass: klass,
        ),
      );
      continue;
    }
    var amount = base;
    if (r.adjustment == AwardAdjustment.international70) {
      amount = base * 0.7;
      appliedRules.add('中国国际大学生创新大赛国际项目按标准 70%（第九条注）');
    }
    // ②′ 赛事经验系数（手动设置）：只缩该赛事的记录，先缩后比。
    final factor = coefficients.factorFor(r.competitionName);
    final preCoefficient = amount;
    if (factor != 1) {
      amount = amount * factor;
      appliedRules.add(
        '“${r.competitionName}”按赛事经验系数 ×${fmtAwardCoefficient(factor)} 等比缩减（手动设置）',
      );
    }
    computed.add((
      r: r,
      amount: amount,
      base: preCoefficient,
      coefficient: factor,
      reason: factor == 1
          ? '按办法标准'
          : '按办法标准 × 赛事经验系数 ${fmtAwardCoefficient(factor)}',
      klass: klass,
    ));
  }

  // ③ 第十条：同一年度同一作品在同一竞赛不同级别获奖取最高。
  final byYear = <String, List<int>>{};
  for (var i = 0; i < computed.length; i++) {
    byYear.putIfAbsent(computed[i].r.yearKey, () => []).add(i);
  }
  final suppressed = <int>{};
  for (final group in byYear.values) {
    if (group.length < 2) continue;
    var bestIndex = group.first;
    for (final i in group) {
      if (computed[i].amount > computed[bestIndex].amount) bestIndex = i;
    }
    for (final i in group) {
      if (i != bestIndex) suppressed.add(i);
    }
    appliedRules.add('同一年度同一竞赛取最高奖项（第十条）');
  }

  // ④ Ⅱ/Ⅲ类：只奖励金额最高的 1 个项目，不累计（按类别分别取最高）。
  final byClassNonAccumulate = <CompetitionClass, List<int>>{};
  for (var i = 0; i < computed.length; i++) {
    if (suppressed.contains(i)) continue;
    final klass = computed[i].klass;
    if (klass == CompetitionClass.ii || klass == CompetitionClass.iii) {
      byClassNonAccumulate.putIfAbsent(klass, () => []).add(i);
    }
  }
  for (final entry in byClassNonAccumulate.entries) {
    if (entry.value.length < 2) continue;
    var bestIndex = entry.value.first;
    for (final i in entry.value) {
      if (computed[i].amount > computed[bestIndex].amount) bestIndex = i;
    }
    for (final i in entry.value) {
      if (i != bestIndex) suppressed.add(i);
    }
    appliedRules.add(
      '${entry.key.label}只奖励金额最高的 1 个项目，不累计（第九条注）',
    );
  }

  var total = 0.0;
  var counted = 0;
  for (var i = 0; i < computed.length; i++) {
    final c = computed[i];
    if (suppressed.contains(i)) {
      outcomes.add(
        AwardRecordOutcome(
          record: c.r,
          amount: 0,
          counted: false,
          // 被取最高挤掉 → 页面只变暗、不印这行（用户 2026-09-18 口径）。
          suppressed: true,
          reason: c.klass == CompetitionClass.i
              ? '同一年度同一竞赛已取更高奖项（第十条）'
              : '只保留金额最高的一项，本项不累计（第九条注）',
          effectiveKlass: c.klass,
        ),
      );
      continue;
    }
    total += c.amount;
    counted++;
    outcomes.add(
      AwardRecordOutcome(
        record: c.r,
        amount: c.amount,
        baseAmount: c.base,
        coefficient: c.coefficient,
        counted: true,
        reason: c.reason,
        effectiveKlass: c.klass,
      ),
    );
  }

  // 保持与输入同序展示（先计入、后未计入在原顺序里交错也没关系，UI 自行分组）。
  final order = <String, int>{
    for (var i = 0; i < records.length; i++) records[i].id: i,
  };
  outcomes.sort(
    (a, b) => (order[a.record.id] ?? 0).compareTo(order[b.record.id] ?? 0),
  );

  return CompetitionAwardOutcome(
    items: outcomes,
    total: total,
    countedCount: counted,
    appliedRules: appliedRules.toSet().toList(),
  );
}

/// 金额展示：`6000 元` / `4.2 万元`（页面与守卫统一走它，别各写一份）。
String fmtAwardAmount(double yuan) {
  if (yuan >= 10000) return '${_trimNumber(yuan / 10000)} 万元';
  return '${_trimNumber(yuan)} 元';
}

/// 去尾零：`3.20` → `3.2`、`4.00` → `4`、`1500.50` → `1500.5`。
String _trimNumber(double v) {
  var text = v.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceAll(RegExp(r'0+$'), '');
    text = text.replaceAll(RegExp(r'\.$'), '');
  }
  return text;
}
