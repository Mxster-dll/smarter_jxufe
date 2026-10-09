/// 扫描 `word/document.xml` → 找出**所有需要填的空位**（含清单表）。
///
/// 识别口径（改动前先读，全部由 `test/materials_fill_form_test.dart` 的合成 docx 钉住）：
///
/// 1. **空格找标签**：一个 `w:tc` 的文本为空 → 标签按
///    ① 同一行**往左**最近的「能当标签的文字」→ ② 往**上**找同网格列的**表头**。
///    两步都要过 [_usableLabel]（纯数字 / `例：国一` / `Ⅰ/Ⅱ/Ⅲ类` / `不填` / `照片`
///    这类提示文字不算标签）。
/// 2. **格内标签段**：段落文字以 `：`/`:` 结尾（或「标签：」后跟一串空白）
///    → 就地追加值（「加、减分项目：」「学生姓名：」）。
/// 3. **提示格**：格内非空、但每个非空段落都是提示（`（德、智、体等方面）`/`签名`/
///    `年 月 日`/`（学院公章）`）→ 当成「成段文字」的书写区，值插在提示段之后。
/// 4. **正文段落**：整段都是「标签：<空白>」或一行里若干「标签：<空白>」
///    → 替换那段空白（`学院：                       `）。**后面紧跟「年 / 月 / 日」
///    的不算**（那是日期模板，填进去会串位）。
/// 5. **清单表**：表头行命中 ≥3 个已知列名 → 整张表当一个**可多行编辑的 TSV 字段**
///    （序号/项目/类别/级别/获得时间/附件数/分值…），行不够时按需**复制表格行**。
///
/// 永不填的标签（[_labelIsSkipped]）：各种「意见」、签名、照片、盖章、学院审核分值、
/// 填表人 / 审核人、备注 —— 那些是给别人写的。
library;

import 'package:xml/xml.dart';

import 'docx_dom.dart';
import 'docx_fields.dart';

/// 全空白压缩（含换行、全角空格）—— 标签比对一律在压缩后的形态上做。
String squashLabel(String s) => s.replaceAll(RegExp(r'[\s\u3000]+'), '');

/// 扫描结果。
class DocxScan {
  final List<DocxField> fields;
  final List<DocxListTable> listTables;

  const DocxScan(this.fields, this.listTables);
}

/// 表格行里的一格（已算好网格列）。
class _Cell {
  final XmlElement tc;
  final int index;
  final int gridStart;
  final int gridSpan;
  final bool vMergeContinue;
  final String text;
  final List<XmlElement> paragraphs;

  const _Cell({
    required this.tc,
    required this.index,
    required this.gridStart,
    required this.gridSpan,
    required this.vMergeContinue,
    required this.text,
    required this.paragraphs,
  });
}

class _Row {
  final XmlElement tr;
  final List<_Cell> cells;
  const _Row(this.tr, this.cells);
}

/// 扫描一份 document.xml。
DocxScan docxScan(XmlDocument doc) {
  final fields = <DocxField>[];
  final lists = <DocxListTable>[];
  final body = _findBody(doc);
  if (body == null) return DocxScan(fields, lists);

  var blockSeq = 0;
  var tableIndex = 0;
  for (final block in _blocksOf(body)) {
    if (isW(block, 'p')) {
      blockSeq++;
      _scanBodyParagraph(block, blockSeq, fields);
    } else if (isW(block, 'tbl')) {
      final ti = tableIndex++;
      _scanTable(block, ti, fields, lists);
    }
  }
  return DocxScan(fields, lists);
}

// ---------------------------------------------------------------------------
// 文档骨架
// ---------------------------------------------------------------------------

XmlElement? _findBody(XmlDocument doc) {
  for (final root in doc.childElements) {
    final body = childW(root, 'body');
    if (body != null) return body;
  }
  return null;
}

/// 正文块（`w:p` / `w:tbl`）按顺序展开；`w:sdt` 这类容器里的一并取出。
List<XmlElement> _blocksOf(XmlElement body) {
  final out = <XmlElement>[];
  void walk(XmlElement e) {
    for (final c in e.childElements) {
      if (isW(c, 'p') || isW(c, 'tbl')) {
        out.add(c);
      } else if (isW(c, 'sdt') || isW(c, 'sdtContent')) {
        walk(c);
      }
    }
  }

  walk(body);
  return out;
}

// ---------------------------------------------------------------------------
// 正文段落
// ---------------------------------------------------------------------------

/// 「标签：<两个以上空白>」——标签最多 12 个字，且不含冒号。
final RegExp _labelBlankRe = RegExp(r'([^\s\u3000：:]{1,12})[：:]([ \u3000]{2,})');

/// 标签**往前并词**：`签    名：` 这种被空格拆开的短标签要合回「签名」。
///
/// 只在提取到的标签 ≤2 字时启用，且遇到冒号/句读即停 —— 这样
/// `班级：        学号：` 里的「学号」不会被并成「班级学号」。
String _expandLabel(String text, int start, String label) {
  if (label.length > 2) return label;
  var i = start;
  final words = <String>[];
  while (words.length < 2) {
    var j = i;
    while (j > 0 && (text[j - 1] == ' ' || text[j - 1] == '\u3000')) {
      j--;
    }
    if (j == i || j == 0) break; // 前面不是空白（或到段首）→ 停
    var k = j;
    while (k > 0 && !' \u3000：:，,。；;、（）()'.contains(text[k - 1])) {
      k--;
    }
    if (k == j) break;
    final word = text.substring(k, j);
    if (word.length > 4) break;
    words.insert(0, word);
    i = k;
  }
  return words.isEmpty ? label : '${words.join()}$label';
}

/// 空白之后是不是「还没填」。
///
/// ⚠ 这条是**防重复填**的关键：`学院：  计算机与人工智能学院      学生姓名：` 里
/// 「学院：」后面那两个空格只是排版间隔，值已经写在后面了 —— 不判就会填成
/// 「学院：计算机与人工智能学院计算机与人工智能学院」。
///
/// 判定：空白之后要么到段尾，要么是**另一个标签**（`XX：`）；中间的括号说明
/// （`（盖章）`）穿透。
bool _blankIsSlot(String text, int end) {
  var rest = text.substring(end);
  while (true) {
    final t = rest.trimLeft();
    if (t.isEmpty) return true;
    final note = RegExp(r'^[（(][^）)]{0,20}[）)]').firstMatch(t);
    if (note != null) {
      rest = t.substring(note.end);
      continue;
    }
    return RegExp(r'^[^\s\u3000：:]{1,12}[：:]').hasMatch(t);
  }
}

void _scanBodyParagraph(XmlElement p, int seq, List<DocxField> out) {
  final text = paragraphText(p);
  if (text.trim().isEmpty) return;
  // 末尾补两个全角空格：让「…学号：            专业：」这种**以标签收尾**的行也能命中。
  final padded = '$text\u3000\u3000';
  final real = <RegExpMatch>[];
  final trailing = <RegExpMatch>[];
  for (final m in _labelBlankRe.allMatches(padded)) {
    if (m.start >= text.length) continue; // 整段都在补出来的空白里 → 不是标签
    if (m.end <= text.length) {
      real.add(m);
    } else {
      trailing.add(m);
    }
  }
  // ⚠ 「以标签收尾」只有在**本段本来就有别的空位**时才算空位 —— 否则
  // 《先进个人登记表》标题那种「表1：」也会变成一个待填项（实测会多出一条空行）。
  final usable = [...real, if (real.isNotEmpty) ...trailing];
  for (final m in usable) {
    final label = _expandLabel(padded, m.start, squashLabel(m.group(1)!));
    // ⚠ Dart 的 `Match` **没有分组偏移**（只有整体的 start/end）→ 空位起点自己算：
    // group(1) 之后紧跟一个冒号字符（半角/全角都是一个 code unit）。
    final start = m.start + m.group(1)!.length + 1;
    final end = m.end > text.length ? text.length : m.end;
    if (_labelIsSkipped(label)) continue;
    // 空白之后紧跟「年 / 月 / 日」这类单位 → 日期模板，填进去会串位。
    if (_followedByUnit(text, end)) continue;
    // 值已经写在空白后面了 → 这不是空位。
    if (!_blankIsSlot(padded, m.end)) continue;
    out.add(
      DocxField(
        id: 'b$seq.$start',
        kind: DocxFieldKind.paragraph,
        label: label,
        context: '正文第 $seq 段',
        element: p,
        blankStart: start,
        blankEnd: end,
      ),
    );
  }
}

/// 空白后面紧跟「年/月/日/时/分」→ 是日期时间模板而不是空位。
bool _followedByUnit(String text, int end) {
  final rest = text.substring(end).trimLeft();
  if (rest.isEmpty) return false;
  return RegExp(r'^[年月日时分]').hasMatch(rest);
}

// ---------------------------------------------------------------------------
// 表格
// ---------------------------------------------------------------------------

void _scanTable(
  XmlElement tbl,
  int ti,
  List<DocxField> fields,
  List<DocxListTable> lists,
) {
  final rows = <_Row>[];
  for (final tr in childrenW(tbl, 'tr')) {
    rows.add(_rowOf(tr));
  }
  if (rows.isEmpty) return;

  final list = _detectListTable(ti, rows);
  if (list != null) {
    lists.add(list);
    fields.add(_listTableField(list, rows));
  }

  final listDataRows = list == null ? const <int>{} : list.dataRows.toSet();
  for (var ri = 0; ri < rows.length; ri++) {
    if (list != null && (ri == list.headerRow || listDataRows.contains(ri))) {
      continue; // 表头与清单数据行整体交给 TSV 字段
    }
    final row = rows[ri];
    for (var ci = 0; ci < row.cells.length; ci++) {
      _scanCell(rows, ri, ci, ti, fields);
    }
  }
}

_Row _rowOf(XmlElement tr) {
  final cells = <_Cell>[];
  var col = 0;
  var index = 0;
  for (final tc in childrenW(tr, 'tc')) {
    final pr = childW(tc, 'tcPr');
    final spanEl = pr == null ? null : childW(pr, 'gridSpan');
    final span = spanEl == null ? 1 : (int.tryParse(attrW(spanEl, 'val')) ?? 1);
    var vmContinue = false;
    if (pr != null) {
      final vm = childW(pr, 'vMerge');
      if (vm != null) {
        final v = attrW(vm, 'val');
        vmContinue = v.isEmpty || v == 'continue';
      }
    }
    final safeSpan = span < 1 ? 1 : span;
    final paragraphs = childrenW(tc, 'p').toList();
    cells.add(
      _Cell(
        tc: tc,
        index: index++,
        gridStart: col,
        gridSpan: safeSpan,
        vMergeContinue: vmContinue,
        text: cellText(tc),
        paragraphs: paragraphs,
      ),
    );
    col += safeSpan;
  }
  return _Row(tr, cells);
}

void _scanCell(
  List<_Row> rows,
  int ri,
  int ci,
  int ti,
  List<DocxField> out,
) {
  final row = rows[ri];
  final cell = row.cells[ci];
  if (cell.vMergeContinue) return; // 纵向合并的续格：内容在锚格上
  final ctx = '表 ${ti + 1} · 第 ${ri + 1} 行';
  final group = _rowGroup(rows, ri);
  final raw = cell.text;
  final trimmed = raw.trim();

  if (trimmed.isEmpty) {
    final label = _labelForEmptyCell(rows, ri, ci);
    if (label == null || _labelIsSkipped(label)) return;
    out.add(
      DocxField(
        id: 't$ti.r$ri.c$ci',
        kind: DocxFieldKind.cell,
        label: label,
        context: ctx,
        element: cell.tc,
        group: group,
        tableIndex: ti,
        rowIndex: ri,
        cellIndex: ci,
        gridStart: cell.gridStart,
        gridSpan: cell.gridSpan,
      ),
    );
    return;
  }

  // 「标签独占一格」：整格只有一段、以冒号收尾（`本人申请理由（…）：`）
  // → 这是**成段文字**的题头，值作为新段落写进同一格（题头与说明原样留着）。
  final nonBlankParas = <XmlElement>[
    for (final p in cell.paragraphs)
      if (!isBlankParagraph(p)) p,
  ];
  if (nonBlankParas.length == 1) {
    final only = paragraphText(nonBlankParas.single).trim();
    if (_endsWithColon(only)) {
      final label = _labelOfLabelOnlyCell(only);
      if (label.isNotEmpty && !_labelIsSkipped(label)) {
        out.add(
          DocxField(
            id: 't$ti.r$ri.c$ci.title',
            kind: DocxFieldKind.cellProse,
            label: label,
            context: ctx,
            group: group,
            hint: only,
            element: cell.tc,
            tableIndex: ti,
            rowIndex: ri,
            cellIndex: ci,
            gridStart: cell.gridStart,
            gridSpan: cell.gridSpan,
          ),
        );
      }
      return;
    }
  }

  // 格内「标签：」段落（可能是多个）。
  var hitInline = false;
  for (var pi = 0; pi < cell.paragraphs.length; pi++) {
    final p = cell.paragraphs[pi];
    final ptext = paragraphText(p);
    if (ptext.trim().isEmpty) continue;
    // 末尾补两个全角空格：让「加、减分项目：」这种**标签独占一段**的写法也能命中。
    final probe = '$ptext\u3000\u3000';
    for (final m in _labelBlankRe.allMatches(probe)) {
      final label = _expandLabel(probe, m.start, squashLabel(m.group(1)!));
      if (_labelIsSkipped(label)) continue;
      if (!_blankIsSlot(probe, m.end)) continue;
      hitInline = true;
      out.add(
        DocxField(
          id: 't$ti.r$ri.c$ci.p$pi',
          kind: DocxFieldKind.cellInline,
          label: label,
          context: ctx,
          group: group,
          element: p,
          paragraphIndex: pi,
          tableIndex: ti,
          rowIndex: ri,
          cellIndex: ci,
          gridStart: cell.gridStart,
          gridSpan: cell.gridSpan,
        ),
      );
    }
  }
  if (hitInline) return;

  // 提示格：非空段落全是提示 → 成段文字的书写区。
  final nonBlank = [for (final p in nonBlankParas) paragraphText(p).trim()];
  final allHint = nonBlank.isNotEmpty && nonBlank.every(_isHintLine);
  if (!allHint) return;
  // 格子自己写的就是「照片」这种不可填的提示 → 整格跳过（否则会从左邻取到
  // 「性别」这种驴唇不对马嘴的标签）。
  if (_selfSkippedHint(trimmed)) return;
  final label = _labelForEmptyCell(rows, ri, ci, allowSelf: true);
  if (label == null || _labelIsSkipped(label)) return;
  out.add(
    DocxField(
      id: 't$ti.r$ri.c$ci.prose',
      kind: DocxFieldKind.cellProse,
      label: label,
      context: ctx,
      group: group,
      hint: trimmed,
      element: cell.tc,
      tableIndex: ti,
      rowIndex: ri,
      cellIndex: ci,
      gridStart: cell.gridStart,
      gridSpan: cell.gridSpan,
    ),
  );
}

/// 整格文字以冒号收尾（`本人申请理由（…）：`）。
bool _endsWithColon(String s) {
  final t = s.trimRight();
  return t.endsWith('：') || t.endsWith(':');
}

/// 这一行的**分组标签** = 首格文字（纵向合并时往上取锚格）。
///
/// 综测登记表里「德育 / 智育 / 体育 / 美育 / 劳育」是每 4 行一个的纵向合并锚格，
/// 「合计」「班级评议 X 等次」各出现 5 次 —— 有这个才能分清填哪一育。
String _rowGroup(List<_Row> rows, int ri) {
  final cells = rows[ri].cells;
  if (cells.isEmpty) return '';
  final raw = _inheritedCellText(rows, ri, cells.first);
  final t = squashLabel(raw);
  return t.length > 6 ? '' : t;
}

/// 「标签独占一格」的标签：去掉结尾冒号 + 去掉括号说明。
String _labelOfLabelOnlyCell(String text) {
  var t = text.trim();
  if (_endsWithColon(t)) t = t.substring(0, t.length - 1);
  final cut = t.split(RegExp(r'[（(]')).first;
  return squashLabel(cut.isEmpty ? t : cut);
}

/// 格子自己的提示文字就说明「这格不用你填」。
bool _selfSkippedHint(String cellText) {
  final flat = squashLabel(cellText);
  return flat == '照片' || flat == '备注' || flat.contains('公章') ||
      flat.contains('盖章');
}

/// 给「空/提示格」找标签：同行往左最近的可用标签 → 往上找表头。
String? _labelForEmptyCell(
  List<_Row> rows,
  int ri,
  int ci, {
  bool allowSelf = false,
}) {
  final row = rows[ri];
  final start = allowSelf ? ci : ci - 1;
  for (var i = start; i >= 0; i--) {
    if (row.cells[i].vMergeContinue) continue;
    final t = row.cells[i].text;
    if (_usableLabel(t)) return squashLabel(t);
    // 空格或提示文字继续往左找。
    if (t.trim().isEmpty || _isHintLine(t.trim())) continue;
    // 出现了既不是标签也不是提示的实体文字 → 不再往左（避免跨栏取到无关标签）。
    if (_looksLikeData(t)) return null;
  }
  return _headerLabel(rows, ri, row.cells[ci].gridStart);
}

/// 纯数字 / 很短的数字串 = 数据（序号列），当不了标签也当不了提示。
bool _looksLikeData(String t) {
  final s = squashLabel(t);
  return RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(s) || s.length > 24;
}

/// 往上找同网格列的表头。
String? _headerLabel(List<_Row> rows, int ri, int gridStart) {
  for (var r = ri - 1; r >= 0; r--) {
    _Cell? covering;
    for (final c in rows[r].cells) {
      if (gridStart >= c.gridStart && gridStart < c.gridStart + c.gridSpan) {
        covering = c;
        break;
      }
    }
    if (covering == null) continue;
    // 纵向合并的续格没有内容，锚格在上面 → 继续往上找。
    if (covering.vMergeContinue) continue;
    final t = covering.text;
    if (_usableLabel(t)) return squashLabel(t);
    if (t.trim().isEmpty || _isHintLine(t.trim())) continue;
    return null;
  }
  return null;
}

/// 能不能当标签用。
bool _usableLabel(String raw) {
  final t = squashLabel(raw);
  if (t.isEmpty) return false;
  if (t.length > 20) return false;
  if (RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(t)) return false;
  if (_isHintLine(raw.trim())) return false;
  return true;
}

/// 提示文字（不是内容，也不是标签）。
bool _isHintLine(String line) {
  final t = line.trim();
  if (t.isEmpty) return true;
  if (RegExp(r'^[（(][^）)]{0,60}[）)]$').hasMatch(t)) return true;
  if (t.contains('签名') || t.contains('签章')) return true;
  if (RegExp(r'年\s*月\s*日').hasMatch(t)) return true;
  if (t.startsWith('例：') || t.startsWith('例:')) return true;
  final flat = squashLabel(t);
  if (flat == '不填' || flat == '照片' || flat == '备注') return true;
  if (RegExp(r'^Ⅰ/Ⅱ/Ⅲ类$').hasMatch(flat)) return true;
  if (flat.contains('公章') || flat.contains('盖章')) return true;
  return false;
}

/// 给别人的格子（永不自动填）。
bool _labelIsSkipped(String label) {
  final t = squashLabel(label);
  if (t.isEmpty) return true;
  // 括号里的说明先摘掉再判：「培养单位（公章）：」要填，「（学院公章）」不填。
  final stripped = t.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '');
  final probe = stripped.isEmpty ? t : stripped;
  if (probe.contains('意见')) return true;
  if (probe.contains('签名') || probe.contains('签章')) return true;
  if (probe.contains('照片')) return true;
  if (probe.contains('公章') || probe.contains('盖章')) return true;
  if (probe.contains('审核分值') || probe.contains('审核意见')) return true;
  if (probe.contains('学院负责人') ||
      probe.contains('审核人') ||
      probe.contains('申报人')) {
    return true;
  }
  if (probe.contains('填表人')) return true;
  if (probe.contains('备注')) return true;
  if (probe.contains('审定')) return true;
  // 班主任 / 辅导员 / 班长 / 导师 那一栏是给老师签字的（「班级意见： 班主任：」）。
  for (final who in const ['班主任', '辅导员', '班长', '导师', '主任']) {
    if (probe.contains(who)) return true;
  }
  if (probe == '不填') return true;
  if (probe == '序号') return true;
  return false;
}

// ---------------------------------------------------------------------------
// 清单表
// ---------------------------------------------------------------------------

/// 表头 → 列语义（先精确匹配，再走下面的「包含」规则）。
const Map<String, DocxListColumnKind> _headerKinds = {
  '序号': DocxListColumnKind.seq,
  '姓名': DocxListColumnKind.name,
  '学号': DocxListColumnKind.studentId,
  '班级': DocxListColumnKind.className,
  '行政班级': DocxListColumnKind.className,
  '学院/班级': DocxListColumnKind.collegeClass,
  '性别': DocxListColumnKind.gender,
  '政治面貌': DocxListColumnKind.political,
  '职务': DocxListColumnKind.duty,
  '担任职务': DocxListColumnKind.duty,
  '授予称号': DocxListColumnKind.title,
  '称号': DocxListColumnKind.title,
  '奖学金等级': DocxListColumnKind.scholarship,
  '奖学金': DocxListColumnKind.scholarship,
  '金额': DocxListColumnKind.other,
  '项目': DocxListColumnKind.project,
  '名称': DocxListColumnKind.project,
  '奖项名称': DocxListColumnKind.project,
  '竞赛名称': DocxListColumnKind.project,
  '类别': DocxListColumnKind.category,
  '级别': DocxListColumnKind.level,
  '获得时间': DocxListColumnKind.date,
  '时间': DocxListColumnKind.date,
  '日期': DocxListColumnKind.date,
  '附件数': DocxListColumnKind.attachCount,
  '附件': DocxListColumnKind.attachCount,
  '分值': DocxListColumnKind.score,
  '分数': DocxListColumnKind.score,
  '加分': DocxListColumnKind.score,
  '总分': DocxListColumnKind.total,
  '合计': DocxListColumnKind.total,
  '学院审核分值': DocxListColumnKind.collegeScore,
  '审核分值': DocxListColumnKind.collegeScore,
  '加权成绩': DocxListColumnKind.weighted,
  '加权': DocxListColumnKind.weighted,
  '加权成绩/单科最低分': DocxListColumnKind.weightedMin,
  '德育': DocxListColumnKind.gradeD,
  '智育': DocxListColumnKind.gradeZ,
  '体育': DocxListColumnKind.gradeT,
  '美育': DocxListColumnKind.gradeM,
  '劳育': DocxListColumnKind.gradeL,
  '德育评定等次': DocxListColumnKind.rankD,
  '智育评定等次': DocxListColumnKind.rankZ,
  '体育评定等次': DocxListColumnKind.rankT,
  '美育评定等次': DocxListColumnKind.rankM,
  '劳育评定等次': DocxListColumnKind.rankL,
  '综合测评等次': DocxListColumnKind.overallGrade,
  '综合素质测评等次': DocxListColumnKind.overallGrade,
  '综合测评等级': DocxListColumnKind.overallGrade,
  '测评等次': DocxListColumnKind.overallGrade,
  '测评成绩': DocxListColumnKind.other,
  '加权成绩排名': DocxListColumnKind.other,
  '备注': DocxListColumnKind.other,
};

/// 长表头的**包含**规则（顺序敏感，先匹配到的赢）。
///
/// 《信毅荣誉奖章…候选人简介表》的表头是整句话（`大学期间受表彰情况（限100字以内…）`），
/// 精确匹不上，只能靠关键词。
const List<(String, DocxListColumnKind)> _headerHints = [
  ('受表彰', DocxListColumnKind.honorsText),
  ('突出事迹', DocxListColumnKind.deedsText),
  ('担任学生干部', DocxListColumnKind.dutyText),
  ('科研成果', DocxListColumnKind.researchText),
  ('服务社会', DocxListColumnKind.serviceText),
  ('英语水平', DocxListColumnKind.englishLevel),
  ('单科最低分', DocxListColumnKind.weightedMin),
  ('学院/班级', DocxListColumnKind.collegeClass),
  ('综合测评等级', DocxListColumnKind.overallGrade),
];

/// 表头文案 → 列语义。
DocxListColumnKind? _headerKindOf(String raw) {
  final flat = squashLabel(raw);
  if (flat.isEmpty) return null;
  final direct = _headerKinds[flat];
  if (direct != null) return direct;
  final cut = flat.split(RegExp(r'[（(]')).first;
  final cutHit = _headerKinds[cut];
  if (cutHit != null) return cutHit;
  for (final rule in _headerHints) {
    if (flat.contains(rule.$1)) return rule.$2;
  }
  return null;
}

/// 合计行首格文案。
const List<String> _totalLabels = ['总分', '合计', '总计', '小计'];

/// 一张表是不是清单表；是则给出列结构。
///
/// ⚠ **「人员清单表」的判据必须够紧**，否则《先进个人登记表》《综合素质测评登记表》
/// 这种**表单**会被误判成清单（它们的第一行同样是「姓名 |  | 班级 |  | 性别」），
/// 结果整张表的空位被吞成一行 TSV，别的项一个都识别不出来。三条闸门：
/// ① 表头行**没有空格**（真表头是一排标签，表单行里夹着待填空格）；
/// ② 或者识别出的列 ≥5；③ 或者下一行首格是「示例」（表 7/表 8 那种模版行）。
DocxListTable? _detectListTable(int ti, List<_Row> rows) {
  var bestRow = -1;
  var bestCols = <DocxListColumn>[];
  for (var ri = 0; ri < rows.length && ri < 3; ri++) {
    final cols = <DocxListColumn>[];
    for (final c in rows[ri].cells) {
      if (c.gridSpan > 2) continue; // 大合并格是分组标题，不是列头
      final raw = _inheritedCellText(rows, ri, c);
      final kind = _headerKindOf(raw);
      if (kind == null) continue;
      cols.add(
        DocxListColumn(
          kind: kind,
          header: squashLabel(raw),
          gridStart: c.gridStart,
          gridSpan: c.gridSpan,
        ),
      );
    }
    if (cols.length > bestCols.length) {
      bestRow = ri;
      bestCols = cols;
    }
  }
  if (bestRow < 0 || bestCols.length < 3) return null;
  final kinds = {for (final c in bestCols) c.kind};
  final material = kinds.contains(DocxListColumnKind.project) &&
      (kinds.contains(DocxListColumnKind.score) ||
          kinds.contains(DocxListColumnKind.level) ||
          kinds.contains(DocxListColumnKind.date) ||
          kinds.contains(DocxListColumnKind.attachCount) ||
          kinds.contains(DocxListColumnKind.category));
  var roster = (kinds.contains(DocxListColumnKind.name) ||
          kinds.contains(DocxListColumnKind.studentId)) &&
      !material;
  if (roster) {
    final headerHasBlank = rows[bestRow].cells.any(
      (c) => squashLabel(_inheritedCellText(rows, bestRow, c)).isEmpty,
    );
    final nextRow = bestRow + 1 < rows.length ? rows[bestRow + 1] : null;
    final nextIsTemplate =
        nextRow != null &&
        nextRow.cells.isNotEmpty &&
        squashLabel(nextRow.cells.first.text) == '示例';
    if (headerHasBlank && bestCols.length < 5 && !nextIsTemplate) {
      roster = false;
    }
  }
  if (!material && !roster) return null;

  final dataRows = <int>[];
  int? totalRow;
  for (var ri = bestRow + 1; ri < rows.length; ri++) {
    final head = rows[ri].cells.isEmpty
        ? ''
        : squashLabel(rows[ri].cells.first.text);
    if (_totalLabels.contains(head)) {
      totalRow ??= ri;
      continue;
    }
    if (_isRepeatHeaderRow(rows[ri])) continue;
    dataRows.add(ri);
  }
  if (dataRows.isEmpty) return null;
  return DocxListTable(
    tableIndex: ti,
    headerRow: bestRow,
    dataRows: dataRows,
    totalRow: totalRow,
    columns: bestCols,
    materialRows: material,
  );
}

bool _isRepeatHeaderRow(_Row row) {
  var hits = 0;
  for (final c in row.cells) {
    if (_headerKindOf(c.text) != null) hits++;
  }
  return hits >= 3;
}

DocxField _listTableField(DocxListTable list, List<_Row> rows) {
  final desc = list.columns.map((c) => c.header).join(' · ');
  return DocxField(
    id: 'list${list.tableIndex}',
    kind: DocxFieldKind.listTable,
    label: list.materialRows ? '材料清单表' : '人员清单表',
    context: '表 ${list.tableIndex + 1} · 可填 ${list.dataRows.length} 行',
    element: rows[list.headerRow].tr,
    hint: '列序：$desc',
    tableIndex: list.tableIndex,
    listTable: list,
  );
}

/// 单元格文字，**纵向合并的续格往上取锚格**。
///
/// 《综测班级汇总表》的表头是两行：R00 写「姓名 | 学号 | 测评成绩 | 综合测评等次」，
/// R01 才写「德育 | 德育评定等次 | …」并让前两格纵向合并继承 R00 —— 不做继承
/// 就会认不出「姓名 / 学号」这两列，整张表也就判不成「人员清单表」
/// （实测退化成 240 个逐格待填项）。
String _inheritedCellText(List<_Row> rows, int ri, _Cell cell) {
  if (!cell.vMergeContinue && cell.text.trim().isNotEmpty) return cell.text;
  for (var r = ri - 1; r >= 0; r--) {
    _Cell? covering;
    for (final c in rows[r].cells) {
      if (cell.gridStart >= c.gridStart &&
          cell.gridStart < c.gridStart + c.gridSpan) {
        covering = c;
        break;
      }
    }
    if (covering == null) continue;
    if (covering.vMergeContinue) continue;
    return covering.text;
  }
  return cell.text;
}
