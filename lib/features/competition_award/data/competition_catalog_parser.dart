/// 资料库 → 竞赛目录解析（纯函数：md 文本进，[CompetitionCatalogEdition] 出）。
///
/// 解析对象 = 《江西财经大学学科竞赛目录》正文，形如：
/// ```
/// # 江西财经大学2025-2026 年学科竞赛目录
/// ## 一、Ⅰ类学科竞赛目录
/// <table><tr><td>序号</td><td>竞赛项目名称</td><td>竞赛组织学院（部门）</td></tr>…</table>
/// ## 二、Ⅱ类学科竞赛目录      ← 表头是「序号 / 竞赛项目名称 / 备注」
/// ## 三、Ⅲ类学科竞赛目录      ← 表头是「序号 / 竞赛项目名称 / 申报学院 / 申报专业 / 备注」
/// ## 四、Ⅳ类学科竞赛（重点）目录 ← 表头是「序号 / 竞赛项目名称 / 子项目 / 组织学院 / 备注」
/// ```
///
/// **按表头文字取列，绝不按下标取列** —— 四类目录的列数各不相同（3/3/5/5），
/// 学校换版时列序也会变；按表头取列的代价只是「认不出就少一列」，不会静默错位。
library;

import '../../rules/data/rule_doc_parse.dart';
import '../domain/competition_catalog.dart';

/// 解析一个版本的竞赛目录；[label] 覆盖从标题里推断的版本标签。
CompetitionCatalogEdition? parseCompetitionCatalogEdition(
  String md, {
  String? label,
  String? sourceDocId,
}) {
  final sections = ruleSectionsOf(md);
  if (sections.isEmpty) return null;

  String? title;
  for (final s in sections) {
    final t = ruleCleanText(s.title);
    if (t.contains('学科竞赛目录') || (t.contains('竞赛') && t.contains('目录'))) {
      title = t;
      break;
    }
  }

  final entries = <CompetitionEntry>[];
  for (final section in sections) {
    final sectionTitle = ruleCleanText(section.title);
    final klass = _classOfSectionTitle(sectionTitle);
    if (klass == null) continue;
    for (final table in section.ruleTables) {
      entries.addAll(_entriesOfTable(table, klass: klass, edition: ''));
    }
  }
  if (entries.isEmpty) return null;

  final editionLabel = label ?? _editionLabelOf(title ?? '') ?? '';
  final finalized = [
    for (final e in entries)
      CompetitionEntry(
        serial: e.serial,
        name: e.name,
        klass: e.klass,
        edition: editionLabel,
        subProject: e.subProject,
        organizer: e.organizer,
        major: e.major,
        note: e.note,
      ),
  ];
  return CompetitionCatalogEdition(
    label: editionLabel,
    title: title ?? '学科竞赛目录',
    sourceDocId: sourceDocId,
    entries: finalized,
  );
}

/// `一、Ⅰ类学科竞赛目录` → [CompetitionClass.i]；认不出返回 null。
CompetitionClass? _classOfSectionTitle(String title) {
  if (!title.contains('类') || !title.contains('目录')) return null;
  final marker = RegExp(r'([ⅠⅡⅢⅣIVXivx]+)\s*类').firstMatch(title);
  if (marker != null) return CompetitionClass.parse(marker.group(1)!);
  final zh = RegExp(r'([一二三四])\s*类').firstMatch(title);
  if (zh != null) return CompetitionClass.parse(zh.group(1)!);
  return null;
}

String? _editionLabelOf(String title) {
  final m = RegExp(r'(\d{4})\s*[-—~]\s*(\d{4})\s*年?').firstMatch(title);
  if (m == null) return null;
  return '${m.group(1)}-${m.group(2)} 年';
}

List<CompetitionEntry> _entriesOfTable(
  RuleTable table, {
  required CompetitionClass klass,
  required String edition,
}) {
  if (table.rowCount <= 1) return const [];
  final header = table.header;
  final nameCol = _columnOf(header, const ['名称'], exclude: const ['序号']);
  if (nameCol < 0) return const [];
  final serialCol = _columnOf(header, const ['序号']);
  final subCol = _columnOf(header, const ['子项目']);
  final noteCol = _columnOf(header, const ['备注']);
  final organizerCol = _columnOf(header, const ['学院', '部门']);
  final majorCol = _columnOf(header, const ['专业']);

  final out = <CompetitionEntry>[];
  var fallbackSerial = 0;
  for (var r = 1; r < table.rowCount; r++) {
    final name = ruleCleanText(table.cell(r, nameCol));
    if (name.isEmpty) continue;
    // 表尾的「注：…」行没有序号，且名称列会被并进整段说明 → 跳过。
    if (name.startsWith('注') || name.startsWith('说明')) continue;
    if (name.contains('竞赛项目名称')) continue;

    final serial = int.tryParse(
      ruleCleanText(table.cell(r, serialCol < 0 ? 0 : serialCol)),
    );
    fallbackSerial++;
    final sub = subCol < 0 ? '' : ruleCleanText(table.cell(r, subCol));
    final organizer = organizerCol < 0
        ? ''
        : ruleCleanText(table.cell(r, organizerCol));
    final major = majorCol < 0 ? '' : ruleCleanText(table.cell(r, majorCol));
    final note = noteCol < 0 ? '' : ruleCleanText(table.cell(r, noteCol));
    // 子项目和主项同名（Ⅳ类 rowspan 之外的重复）时不留冗余。
    final subProject = (sub.isEmpty || sub == name) ? null : sub;
    out.add(
      CompetitionEntry(
        serial: serial ?? fallbackSerial,
        name: name,
        klass: klass,
        edition: edition,
        subProject: subProject,
        organizer: organizer.isEmpty ? null : organizer,
        major: major.isEmpty ? null : major,
        note: note.isEmpty ? null : note,
      ),
    );
  }
  return out;
}

/// 表头里第一个含 [needles] 任一子串的列（[exclude] 命中的列不取）。
int _columnOf(
  List<String> header,
  List<String> needles, {
  List<String> exclude = const [],
}) {
  for (var c = 0; c < header.length; c++) {
    final cell = ruleCleanText(header[c]);
    if (cell.isEmpty) continue;
    if (exclude.any(cell.contains)) continue;
    if (needles.any(cell.contains)) return c;
  }
  return -1;
}
