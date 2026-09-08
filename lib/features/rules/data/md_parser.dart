import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../domain/doc_blocks.dart';

/// 将提取器产出的结构化 md 解析为 [DocArticle]。
///
/// md 版式约定（来自 pdf2md v4 产物）：
/// - `#/##/### ` 标题行；
/// - `<table>…</table>` 为表格块（保留 colspan/rowspan 合并结构）；
/// - 空行分隔段落块（块内换行已由提取器消除，这里仅兜底拼接）。
class MdParser {
  static final _collapseGap = RegExp(
    r'(?<=[\u3400-\u9fff0-9])\s+(?=[\u3400-\u9fff0-9（）《》「」『』〔〕])'
    r'|(?<=[\u3400-\u9fff0-9（）《》「」『』〔〕])\s+(?=[\u3400-\u9fff0-9])',
  );
  static final _chapterBody = RegExp(r'^第[一二三四五六七八九十百零]+章(.*)$');
  static final _headerRow = RegExp(r'^\s*\|?[\s:|-]+\|?\s*$');

  /// 清理提取残留：折叠 CJK/CJK、CJK/数字 之间的空格（保留拉丁词间距）。
  static String clean(String s) => s.replaceAll(_collapseGap, ' ').trim();

  DocArticle parse(String md) {
    final lines = md.split('\n');
    final blocks = <DocBlock>[];
    var buf = <String>[]; // 段落行缓冲

    void flushPara() {
      if (buf.isEmpty) return;
      var text = '';
      for (final raw in buf) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (text.isEmpty) {
          text = line;
        } else {
          final needSpace = _endsLatin(text) && _startsLatin(line);
          text = '$text${needSpace ? ' ' : ''}$line';
        }
      }
      buf = [];
      if (text.isNotEmpty) blocks.add(DocBlock.para(clean(text)));
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i].trimRight();
      final t = line.trim();
      if (t.isEmpty) {
        flushPara();
        i++;
        continue;
      }
      if (t.startsWith('#')) {
        final m = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(t);
        flushPara();
        if (m != null) {
          final lvl = m.group(1)!.length;
          final text = m.group(2)!.trim();
          if (text.isNotEmpty) blocks.add(DocBlock.heading(text, level: lvl));
        }
        i++;
        continue;
      }
      if (t.startsWith('<table>')) {
        flushPara();
        final buf = <String>[];
        while (i < lines.length) {
          final r = lines[i];
          buf.add(r);
          i++;
          if (r.trimRight().endsWith('</table>')) break;
        }
        final table = _buildHtmlTable(buf.join('\n'));
        if (table != null) blocks.add(DocBlock.tableBlock(table));
        continue;
      }
      if (t.startsWith('|')) {
        flushPara();
        final rows = <List<String>>[];
        while (i < lines.length) {
          final r = lines[i].trim();
          if (!r.startsWith('|')) break;
          if (!_headerRow.hasMatch(r)) {
            rows.add(_splitRow(r));
          }
          i++;
        }
        final table = _buildTable(rows);
        if (table != null) blocks.add(DocBlock.tableBlock(table));
        continue;
      }
      buf.add(line);
      i++;
    }
    flushPara();

    _absorbChapterTitles(blocks);
    return DocArticle(blocks: blocks, chapters: _collectChapters(blocks));
  }

  static bool _endsLatin(String s) =>
      s.isNotEmpty && RegExp(r'[A-Za-z0-9]$').hasMatch(s);

  static bool _startsLatin(String s) =>
      s.isNotEmpty && RegExp(r'^[A-Za-z0-9]').hasMatch(s);

  static List<String> _splitRow(String row) {
    var s = row.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s.split('|').map((c) => clean(c)).toList();
  }

  /// 解析内嵌 HTML 表格（pdf2md v4 产物，含 colspan/rowspan）。
  TableData? _buildHtmlTable(String html) {
    final frag = html_parser.parseFragment(html);
    dom.Element? tableEl;
    for (final child in frag.children) {
      if (child.localName == 'table') {
        tableEl = child;
        break;
      }
    }
    if (tableEl == null) return null;
    final trs = tableEl.querySelectorAll('tr')
        .where((e) => e.localName == 'tr')
        .toList();
    if (trs.isEmpty) return null;

    // 逻辑行：每行 cells = [(text, cs, rs)]（缺省 1×1）。
    final logical = <List<(String, int, int)>>[];
    for (final tr in trs) {
      final cells = <(String, int, int)>[];
      for (final cell in tr.children) {
        if (cell.localName != 'td' && cell.localName != 'th') continue;
        final cs = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
        final rs = int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1;
        cells.add((clean(cell.text.replaceAll('\u00a0', ' ')), cs, rs));
      }
      logical.add(cells);
    }
    final ncol = logical.first.fold<int>(
        0, (a, c) => a + (c.$2 > 0 ? c.$2 : 1));
    if (ncol == 0 || ncol > 40) return null; // 防畸形表

    // 行流式物理化：rowspan 占位槽推进。
    // pending: col -> 还需占位行数（含下一行）。每行开始时将 pending 键
    // 计入本轮 occ（本行被占、跳过填格），计数减一后转移回 pending。
    final physical = <List<String>>[];
    final spans = <int, TableSpan>{};
    var pending = <int, int>{};
    for (var ri = 0; ri < logical.length; ri++) {
      final occ = <int>{};
      final nextPending = <int, int>{};
      for (final e in pending.entries) {
        occ.add(e.key); // 本行该列被上行 rowspan 覆盖
        final left = e.value - 1;
        if (left > 0) nextPending[e.key] = left;
      }
      pending = nextPending;
      final row = List<String>.filled(ncol, '');
      final cells = logical[ri];
      var col = 0;
      for (final (text, cs, rs) in cells) {
        while (col < ncol && occ.contains(col)) {
          col++; // 洞槽
        }
        if (col >= ncol) break; // 行溢出：截断防御
        row[col] = text;
        if (cs > 1 || rs > 1) {
          spans[ri * ncol + col] = TableSpan(rs, cs);
        }
        if (rs > 1) {
          for (var k = 0; k < cs; k++) {
            pending[col + k] = rs - 1; // 未来 rs-1 行继续占位
          }
        }
        col += cs;
      }
      physical.add(row);
    }
    if (physical.isEmpty) return null;
    final headers = physical.first;
    final body = physical.skip(1).toList();
    return TableData(headers: headers, rows: body, spans: spans);
  }

  /// 旧式管道表（兜底，pdf2md v3 及更早资产）。
  TableData? _buildTable(List<List<String>> rows) {
    if (rows.isEmpty) return null;
    final ncol = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    if (ncol == 0) return null;
    final norm = rows.map((r) {
      final out = List<String>.of(r);
      while (out.length < ncol) {
        out.add('');
      }
      return out.sublist(0, ncol);
    }).toList();

    final headers = norm.first;
    final body = norm.skip(1).toList();

    // 去掉整列为空的尾部列（pdf 表格边界噪声）。
    var last = ncol;
    while (last > 1) {
      final colEmpty = body.every((r) => r[last - 1].isEmpty);
      if (!colEmpty) break;
      last--;
    }
    return TableData(
      headers: headers.sublist(0, last),
      rows: body.map((r) => r.sublist(0, last)).toList(),
    );
  }

  /// 「### 第一章」+ 独立一行「总则」→ 合并为「第一章 总则」。
  void _absorbChapterTitles(List<DocBlock> blocks) {
    for (var i = 0; i < blocks.length - 1; i++) {
      final b = blocks[i];
      if (b.kind != BlockKind.heading) continue;
      final m = _chapterBody.firstMatch(b.text);
      if (m == null || m.group(1)!.isNotEmpty) continue; // 仅当「第一章」无章名
      final next = blocks[i + 1];
      if (next.kind != BlockKind.para) continue;
      final name = next.text.trim();
      if (name.isEmpty ||
          name.length > 16 ||
          RegExp(r'[。；：!?]|^第|^[（(]|^\d').hasMatch(name)) {
        continue;
      }
      blocks[i] = DocBlock.heading('${b.text} $name', level: b.level);
      blocks.removeAt(i + 1);
    }
  }

  List<ChapterRef> _collectChapters(List<DocBlock> blocks) {
    final out = <ChapterRef>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.kind != BlockKind.heading) continue;
      if (_chapterBody.hasMatch(b.text)) {
        out.add(ChapterRef(label: b.text, blockIndex: i));
      }
    }
    return out;
  }
}
