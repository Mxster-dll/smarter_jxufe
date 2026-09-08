import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';

import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';

/// 把教务系统 `SchoolCalendar.show.jsp` 返回的校历 HTML 解析为 [SchoolCalendar]。
///
/// 页面结构（实测 2025-2026 学年三学段同构）：
/// - 外层一个布局大表，左列自上而下嵌套多个「月份表」，右列是
///   `<textarea name="bz">` 备注；
/// - 每个月份表：
///   - 第 1 行：`月份` + 跨 7 列的本月「2026-03」；
///   - 第 2 行：`周次` + 一~日表头；
///   - 之后每行：第 1 格 = 教学周次，第 2~8 格 = 周一~周日日期
///     （`<span class="workday|nonday">数字</span>`），无日期为空；
///   - 末尾可能有整行空白缓冲行。
class SchoolCalendarHtmlParser {
  SchoolCalendar parse(String html, {required int xn, required int xq}) {
    final document = parser.parse(html);

    // 备注：<textarea name="bz"> 内容，按行拆。
    final notes = <String>[];
    final bz = document.querySelector('textarea[name="bz"]');
    if (bz != null) {
      for (final raw in bz.text.split(RegExp(r'[\r\n]+'))) {
        final line = raw.trim();
        if (line.isNotEmpty) notes.add(line);
      }
    }

    // 月份表：所有 table 中首行文本含「月份」的表。
    final monthTables = document
        .querySelectorAll('table')
        .where((table) => _hasMonthHeader(table))
        .toList();
    if (monthTables.isEmpty) {
      throw Exception(
        '校历 HTML 解析失败：未找到月份表（共 ${document.querySelectorAll('table').length} 张表）',
      );
    }

    final months = <CalendarMonth>[];
    for (final table in monthTables) {
      months.add(_parseMonthTable(table));
    }

    // 标题：优先解析页内大字标题，失败则用 (xn, xq) 拼接。
    var title = _parsePageTitle(document) ?? buildCalendarTitle(xn, xq);

    return SchoolCalendar(
      title: title,
      xn: xn,
      xq: xq,
      months: months,
      notes: notes,
    );
  }

  /// 判定该表是月份表：首行恰好两个 td（`月份` + 形如 `2026-03` 的值）。
  bool _hasMonthHeader(Element table) {
    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) return false;
    final firstCells = rows.first.querySelectorAll('td');
    if (firstCells.length != 2) return false;
    final label = _text(firstCells[0]);
    final ym = _text(firstCells[1]);
    if (!label.contains('月份')) return false;
    return RegExp(r'^\d{4}-\d{1,2}$').hasMatch(ym);
  }

  CalendarMonth _parseMonthTable(Element table) {
    final rows = table.querySelectorAll('tr');
    if (rows.length < 3) {
      throw Exception('校历月份表行数异常：${rows.length}');
    }

    // 行 0：月份（第 2 个 td 是「2026-03」）。
    final headerCells = rows[0].querySelectorAll('td');
    final ym = _text(headerCells.length > 1 ? headerCells[1] : null);
    final ymMatch = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(ym);
    if (ymMatch == null) {
      throw Exception('校历月份头无法解析："$ym"');
    }
    final year = int.parse(ymMatch.group(1)!);
    final month = int.parse(ymMatch.group(2)!);

    final weekRows = <CalendarWeekRow>[];
    for (var i = 2; i < rows.length; i++) {
      final cells = rows[i].querySelectorAll('td');
      if (cells.isEmpty) continue;
      final weekNoRaw = _text(cells.first).trim();
      final weekNo = weekNoRaw.isEmpty ? null : weekNoRaw;

      final days = <int?>[];
      for (var c = 1; c < cells.length && c <= 7; c++) {
        days.add(int.tryParse(_text(cells[c]).trim()));
      }
      while (days.length < 7) {
        days.add(null);
      }

      final row = CalendarWeekRow(weekNo: weekNo, days: days.take(7).toList());
      if (!row.isEmpty) weekRows.add(row);
    }

    return CalendarMonth(year: year, month: month, rows: weekRows);
  }

  /// 页面大字标题（如「江西财经大学2025-2026学年第一学期校历」）。
  String? _parsePageTitle(Document document) {
    final reg = RegExp(r'江西财经大学\d{4}-\d{4}学年(?:第一学期|第二学期|第二阶段)校历');
    // 标题字通常在 body 开头的表格文本里；直接全文搜第一个匹配。
    final body = document.body;
    if (body == null) return null;
    final m = reg.firstMatch(_onlyVisibleText(body));
    return m?.group(0);
  }

  /// 取去标签后的可见文本（不含 script/style 内容）。
  String _onlyVisibleText(Element root) {
    final buf = StringBuffer();
    void walk(Element node) {
      for (final child in node.nodes) {
        if (child is Element) {
          if (child.localName == 'script' || child.localName == 'style') {
            continue;
          }
          walk(child);
        } else if (child is Text) {
          buf.write(child.text);
        }
      }
    }

    walk(root);
    return buf.toString();
  }

  String _text(Element? element) {
    if (element == null) return '';
    return element.text.trim();
  }
}
