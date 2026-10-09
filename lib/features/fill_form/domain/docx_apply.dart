/// 把「填好的值」写回 docx 的 XML 树。
///
/// ⚠ **永远在「新解析出来的那份文档」上写**（`DocxForm.export` 每次重新解析原始
/// 字节 + 重扫一遍，用 [DocxField.id] 对位）。这样：
/// - 反复导出幂等（同一份值导两次，第二次不会在已有内容后面再贴一遍）；
/// - 字段一旦被写过，重扫时它就不再是「空位」，自然不会被重复计入。
///
/// 空值的口径 = **不写**（保持文档原样）。这正是「空着的项自动留空」：
/// 我们只会往原本就空的位置写，所以「不写」就等于「还是空的」。
library;

import 'package:xml/xml.dart';

import 'docx_dom.dart';
import 'docx_fields.dart';
import 'docx_scan.dart';

/// 按 [values]（field id → 文本）写回。
///
/// 返回真正写进去的字段数（便于 UI 给一句「已填 N 项」）。
int docxApplyValues(DocxScan scan, Map<String, String> values) {
  var applied = 0;
  // 正文段落：同一段里的多个空位要**从后往前**替换，否则先替换的会挪动后面的偏移。
  final paragraphFields = <XmlElement, List<DocxField>>{};
  for (final f in scan.fields) {
    if (f.kind != DocxFieldKind.paragraph) continue;
    final v = values[f.id];
    if (v == null || v.trim().isEmpty) continue;
    paragraphFields.putIfAbsent(f.element, () => []).add(f);
  }
  paragraphFields.forEach((p, list) {
    list.sort((a, b) => b.blankStart.compareTo(a.blankStart));
    var text = paragraphText(p);
    for (final f in list) {
      if (f.blankEnd > text.length) continue;
      final v = values[f.id]!;
      // 空白不在段尾时留一个空格，免得「学院：X填表日期：」两个标签粘在一起。
      final tail = f.blankEnd < text.length ? ' ' : '';
      text = text.replaceRange(f.blankStart, f.blankEnd, '$v$tail');
      applied++;
    }
    setParagraphText(p, text);
  });

  for (final f in scan.fields) {
    final v = values[f.id];
    if (v == null || v.trim().isEmpty) continue;
    switch (f.kind) {
      case DocxFieldKind.paragraph:
        break; // 上面已处理
      case DocxFieldKind.cell:
        if (_writeCell(f.element, v)) applied++;
      case DocxFieldKind.cellInline:
        appendParagraphText(f.element, v);
        applied++;
      case DocxFieldKind.cellProse:
        if (_writeProse(f.element, v)) applied++;
      case DocxFieldKind.listTable:
        applied += _writeListTable(f, v);
    }
  }
  return applied;
}

/// 整格写值：写进格内**第一段**（空格的段落格式正是用户期望的）。
bool _writeCell(XmlElement tc, String value) {
  var ps = childrenW(tc, 'p').toList();
  if (ps.isEmpty) {
    final p = XmlElement(XmlName.fromString('w:p'));
    tc.children.add(p);
    ps = [p];
  }
  setParagraphText(ps.first, value);
  return true;
}

/// 提示格（成段文字）：写进「第一个提示段之后的第一个空段」；没有空段就在提示段
/// 后面插一段新的（这样提示文字与 `签名 年 月 日` 都原样留着）。
bool _writeProse(XmlElement tc, String value) {
  final ps = childrenW(tc, 'p').toList();
  if (ps.isEmpty) return _writeCell(tc, value);
  var hintAt = -1;
  for (var i = 0; i < ps.length; i++) {
    if (!isBlankParagraph(ps[i])) {
      hintAt = i;
      break;
    }
  }
  if (hintAt < 0) return _writeCell(tc, value);
  for (var i = hintAt + 1; i < ps.length; i++) {
    if (isBlankParagraph(ps[i])) {
      setParagraphText(ps[i], value);
      return true;
    }
  }
  final fresh = buildParagraph(template: ps[hintAt]);
  insertAfterNode(ps[hintAt], fresh);
  setParagraphText(fresh, value);
  return true;
}

/// 清单表：把 TSV 逐行逐列写进网格；行不够就**复制最后一个数据行**。
int _writeListTable(DocxField field, String tsv) {
  final list = field.listTable;
  if (list == null) return 0;
  final parent = field.element.parent;
  if (parent is! XmlElement) return 0;
  final tbl = parent;
  final lines = [
    for (final line in tsv.split('\n'))
      if (line.trim().isNotEmpty) line,
  ];
  if (lines.isEmpty) return 0;

  final rows = childrenW(tbl, 'tr').toList();
  final dataRowEls = <XmlElement>[
    for (final ri in list.dataRows)
      if (ri >= 0 && ri < rows.length) rows[ri],
  ];
  if (dataRowEls.isEmpty) return 0;

  // 行不够 → 复制最后一个数据行，插在它后面（合计行保持在最后）。
  var last = dataRowEls.last;
  while (dataRowEls.length < lines.length) {
    final clone = last.copy();
    insertAfterNode(last, clone);
    dataRowEls.add(clone);
    last = clone;
  }

  var applied = 0;
  for (var i = 0; i < lines.length; i++) {
    final cells = lines[i].split('\t');
    final tr = dataRowEls[i];
    for (var j = 0; j < list.columns.length && j < cells.length; j++) {
      final value = cells[j].trim();
      if (value.isEmpty) continue;
      final tc = _cellAtGrid(tr, list.columns[j].gridStart);
      if (tc == null) continue;
      _writeCell(tc, value);
      applied++;
    }
  }
  return applied;
}

/// 取一行里覆盖某个网格列的 `w:tc`。
XmlElement? _cellAtGrid(XmlElement tr, int gridStart) {
  var col = 0;
  for (final tc in childrenW(tr, 'tc')) {
    final pr = childW(tc, 'tcPr');
    final spanEl = pr == null ? null : childW(pr, 'gridSpan');
    final span = spanEl == null ? 1 : (int.tryParse(attrW(spanEl, 'val')) ?? 1);
    final safe = span < 1 ? 1 : span;
    if (gridStart >= col && gridStart < col + safe) return tc;
    col += safe;
  }
  return null;
}
