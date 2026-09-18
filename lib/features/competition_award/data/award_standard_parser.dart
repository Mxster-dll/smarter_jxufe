/// 资料库 → 竞赛奖励标准解析（纯函数：md 文本进，[AwardStandard] 出）。
///
/// 解析对象 = 《学科竞赛管理办法（2024年修订）》第九条 5 张表：
/// | 表 | 表头特征 | 处理 |
/// |---|---|---|
/// | Ⅰ类 指导教师+学生 | 首行含「Ⅰ类竞赛」、有「奖励对象」行 | 两组赛项 × 2 对象 × 国赛/省赛 |
/// | 竞赛组织奖 | 首行含「先进集体奖」 | **跳过**（奖励单位，与个人无关） |
/// | Ⅱ/Ⅲ类 指导教师 | 首行同时含「Ⅱ类竞赛」「Ⅲ类竞赛」且有「奖励类别」列 | 取「奖金」行 |
/// | Ⅱ/Ⅲ类 本科生 | 同上但无「奖励类别」列；前一段文字含「本科生」 | 取全部数据行 |
/// | Ⅳ类 指导教师 | 首行含「Ⅳ类」 | 不分赛别；学生不奖励（见表下注） |
///
/// **三行表头 + rowspan 的处理**：Ⅰ类表的表头是「Ⅰ类竞赛（赛项组）→ 奖励对象 →
/// 获奖等级」，Ⅱ/Ⅲ类表是「Ⅱ类竞赛/Ⅲ类竞赛 → 国赛/省赛」。这里统一的做法是
/// 「先定位『国赛/省赛』那一行（scopeRow），再按列向上回溯」——不写死行号，
/// 学校改版后仍能工作。
library;

import '../../rules/data/rule_doc_parse.dart';
import '../../rules/domain/doc_blocks.dart';
import '../domain/award_standard.dart';
import '../domain/competition_catalog.dart';

/// 解析《学科竞赛管理办法》全文 → 奖励标准。
AwardStandard parseAwardStandard(String md) {
  final sections = ruleSectionsOf(md);
  if (sections.isEmpty) return AwardStandard.empty;

  final entries = <AwardStandardEntry>[];
  final notes = <String>[];
  final rules = <String>[];

  String? sourceTitle;
  for (final s in sections) {
    final t = ruleCleanText(s.title);
    if (t.contains('学科竞赛管理办法') && sourceTitle == null) sourceTitle = t;
  }

  // 第九条 = 含奖励标准表的节；退化时扫全文所有含表格的节。
  final standardSections = <RuleSection>[];
  for (final s in sections) {
    if (s.title.contains('第九条') || s.title.contains('竞赛奖励标准')) {
      standardSections.add(s);
    }
  }
  if (standardSections.isEmpty) {
    for (final s in sections) {
      if (s.ruleTables.isNotEmpty) standardSections.add(s);
    }
  }

  for (final section in standardSections) {
    final recent = <String>[];
    for (final block in section.blocks) {
      if (block.kind == BlockKind.para) {
        final text = ruleCleanText(block.text);
        if (text.isEmpty) continue;
        if (text.startsWith('注')) notes.add(text);
        recent.add(text);
        if (recent.length > 4) recent.removeAt(0);
        continue;
      }
      if (block.table == null) continue;
      final table = ruleTableOf(block.table!);
      final head = table.header.map(ruleCleanText).join('|');
      if (head.contains('先进集体奖') || head.contains('奖励等级')) {
        continue; // 竞赛组织奖：奖励单位，与个人奖励无关
      }
      if (head.contains('Ⅳ类')) {
        entries.addAll(_parseClassIvTable(table));
        continue;
      }
      if (head.contains('Ⅰ类')) {
        entries.addAll(_parseClassITable(table));
        continue;
      }
      if (head.contains('Ⅱ类') && head.contains('Ⅲ类')) {
        final audience = recent.any((p) => p.contains('本科生'))
            ? AwardAudience.student
            : AwardAudience.teacher;
        entries.addAll(_parseScopeClassTable(table, audience: audience));
      }
    }
  }

  for (final s in sections) {
    final t = ruleCleanText(s.title);
    if (t.contains('第十条') || t.contains('第十二条') || t.contains('第八条')) {
      rules.addAll(s.paragraphs.map(ruleCleanText));
    }
  }

  return AwardStandard(
    entries: entries,
    notes: notes,
    rules: rules,
    sourceTitle: sourceTitle,
  );
}

/// Ⅰ类表：赛项组（列） × 奖励对象（列） × 国赛/省赛（列） × 获奖等级（行）。
List<AwardStandardEntry> _parseClassITable(RuleTable table) {
  final scopeRow = table.indexOfRow((c) => ruleCleanText(c) == '国赛');
  if (scopeRow < 0) return const [];

  int audienceRow = -1;
  int groupRow = -1;
  for (var r = scopeRow - 1; r >= 0; r--) {
    final joined = table.rowAt(r).map(ruleCleanText).join('|');
    if (audienceRow < 0 &&
        (joined.contains('学生') || joined.contains('指导教师'))) {
      audienceRow = r;
      continue;
    }
    if (audienceRow >= 0 &&
        groupRow < 0 &&
        (joined.contains('类竞赛') ||
            joined.contains('大赛') ||
            joined.contains('挑战杯'))) {
      groupRow = r;
    }
  }

  final columns = <int, ({AwardScope scope, AwardAudience audience, String group})>{};
  for (var c = 0; c < table.columnCount; c++) {
    final scope = AwardScope.parse(ruleCleanText(table.cell(scopeRow, c)));
    if (scope == null) continue;
    final audienceCell = audienceRow < 0
        ? ''
        : ruleCleanText(table.cell(audienceRow, c));
    final audience = audienceCell.contains('学生')
        ? AwardAudience.student
        : AwardAudience.teacher;
    var group = groupRow < 0 ? '' : ruleCleanText(table.cell(groupRow, c));
    if (group == 'Ⅰ类竞赛') group = '';
    columns[c] = (scope: scope, audience: audience, group: group);
  }
  if (columns.isEmpty) return const [];

  final categoryCol = _columnAtRow(table, scopeRow, const ['奖励类别']);
  final tierCol = _columnAtRow(table, scopeRow, const ['获奖等级']);
  final out = <AwardStandardEntry>[];
  for (var r = scopeRow + 1; r < table.rowCount; r++) {
    if (categoryCol >= 0 &&
        !ruleCleanText(table.cell(r, categoryCol)).contains('奖金')) {
      continue; // 「非课堂教学工作量 / 科研工作量」行不是钱
    }
    final tierLabel = ruleCleanText(
      table.cell(r, tierCol < 0 ? 0 : tierCol),
    );
    if (tierLabel.isEmpty || tierLabel.contains('获奖等级')) continue;
    for (final entry in columns.entries) {
      final amount = ruleAmountInYuan(table.cell(r, entry.key));
      if (amount == null) continue;
      out.add(
        AwardStandardEntry(
          klass: CompetitionClass.i,
          audience: entry.value.audience,
          groupLabel: entry.value.group,
          scope: entry.value.scope,
          tier: _shortTier(tierLabel),
          tierLabel: tierLabel,
          amount: amount,
        ),
      );
    }
  }
  return out;
}

/// Ⅱ/Ⅲ类表：类别（列） × 国赛/省赛（列） × 等次（行）。
List<AwardStandardEntry> _parseScopeClassTable(
  RuleTable table, {
  required AwardAudience audience,
}) {
  final scopeRow = table.indexOfRow((c) => ruleCleanText(c) == '国赛');
  if (scopeRow < 0) return const [];
  final classRow = scopeRow - 1;
  if (classRow < 0) return const [];

  final columns = <int, ({CompetitionClass klass, AwardScope scope})>{};
  for (var c = 0; c < table.columnCount; c++) {
    final scope = AwardScope.parse(ruleCleanText(table.cell(scopeRow, c)));
    if (scope == null) continue;
    final klass = CompetitionClass.parse(ruleCleanText(table.cell(classRow, c)));
    if (klass == null) continue;
    columns[c] = (klass: klass, scope: scope);
  }
  if (columns.isEmpty) return const [];

  final categoryCol = _columnAtRow(table, scopeRow, const ['奖励类别']);
  final tierCol = _columnAtRow(table, scopeRow, const ['获奖等次', '获奖等级']);
  final out = <AwardStandardEntry>[];
  for (var r = scopeRow + 1; r < table.rowCount; r++) {
    if (categoryCol >= 0 &&
        !ruleCleanText(table.cell(r, categoryCol)).contains('奖金')) {
      continue;
    }
    final tierLabel = ruleCleanText(table.cell(r, tierCol < 0 ? 0 : tierCol));
    if (tierLabel.isEmpty || tierLabel.contains('等次')) {
      if (!tierLabel.startsWith('第')) continue;
    }
    for (final entry in columns.entries) {
      final amount = ruleAmountInYuan(table.cell(r, entry.key));
      if (amount == null) continue;
      out.add(
        AwardStandardEntry(
          klass: entry.value.klass,
          audience: audience,
          scope: entry.value.scope,
          tier: _shortTier(tierLabel),
          tierLabel: tierLabel,
          amount: amount,
        ),
      );
    }
  }
  return out;
}

/// Ⅳ类表：只奖励指导教师（组），不分赛别。
List<AwardStandardEntry> _parseClassIvTable(RuleTable table) {
  final tierCol = table.indexOfColumn('获奖等次');
  final col = tierCol < 0 ? 0 : tierCol;
  final projectColumns = <int, String>{};
  for (var c = 0; c < table.columnCount; c++) {
    if (c == col) continue;
    final label = ruleCleanText(table.cell(0, c));
    if (label.isEmpty) continue;
    projectColumns[c] = label;
  }
  final out = <AwardStandardEntry>[];
  for (var r = 1; r < table.rowCount; r++) {
    final tierLabel = ruleCleanText(table.cell(r, col));
    if (tierLabel.isEmpty || tierLabel.contains('获奖等次')) continue;
    for (final entry in projectColumns.entries) {
      final amount = ruleAmountInYuan(table.cell(r, entry.key));
      if (amount == null) continue;
      out.add(
        AwardStandardEntry(
          klass: CompetitionClass.iv,
          audience: AwardAudience.teacher,
          groupLabel: entry.value,
          tier: _shortTier(tierLabel),
          tierLabel: tierLabel,
          amount: amount,
        ),
      );
    }
  }
  return out;
}

/// 某一行里第一个含 [needles] 的列。
int _columnAtRow(RuleTable table, int row, List<String> needles) {
  for (var c = 0; c < table.columnCount; c++) {
    final cell = ruleCleanText(table.cell(row, c));
    if (cell.isEmpty) continue;
    if (needles.any(cell.contains)) return c;
  }
  return -1;
}

/// `特等奖（金奖）` → `特等奖`；`第一等次` → `第一等次`。
String _shortTier(String raw) {
  var s = raw.replaceAll(RegExp(r'\s+'), '');
  s = s.replaceAll(RegExp(r'[（(].*?[）)]'), '');
  return s;
}
