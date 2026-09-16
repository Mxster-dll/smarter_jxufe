/// 教务 `taglib/DataTable.jsp?tableId=<id>` 响应的通用解析。
///
/// 「网上选课」一族的列表（可选课程 2568 / 教学班 6142 / 查询课表 5327042 /
/// 申请扩容 5929098）都是同一套 Kingo 数据列表模板：
/// ```html
/// <tr id='tr0'>
///   <td id='tr0_kc' name='kc' …>[1004001943]会计学</td>
///   …
/// </tr>
/// <script>try{parent.showTotalRecord('2568','11');}catch(e){}</script>
/// ```
/// 所以只写一个解析器：按 `td` 的 `name` 取格，避免依赖列序。
library;

import 'package:html/parser.dart' as html_parser;

/// 一页数据列表：总条数 + 每行的「name → 文本」。
class DataTablePage {
  const DataTablePage({required this.total, required this.rows});

  /// `parent.showTotalRecord('<tableId>','<total>')` 里的 total；解析不到为 null。
  final int? total;

  /// 数据行（表头行不在此列）。
  final List<Map<String, String>> rows;

  bool get isEmpty => rows.isEmpty;

  int get length => rows.length;

  static const DataTablePage empty = DataTablePage(total: 0, rows: []);
}

/// 教务 DataTable 里常见的空白与占位符清洗：
/// `&ensp;` / `&nbsp;` / 换行 / 全角空格 → 单个半角空格，两端去空白。
String normalizeTableCell(String? raw) {
  if (raw == null) return '';
  final replaced = raw
      .replaceAll('\u00a0', ' ')
      .replaceAll('\u3000', ' ')
      .replaceAll('\u2002', ' ');
  return replaced.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 从 `[1004001943]会计学` 这类文本里拆出代码与名称（无方括号时 code 为空）。
({String code, String name}) splitCodedName(String text) {
  final value = normalizeTableCell(text);
  final match = RegExp(r'^\[([^\]]*)\]\s*(.*)$').firstMatch(value);
  if (match == null) return (code: '', name: value);
  return (code: match.group(1)!.trim(), name: match.group(2)!.trim());
}

/// 解析 DataTable.jsp 响应。
DataTablePage parseDataTablePage(String html) {
  if (html.trim().isEmpty) return DataTablePage.empty;
  final document = html_parser.parse(html);
  final total = parseDataTableTotal(html);
  final rows = <Map<String, String>>[];

  for (final row in document.querySelectorAll('tr')) {
    final cells = row.children.where((e) => e.localName == 'td').toList();
    if (cells.isEmpty) continue;
    final values = <String, String>{};
    var named = 0;
    for (final cell in cells) {
      final name = cell.attributes['name'];
      if (name == null || name.isEmpty) continue;
      named++;
      // 同一 name 重复出现时保留第一个非空值（列表里偶有隐藏格重复）。
      final text = normalizeTableCell(cell.text);
      if (!values.containsKey(name) || values[name]!.isEmpty) {
        values[name] = text;
      }
    }
    if (named == 0) continue;
    // `id='head_kc'` 的那行是表头，name 属性不参与，已天然排除；这里再兜一层。
    final name = row.attributes['id'];
    if (name != null && name.startsWith('tr')) rows.add(values);
  }
  return DataTablePage(total: total, rows: rows);
}

/// 读 `parent.showTotalRecord('2568','11')` 的总条数。
int? parseDataTableTotal(String html) {
  final match = RegExp(
    r"showTotalRecord\(\s*'?\d+'?\s*,\s*'?(\d+)'?\s*\)",
  ).firstMatch(html);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// 教务「没有检索到记录」类空结果的判定（GS1/GS4 两种文案）。
bool dataTableIsEmptyResult(String html) =>
    html.contains('没有检索到记录') || html.contains('没有符合检索条件');
