import 'package:html/parser.dart' as parser;

import 'package:smarter_jxufe/utils/Log.dart';
import 'package:smarter_jxufe/core/extension/dom_element_extension.dart';

class CurriculumHtmlParser {
  List<List<String>> parse(String html) {
    final document = parser.parse(html);
    final tables = document.querySelectorAll('table');

    if (tables.length != 1) {
      logInfo(html);
      throw Exception('期望有1个 table，但找到了${tables.length}个 table\n $tables');
    }

    return tables.first.toMatrix;
  }
}
