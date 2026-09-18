/// 推免成绩模块 —— 附加分目录模型。
///
/// 目录来自**资料库文档**《江西财经大学推荐优秀应届本科毕业生免试攻读硕士研究生
/// 工作办法（2024年修订）》（`assets/rules/text/r08a.md`）的附件
/// 「推免工作附加分项目审核认定及加分标准」，运行时由 `bonus_catalog_parser.dart`
/// 解析（用户原话：「自动从资料库里获取加分项 / 具体的加分项参考 app 目前
/// 『规章制度』部分里有相关文件」）。
///
/// 办法关键口径（第十条 / 第十五条，UI 必须引原文）：
/// - 附加分分 5 类：竞赛类、专利类、著作权类、综合类、学术科研类；
/// - **每一类别只计一项，不累加**；**附加分总分 10 分封顶**（超过者以 10 分计算）；
/// - 综合成绩 = 推免加权平均成绩 + 附加分。
library;

/// 附加分五大类（《推免办法》第十条原文顺序）。
enum BonusCategory {
  contest('竞赛类'),
  patent('专利类'),
  copyright('著作权类'),
  honor('综合类'),
  research('学术科研类');

  const BonusCategory(this.label);

  final String label;

  String get hint => switch (this) {
    BonusCategory.contest => '国家级Ⅰ类主体赛道 / 国家级Ⅱ类（含排行榜目录内竞赛）',
    BonusCategory.patent => '发明专利 / 实用新型专利 / 外观设计专利',
    BonusCategory.copyright => '以国家版权局证书为依据',
    BonusCategory.honor => '各级荣誉称号、奖学金，分值为「分/学年」',
    BonusCategory.research => '核心期刊论文、大创项目课题',
  };
}

/// 「按获奖等级给分」的档位（金奖 10 分 / 银奖 7 分 / …）。
class BonusTier {
  final String label;
  final double points;

  const BonusTier(this.label, this.points);

  @override
  String toString() => '$label=$points';
}

/// 一个可选的加分项目。
class BonusOption {
  /// 稳定 id：`<类别>#<该类内序号>`（目录改版后仍能定位到「第几项」）。
  final String id;

  final BonusCategory category;

  /// 项目名（Ⅰ类赛项名称 / 专利与著作权的级别 / 综合类的荣誉 / 学术科研的类别）。
  final String label;

  /// 小类（`发明专利` / `实用新型专利` / `外观设计专利`），仅专利类非空。
  final String? group;

  /// 原文里的归类文字（如「国家级Ⅰ类（主体赛道）」「国家级Ⅱ类」）。
  final String? detail;

  /// 按获奖等级给分的档位；为空表示固定分值 [points]。
  final List<BonusTier> tiers;

  /// 固定分值（[tiers] 非空时为 null）。
  final double? points;

  /// 综合类的分值是「分/学年」。
  final bool perYear;

  /// 小类总分上限（实用新型 0.6 / 外观 1 / 著作权 1），来自表下注记。
  final double? capNote;

  const BonusOption({
    required this.id,
    required this.category,
    required this.label,
    this.group,
    this.detail,
    this.tiers = const [],
    this.points,
    this.perYear = false,
    this.capNote,
  });

  bool get hasTiers => tiers.isNotEmpty;

  /// 取该选项在给定获奖等级下的基准分（[tierLabel] 为空且选项只有一档时取该档）。
  double? pointsOf(String? tierLabel) {
    if (tiers.isEmpty) return points;
    final want = _norm(tierLabel ?? '');
    if (want.isEmpty) {
      return tiers.length == 1 ? tiers.first.points : null;
    }
    for (final t in tiers) {
      if (_norm(t.label) == want) return t.points;
    }
    for (final t in tiers) {
      // 容错：`第一等次奖` vs `第一等次`、`金奖` vs `金 奖`。
      if (_norm(t.label).contains(want) || want.contains(_norm(t.label))) {
        return t.points;
      }
    }
    return null;
  }

  String get pointsHint {
    if (tiers.isNotEmpty) {
      return tiers.map((t) => '${t.label} ${_fmt(t.points)} 分').join(' · ');
    }
    final p = points ?? 0;
    return perYear ? '${_fmt(p)} 分/学年' : '${_fmt(p)} 分/项';
  }
}

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '');

/// 竞赛类排名系数（原文「加分方式」栏）。
class BonusRankFactor {
  /// 排名区间（含端点）；[maxRank] 用 9999 表示「及以上」。
  final int minRank;
  final int maxRank;
  final double factor;

  const BonusRankFactor({
    required this.minRank,
    required this.maxRank,
    required this.factor,
  });

  String get label => maxRank >= 9999
      ? '第 $minRank 名及以后'
      : (minRank == maxRank ? '第 $minRank 名' : '第 $minRank-$maxRank 名');

  bool contains(int rank) => rank >= minRank && rank <= maxRank;
}

/// 推免附加分目录（解析结果）。
class BonusCatalog {
  final List<BonusOption> options;

  /// 竞赛类排名系数（空 = 未解析到，计算时按 1.0 处理并在 UI 提示）。
  final List<BonusRankFactor> rankFactors;

  /// 2025-01-01 之前取得的竞赛获奖，排名第 6 及以后按 [legacyFactor] 计。
  final double legacyFactor;

  /// 新旧规则分界日（原文：2025 年 1 月 1 日）。
  final DateTime legacyCutoff;

  /// 附加分总分上限（原文 10 分封顶）。
  final double cap;

  /// 办法文档标题（`推荐优秀应届本科毕业生免试攻读硕士研究生工作办法（2024年修订）`）。
  final String? sourceTitle;

  /// 附件标题（`江西财经大学推免工作附加分项目审核认定及加分标准`）。
  final String? attachmentTitle;

  /// 关键注记原文（含「以最高分计入，不累加」「教师为负责人的课题，其成员不加分」等）。
  final List<String> notes;

  /// 综合成绩计算式原文段落。
  final String? formulaNote;

  /// ⚠ 不是 const 构造：`DateTime` 没有 const 构造，分界日默认值只能运行时给。
  BonusCatalog({
    required this.options,
    this.rankFactors = const [],
    this.legacyFactor = 0.5,
    DateTime? legacyCutoff,
    this.cap = 10,
    this.sourceTitle,
    this.attachmentTitle,
    this.notes = const [],
    this.formulaNote,
  }) : legacyCutoff = legacyCutoff ?? _defaultCutoff;

  static final DateTime _defaultCutoff = DateTime(2025, 1, 1);

  /// 解析失败/资料库无该文档时的空目录（**非 const**：分界日默认值要现算）。
  static final BonusCatalog empty = BonusCatalog(options: const []);

  bool get hasData => options.isNotEmpty;

  List<BonusOption> optionsOf(BonusCategory category) => [
    for (final o in options)
      if (o.category == category) o,
  ];

  BonusOption? optionById(String id) {
    for (final o in options) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// 排名 → 系数。超出表范围（如第 16 名及以后）返回表里给出的小值（0）。
  double? rankFactorOf(int rank) {
    if (rank <= 0) return null;
    for (final f in rankFactors) {
      if (f.contains(rank)) return f.factor;
    }
    return null;
  }

  /// 竞赛类的实际系数（含 2025-01-01 前「排名第 6 及以后按 0.5」的旧规则）。
  double contestFactor({required int rank, DateTime? awardDate}) {
    final legacy = awardDate != null && awardDate.isBefore(legacyCutoff);
    if (legacy && rank >= 6) return legacyFactor;
    final factor = rankFactorOf(rank);
    if (factor != null) return factor;
    // 表里没有该排名（如第 16 名及以后「不加分」被写成一句文案）→ 0。
    return 0;
  }
}
