/// 资料库 → 推免附加分目录解析（纯函数：md 文本进，[BonusCatalog] 出）。
///
/// 解析对象 = 《推免工作办法（2024年修订）》附件的五节：
/// ```
/// ## 一、竞赛类          <table> 获奖类别 | 赛项名称 | 分值/次 | 加分方式 </table>  + 注 1/2/3
/// ## 二、专利类
///    ### （一）发明专利   <table> 级别 | 分值/次 </table>
///    ### （二）实用新型专利 … + 注：总加分最高 0.6 分
///    ### （三）外观设计专利 … + 注：总加分最高 1 分
/// ## 三、著作权类（以国家版权局证书为依据）  + 注：总加分最高 1 分
/// ## 四、综合类          <table> 获奖级别 | 分值/学年 </table>
/// ## 五、学术科研类       <table> 类别 | 分值/项 </table> + 注（课题组前 2-5 名加分）
/// ```
/// 另有 第十条（类别/10 分封顶）、第十五条（综合成绩=推免加权平均成绩+附加分）供口径引用。
///
/// **容错**：任何一节/一张表缺失都只导致该节为空，不抛异常；解析结果为空时由 UI
/// 显示「资料库未解析到加分标准」并给出原文入口（`BonusCatalog.hasData == false`）。
library;

import '../../rules/data/rule_doc_parse.dart';
import '../domain/bonus_catalog.dart';

/// 解析《推免工作办法》全文 → 附加分目录。
BonusCatalog parseBonusCatalog(String md) {
  final sections = ruleSectionsOf(md);
  if (sections.isEmpty) return BonusCatalog.empty;

  String? sourceTitle;
  String? attachmentTitle;
  for (final s in sections) {
    final t = ruleCleanText(s.title);
    if (sourceTitle == null && t.contains('免试攻读')) sourceTitle = t;
    if (attachmentTitle == null &&
        (t.contains('附加分项目审核认定') || t.contains('加分标准'))) {
      attachmentTitle = t;
    }
  }

  final options = <BonusOption>[];
  options.addAll(_parseContestOptions(sections));
  options.addAll(_parsePatentOptions(sections));
  options.addAll(_parseCopyrightOptions(sections));
  options.addAll(_parseHonorOptions(sections));
  options.addAll(_parseResearchOptions(sections));

  // 排名系数 / 新旧规则分界：都取自竞赛类表的「加分方式」栏与表下注记。
  var rankFactors = <BonusRankFactor>[];
  for (final section in sections) {
    if (!ruleCleanText(section.title).contains('竞赛类')) continue;
    for (final table in section.ruleTables) {
      final rankCol = table.indexOfColumn('加分方式');
      if (rankCol < 0) continue;
      for (var r = 1; r < table.rowCount; r++) {
        final cell = ruleCleanText(table.cell(r, rankCol));
        if (cell.isEmpty) continue;
        rankFactors = _parseRankFactors(cell);
        if (rankFactors.isNotEmpty) break;
      }
      if (rankFactors.isNotEmpty) break;
    }
    if (rankFactors.isNotEmpty) break;
  }
  rankFactors.sort((a, b) => a.minRank.compareTo(b.minRank));

  var legacyFactor = 0.5;
  var legacyCutoff = DateTime(2025, 1, 1);
  final notes = <String>[];
  for (final s in sections) {
    for (final p in s.paragraphs) {
      final t = ruleCleanText(p);
      if (t.contains('取得的竞赛获奖')) {
        final date = _parseDate(t);
        if (date != null) legacyCutoff = date;
        final m = RegExp(
          r'排名第\s*\d+\s*及以后者为满分\s*[*×]\s*([\d.]+)',
        ).firstMatch(t);
        if (m != null) {
          legacyFactor = double.tryParse(m.group(1)!) ?? legacyFactor;
        }
      }
      if (t.startsWith('注') || t.contains('不累加') || t.contains('不加分')) {
        if (!notes.contains(t)) notes.add(t);
      }
    }
  }

  var cap = 10.0;
  String? formulaNote;
  for (final s in sections) {
    final sectionTitle = ruleCleanText(s.title);
    if (sectionTitle.contains('第十条') || sectionTitle.contains('附加分')) {
      for (final p in s.paragraphs) {
        final t = ruleCleanText(p);
        final m = RegExp(r'总分\s*(\d+(?:\.\d+)?)\s*分封顶').firstMatch(t);
        if (m != null) cap = double.tryParse(m.group(1)!) ?? cap;
        if (t.contains('只计一项') && !notes.contains(t)) notes.add(t);
      }
    }
    for (final p in s.paragraphs) {
      final t = ruleCleanText(p);
      if (t.contains('综合成绩=') || t.contains('综合成绩计算方法')) {
        formulaNote ??= t;
      }
    }
  }

  if (options.isEmpty) return BonusCatalog.empty;

  return BonusCatalog(
    options: options,
    rankFactors: rankFactors,
    legacyFactor: legacyFactor,
    legacyCutoff: legacyCutoff,
    cap: cap,
    sourceTitle: sourceTitle,
    attachmentTitle: attachmentTitle,
    notes: notes,
    formulaNote: formulaNote,
  );
}

// ────────────────────────────── 竞赛类 ──────────────────────────────

List<BonusOption> _parseContestOptions(List<RuleSection> sections) {
  final section = ruleSectionOf(sections, '竞赛类', level: 2) ??
      ruleSectionOf(sections, '竞赛类');
  if (section == null) return const [];
  final out = <BonusOption>[];
  var serial = 0;
  for (final table in section.ruleTables) {
    final nameCol = table.indexOfColumn('赛项');
    final pointsCol = table.indexOfColumn('分值');
    final groupCol = table.indexOfColumn('获奖类别');
    if (nameCol < 0 || pointsCol < 0) continue;
    for (var r = 1; r < table.rowCount; r++) {
      final label = ruleCleanText(table.cell(r, nameCol));
      if (label.isEmpty || label == '赛项名称') continue;
      final tiers = _parseTiers(ruleCleanText(table.cell(r, pointsCol)));
      if (tiers.isEmpty) continue;
      serial++;
      out.add(
        BonusOption(
          id: 'contest#$serial',
          category: BonusCategory.contest,
          label: label,
          detail: groupCol < 0 ? null : ruleCleanText(table.cell(r, groupCol)),
          tiers: tiers,
        ),
      );
    }
  }
  return out;
}

/// `金奖： 10 分 银奖： 7 分 铜奖： 4 分` → [(金奖,10),(银奖,7),(铜奖,4)]。
List<BonusTier> _parseTiers(String raw) {
  final out = <BonusTier>[];
  final re = RegExp(r'([^：:\s]{2,12})\s*[：:]\s*(\d+(?:\.\d+)?)\s*分');
  for (final m in re.allMatches(raw)) {
    final label = m.group(1)!.trim();
    final points = double.tryParse(m.group(2)!);
    if (points == null) continue;
    if (out.any((t) => t.label == label)) continue;
    out.add(BonusTier(label, points));
  }
  return out;
}

/// 加分方式栏 → 排名系数表。
///
/// 原文：`排名第 1 者为满分；排名第 2 者为满分*0.9；…；排名第 7-10 名者为满分*0.3；
/// 排名第 11-15 名者为满分*0.1；排名第 16 名及以后者不加分。`
List<BonusRankFactor> _parseRankFactors(String raw) {
  final out = <BonusRankFactor>[];
  for (final segment in raw.split(RegExp(r'[；;\n]'))) {
    final s = segment.trim();
    if (s.isEmpty) continue;
    final range = RegExp(
      r'排名第\s*(\d+)\s*[-–—~至]\s*(\d+)\s*名?者为满分\s*[*×]\s*([\d.]+)',
    ).firstMatch(s);
    if (range != null) {
      out.add(
        BonusRankFactor(
          minRank: int.parse(range.group(1)!),
          maxRank: int.parse(range.group(2)!),
          factor: double.tryParse(range.group(3)!) ?? 0,
        ),
      );
      continue;
    }
    final zero = RegExp(r'排名第\s*(\d+)\s*名及以后者不加分').firstMatch(s);
    if (zero != null) {
      out.add(
        BonusRankFactor(
          minRank: int.parse(zero.group(1)!),
          maxRank: 9999,
          factor: 0,
        ),
      );
      continue;
    }
    final single = RegExp(
      r'排名第\s*(\d+)\s*名?者为满分(?:\s*[*×]\s*([\d.]+))?',
    ).firstMatch(s);
    if (single != null) {
      out.add(
        BonusRankFactor(
          minRank: int.parse(single.group(1)!),
          maxRank: int.parse(single.group(1)!),
          factor: single.group(2) == null
              ? 1
              : (double.tryParse(single.group(2)!) ?? 1),
        ),
      );
    }
  }
  return out;
}

// ────────────────────────────── 专利类 ──────────────────────────────

List<BonusOption> _parsePatentOptions(List<RuleSection> sections) {
  const groups = <(String, String)>[
    ('发明专利', '发明专利'),
    ('实用新型专利', '实用新型专利'),
    ('外观设计专利', '外观设计专利'),
  ];
  final out = <BonusOption>[];
  var serial = 0;
  for (final (needle, groupName) in groups) {
    final section = ruleSectionWhere(
      sections,
      (s) => ruleCleanText(s.title).contains(needle) && s.ruleTables.isNotEmpty,
    );
    if (section == null) continue;
    final cap = _capOf(section);
    for (final table in section.ruleTables) {
      final labelCol = table.indexOfColumn('级别');
      final pointsCol = table.indexOfColumn('分值');
      if (labelCol < 0 || pointsCol < 0) continue;
      for (var r = 1; r < table.rowCount; r++) {
        final label = ruleCleanText(table.cell(r, labelCol));
        final points = ruleFirstNumber(ruleCleanText(table.cell(r, pointsCol)));
        if (label.isEmpty || points == null) continue;
        if (label == '级别' || label.contains('级 别')) continue;
        serial++;
        out.add(
          BonusOption(
            id: 'patent#$serial',
            category: BonusCategory.patent,
            label: label,
            group: groupName,
            points: points,
            capNote: cap,
          ),
        );
      }
    }
  }
  return out;
}

// ───────────────────────────── 著作权类 ─────────────────────────────

List<BonusOption> _parseCopyrightOptions(List<RuleSection> sections) {
  final section = ruleSectionOf(sections, '著作权类');
  if (section == null) return const [];
  final cap = _capOf(section);
  final out = <BonusOption>[];
  var serial = 0;
  for (final table in section.ruleTables) {
    final labelCol = table.indexOfColumn('级别');
    final pointsCol = table.indexOfColumn('分值');
    if (labelCol < 0 || pointsCol < 0) continue;
    for (var r = 1; r < table.rowCount; r++) {
      final label = ruleCleanText(table.cell(r, labelCol));
      final points = ruleFirstNumber(ruleCleanText(table.cell(r, pointsCol)));
      if (label.isEmpty || points == null) continue;
      if (label == '级别') continue;
      serial++;
      out.add(
        BonusOption(
          id: 'copyright#$serial',
          category: BonusCategory.copyright,
          label: label,
          points: points,
          capNote: cap,
        ),
      );
    }
  }
  return out;
}

// ────────────────────────────── 综合类 ──────────────────────────────

List<BonusOption> _parseHonorOptions(List<RuleSection> sections) {
  final section = ruleSectionOf(sections, '综合类');
  if (section == null) return const [];
  final out = <BonusOption>[];
  var serial = 0;
  for (final table in section.ruleTables) {
    final labelCol = table.indexOfColumn('获奖级别');
    final pointsCol = table.indexOfColumn('分值');
    if (labelCol < 0 || pointsCol < 0) continue;
    final perYear = ruleCleanText(table.header.join()).contains('学年');
    for (var r = 1; r < table.rowCount; r++) {
      final rawLabel = ruleCleanText(table.cell(r, labelCol));
      final points = ruleFirstNumber(ruleCleanText(table.cell(r, pointsCol)));
      if (rawLabel.isEmpty || points == null) continue;
      if (rawLabel.contains('获奖级别')) continue;
      // 一格列多个荣誉（`全国优秀学生、全国优秀学生干部、…`）→ 拆成可单独勾选的项。
      final parts = rawLabel
          .split(RegExp(r'[、，,]'))
          .map(ruleCleanText)
          .where((s) => s.isNotEmpty)
          .toList();
      for (final part in parts) {
        serial++;
        out.add(
          BonusOption(
            id: 'honor#$serial',
            category: BonusCategory.honor,
            label: part,
            detail: parts.length > 1 ? rawLabel : null,
            points: points,
            perYear: perYear,
          ),
        );
      }
    }
  }
  return out;
}

// ──────────────────────────── 学术科研类 ────────────────────────────

List<BonusOption> _parseResearchOptions(List<RuleSection> sections) {
  final section = ruleSectionOf(sections, '学术科研类');
  if (section == null) return const [];
  final out = <BonusOption>[];
  var serial = 0;
  for (final table in section.ruleTables) {
    final labelCol = table.indexOfColumn('类别');
    final pointsCol = table.indexOfColumn('分值');
    if (labelCol < 0 || pointsCol < 0) continue;
    for (var r = 1; r < table.rowCount; r++) {
      final label = ruleCleanText(table.cell(r, labelCol));
      final points = ruleFirstNumber(ruleCleanText(table.cell(r, pointsCol)));
      if (label.isEmpty || points == null) continue;
      if (label.contains('类 别') || label == '类别') continue;
      serial++;
      out.add(
        BonusOption(
          id: 'research#$serial',
          category: BonusCategory.research,
          label: label,
          points: points,
        ),
      );
    }
  }
  // 表下注记里的「课题组前 2-5 名加分」也做成可选项（国家级 / 省级）。
  final re = RegExp(
    r'(国家级|省级)[^。；;]*?课题组前\s*2\s*-\s*5\s*名加\s*(\d+(?:\.\d+)?)\s*分',
  );
  for (final p in section.paragraphs) {
    for (final m in re.allMatches(ruleCleanText(p))) {
      final level = m.group(1)!;
      final points = double.tryParse(m.group(2)!);
      if (points == null) continue;
      final label = '$level大学生创新创业训练计划项目课题组成员（前 2-5 名）';
      if (out.any((o) => o.label == label)) continue;
      serial++;
      out.add(
        BonusOption(
          id: 'research#$serial',
          category: BonusCategory.research,
          label: label,
          points: points,
        ),
      );
    }
  }
  return out;
}

// ─────────────────────────────── 工具 ───────────────────────────────

/// 节内「最高 X 分」→ X（实用新型 0.6 / 外观 1 / 著作权 1）。
double? _capOf(RuleSection section) {
  for (final p in section.paragraphs) {
    final t = ruleCleanText(p);
    final m = RegExp(
      r'(?:总加分)?最高\s*(\d+(?:\.\d+)?)\s*分',
    ).firstMatch(t);
    if (m != null) return double.tryParse(m.group(1)!);
  }
  return null;
}

DateTime? _parseDate(String text) {
  final m = RegExp(
    r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日',
  ).firstMatch(text);
  if (m == null) return null;
  final y = int.tryParse(m.group(1)!);
  final mo = int.tryParse(m.group(2)!);
  final d = int.tryParse(m.group(3)!);
  if (y == null || mo == null || d == null) return null;
  return DateTime(y, mo, d);
}
