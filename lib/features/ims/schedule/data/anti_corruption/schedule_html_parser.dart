import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import 'package:smarter_jxufe/utils/Log.dart';

class ScheduleHtmlParser {
  List<List<String>> parse(String html) {
    final document = parser.parse(html);
    final tables = document.querySelectorAll('table');

    if (tables.length != 2) {
      logInfo(html);
      throw Exception('期望有2个 table，但找到了${tables.length}个 table\n $tables');
    }

    final table = tables[1];

    final rows = table
        .querySelectorAll('tr')
        .where((tr) => !tr.classes.contains('H'))
        .toList();
    final List<List<String>> result = [];

    for (var tr in rows) {
      final tds = tr.children
          .whereType<Element>()
          .where((td) => !td.classes.contains('td1'))
          .toList();

      final rowCells = tds.map((td) {
        for (final br in td.querySelectorAll('br')) {
          br.replaceWith(Text('\n'));
        }
        return td.text.trim();
      }).toList();

      if (rowCells.isNotEmpty) {
        result.add(rowCells);
      }
    }

    return result;
  }
}
