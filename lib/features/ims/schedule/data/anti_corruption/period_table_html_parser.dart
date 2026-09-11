import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/utils/Log.dart';

/// 教务作息时间表 HTML 解析器。
///
/// 目标页面为 `SchoolTimetable.show.jsp` 的报表 iframe，表格形如：
///
/// ```html
/// <tr><td>上课节次</td><td>开始时间</td><td>结束时间</td><td>备注</td></tr>
/// <tr><td rowspan="5">上午</td><td>1</td><td>08:00</td><td>08:45</td><td></td></tr>
/// <tr><td>2</td><td>08:50</td><td>09:35</td><td></td></tr>
/// ...
/// ```
///
/// 由于「上午/下午/晚上」用 `rowspan` 合并，各行单元格数不一致，
/// 故**不按固定列索引取值**，而是逐行扫描「节次整数 + 两个 HH:mm」的模式。
class PeriodTableHtmlParser {
  static final RegExp _periodCell = RegExp(r'^\d{1,2}$');
  static final RegExp _hhmmCell = RegExp(r'^\d{1,2}:\d{2}$');
  static final RegExp _titleCell = RegExp(r'作息时间');

  /// 解析作息表 HTML。
  ///
  /// [termCode] 标记该表所属学年学期（如 `2026-0`），便于排查周次错位。
  /// 解析不出任何节次时返回 null，由调用方回退到内置表。
  PeriodTable? parse(String html, {String? termCode}) {
    final document = parser.parse(html);

    final periods = <ClassPeriod>[];
    for (final tr in document.querySelectorAll('tr')) {
      final cells = tr.children
          .whereType<Element>()
          .map((td) => td.text.trim())
          .toList();
      final period = _parseRow(cells);
      if (period != null) periods.add(period);
    }

    if (periods.isEmpty) {
      logInfo('作息时间表解析为空');
      return null;
    }

    // 去重（同一节次若重复出现，以先出现的为准）
    final seen = <int>{};
    final unique = <ClassPeriod>[];
    for (final p in periods) {
      if (seen.add(p.index)) unique.add(p);
    }
    unique.sort((a, b) => a.index.compareTo(b.index));

    return PeriodTable(
      periods: unique,
      label: _extractTitle(document),
      termCode: termCode,
      source: 'remote',
    );
  }

  /// 从一行单元格中提取节次作息；该行不是作息行时返回 null。
  ClassPeriod? _parseRow(List<String> cells) {
    for (var i = 0; i + 2 < cells.length; i++) {
      if (!_periodCell.hasMatch(cells[i])) continue;
      if (!_hhmmCell.hasMatch(cells[i + 1]) || !_hhmmCell.hasMatch(cells[i + 2])) {
        continue;
      }
      final index = int.tryParse(cells[i]);
      if (index == null || index < 1 || index > 20) continue;
      return ClassPeriod(index: index, start: cells[i + 1], end: cells[i + 2]);
    }
    return null;
  }

  /// 抓取表格标题，如「江西财经大学2026-2027学年第一学期作息时间」。
  String _extractTitle(Document document) {
    for (final el in document.querySelectorAll('td, th, div, b, font')) {
      final text = el.text.trim();
      if (text.isEmpty || text.length > 80) continue;
      if (_titleCell.hasMatch(text)) return text;
    }
    return '教务作息时间表';
  }
}
