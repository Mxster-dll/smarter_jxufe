/// 竞赛奖励模块 —— 奖励标准模型（《学科竞赛管理办法（2024年修订）》第九条）。
///
/// 与目录一样，标准本身**来自资料库文档**（`assets/rules/text/r01a.md`），
/// 运行时由 `award_standard_parser.dart` 解析；这里只放解析后的形态与查询口径。
///
/// 关键条款（改动前先读，都在 UI 上引原文）：
/// - 第九条：Ⅰ/Ⅱ/Ⅲ/Ⅳ 类 × 国赛/省赛 × 获奖等次的奖励金额；**Ⅳ类只奖励指导教师（组），
///   不奖励学生**；Ⅱ/Ⅲ类「个人或团队只分别奖励金额最高的 1 个竞赛获奖项目，不累计奖励」。
/// - 第十条：只奖励最高的 3 个获奖等级；赛事设特等奖时，特等奖对应一等奖、
///   一等奖对应二等奖并依此类推；没明确规定特/一/二/三等奖的一律按三等奖；
///   入围奖、晋级奖、参与奖、优秀奖不计入。
library;

import 'competition_catalog.dart';

/// 竞赛范围层次（第八条）：国赛 / 省赛。
enum AwardScope {
  national('国赛'),
  provincial('省赛');

  const AwardScope(this.label);

  final String label;

  static AwardScope? parse(String raw) {
    final s = raw.trim();
    if (s.contains('国')) return AwardScope.national;
    if (s.contains('省')) return AwardScope.provincial;
    return null;
  }
}

/// 奖励对象：学生 / 指导教师（组）。
enum AwardAudience {
  student('学生'),
  teacher('指导教师（组）');

  const AwardAudience(this.label);

  final String label;
}

/// 一条奖励标准 = 表里的一个金额格。
class AwardStandardEntry {
  final CompetitionClass klass;
  final AwardAudience audience;

  /// Ⅰ类竞赛里同一张表并列了两组赛项（创新大赛/挑战杯课外学术 vs 挑战杯创业计划），
  /// 取该列所属的组名；其余类别为空串。
  final String groupLabel;

  /// null = 该表不分赛别（Ⅳ类）。
  final AwardScope? scope;

  /// 归一后的等次：Ⅰ类 = 特等奖/一等奖/二等奖/三等奖；Ⅱ/Ⅲ类 = 第一/二/三等次。
  final String tier;

  /// 原文标签（如 `特等奖（金奖）`），展示用。
  final String tierLabel;

  /// 金额（元）。
  final double amount;

  const AwardStandardEntry({
    required this.klass,
    required this.audience,
    required this.tier,
    required this.tierLabel,
    required this.amount,
    this.groupLabel = '',
    this.scope,
  });

  @override
  String toString() =>
      'AwardStandardEntry(${klass.label}/$groupLabel/${audience.label}/'
      '${scope?.label ?? '不分赛别'}/$tier=$amount)';
}

/// 奖励标准全文（解析结果）。
class AwardStandard {
  final List<AwardStandardEntry> entries;

  /// 表下注记原文（Ⅳ类不奖励学生、Ⅱ/Ⅲ类不累计、单赛事上限…）。
  final List<String> notes;

  /// 关键条款原文（第十条 奖励等级认定、第十二条 本科生奖励规定…）。
  final List<String> rules;

  /// 出处文档标题（`江西财经大学学科竞赛管理办法`）。
  final String? sourceTitle;

  const AwardStandard({
    required this.entries,
    this.notes = const [],
    this.rules = const [],
    this.sourceTitle,
  });

  static const AwardStandard empty = AwardStandard(entries: []);

  bool get hasData => entries.isNotEmpty;

  /// 某类别（+对象）在表里出现过的等次标签，按解析顺序去重。
  List<String> tierOptions(
    CompetitionClass klass, {
    AwardAudience audience = AwardAudience.student,
  }) {
    final out = <String>[];
    for (final e in entries) {
      if (e.klass != klass || e.audience != audience) continue;
      if (!out.contains(e.tierLabel)) out.add(e.tierLabel);
    }
    return out;
  }

  /// Ⅰ类各赛项组名（如「中国国际大学生创新大赛、“挑战杯”…课外学术科技作品竞赛」）。
  List<String> groupLabels(CompetitionClass klass) {
    final out = <String>[];
    for (final e in entries) {
      if (e.klass != klass || e.groupLabel.isEmpty) continue;
      if (!out.contains(e.groupLabel)) out.add(e.groupLabel);
    }
    return out;
  }

  /// 竞赛名 → Ⅰ类表里的赛项组（办法把「挑战杯创业计划竞赛」单列一档标准）。
  ///
  /// ⚠ **认不出就返回 null，绝不回落到「第一组」**：Ⅰ类两组标准不同
  /// （创业计划特等奖 3.2 万 vs 创新大赛/挑战杯课外学术 4 万，且创业计划三等奖
  /// `/` 不奖励学生）——回落会让「挑战杯创业计划三等奖」静默拿到 5000 元
  /// （实测踩过：守卫 `test/award_rules_parse_test.dart` 抓到）。
  String? groupLabelFor(CompetitionClass klass, String competitionName) {
    final groups = groupLabels(klass);
    if (groups.isEmpty) return null;
    final name = competitionName.replaceAll(RegExp(r'\s+'), '');
    String keyOf(String g) => g.replaceAll(RegExp(r'[\s“”"、，,（）()]'), '');

    // ① 创业计划组（必须在「创新」之前判，否则「挑战杯创业计划」也可能被误归到创新组）。
    for (final g in groups) {
      if (keyOf(g).contains('创业计划') && name.contains('创业计划')) return g;
    }
    // ② 课外学术 / 创新大赛组（「中国国际大学生创新大赛」与文档里的
    //    「中国国际大学生创新创业大赛」都要命中）。
    for (final g in groups) {
      final key = keyOf(g);
      if (key.contains('课外学术') && name.contains('课外学术')) return g;
      if (key.contains('创新') && name.contains('创新')) return g;
    }
    return null;
  }

  /// 按等次标签查金额（[tier] 用展示标签，如 `特等奖（金奖）`/`第一等次`）。
  double? amountOf({
    required CompetitionClass klass,
    required AwardAudience audience,
    required String tier,
    AwardScope? scope,
    String? groupLabel,
  }) {
    final wantTier = _normalizeTierLabel(tier);
    for (final e in entries) {
      if (e.klass != klass || e.audience != audience) continue;
      if (_normalizeTierLabel(e.tierLabel) != wantTier) continue;
      if (scope != null && e.scope != null && e.scope != scope) continue;
      if (groupLabel != null &&
          e.groupLabel.isNotEmpty &&
          e.groupLabel != groupLabel) {
        continue;
      }
      return e.amount;
    }
    return null;
  }

  /// 学生奖励金额（本功能的主查询）。
  ///
  /// - Ⅳ类：办法明确不奖励学生 → 返回 **0**（不是 null，调用方据此显示「不奖励学生」）；
  /// - Ⅰ类：先按竞赛名定位赛项组，再查等次/赛别；**定位不到组名 → null**
  ///   （两组标准不同，宁可让调用方提示核对，也不能拿错档的钱）；
  /// - Ⅱ/Ⅲ类：直接按等次/赛别查；
  /// - 查不到 → null（档案/标准版本不匹配，调用方提示核对）。
  double? studentAmountFor({
    required CompetitionClass klass,
    required String competitionName,
    required String tier,
    AwardScope? scope,
  }) {
    if (!klass.rewardsStudents) return 0;
    final group = groupLabelFor(klass, competitionName);
    if (klass == CompetitionClass.i && group == null) return null;
    return amountOf(
      klass: klass,
      audience: AwardAudience.student,
      tier: tier,
      scope: scope,
      groupLabel: group,
    );
  }

  String? noteContaining(String needle) {
    for (final n in notes) {
      if (n.contains(needle)) return n;
    }
    return null;
  }

  String? ruleContaining(String needle) {
    for (final r in rules) {
      if (r.contains(needle)) return r;
    }
    return null;
  }
}

/// 等次标签归一：去掉括号别名与空格，`特等奖（金 奖）` → `特等奖`。
String _normalizeTierLabel(String raw) {
  var s = raw.replaceAll(RegExp(r'\s+'), '');
  s = s.replaceAll(RegExp(r'[（(].*?[）)]'), '');
  return s;
}

/// 第十条「奖励等级认定」的等次归一（**Ⅱ/Ⅲ类**用：表里只有第一/二/三等次）。
///
/// 返回 0/1/2（一等次/二等次/三等次），null = 不计入（入围奖、晋级奖、参与奖、
/// 优秀奖，或设特等奖赛事里落到第 4 档的奖项）。
///
/// [hasSpecialTier]：该赛事是否设特等奖 —— 办法原话「若赛事设特等奖，则特等奖对应
/// 一等奖，一等奖对应二等奖并依此类推」，所以设特等奖时三/四等奖都拿不到奖励。
int? awardTierIndex(String raw, {bool hasSpecialTier = false}) {
  final s = _normalizeTierLabel(raw);
  if (s.isEmpty) return null;
  if (s.contains('入围') ||
      s.contains('晋级') ||
      s.contains('参与') ||
      s.contains('优秀') ||
      s.contains('纪念') ||
      s.contains('鼓励')) {
    return null;
  }
  // 已归一过的等次标签直接映射。
  if (s.contains('第一等次') || s.contains('一等次')) return 0;
  if (s.contains('第二等次') || s.contains('二等次')) return 1;
  if (s.contains('第三等次') || s.contains('三等次')) return 2;

  final isSpecial = s.contains('特等') || s.startsWith('金');
  final isFirst = s.contains('一等') || s.startsWith('金');
  final isSecond = s.contains('二等') || s.startsWith('银');
  final isThird = s.contains('三等') || s.startsWith('铜');
  if (!isSpecial && !isFirst && !isSecond && !isThird) {
    // 第十条：没有明确规定特/一/二/三等奖的奖项一律按三等奖奖励。
    return hasSpecialTier ? null : 2;
  }
  if (isSpecial) return 0;
  if (isFirst) return hasSpecialTier ? 1 : 0;
  if (isSecond) return hasSpecialTier ? 2 : 1;
  return hasSpecialTier ? null : 2;
}

/// 等次下标 → Ⅱ/Ⅲ类表里的标签。
String awardTierLabelOf(int index) => switch (index) {
  0 => '第一等次',
  1 => '第二等次',
  _ => '第三等次',
};
