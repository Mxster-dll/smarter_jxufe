import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/graduation_requirement.dart';

/// 解析毕业学分要求 HTML 响应。
class GraduationRequirementsHtmlParser {
  List<GraduationRequirement> parseHtml(String html) {
    final document = html_parser.parse(html);
    final tbody = document.querySelector('#sdTable_tbody');
    if (tbody == null) throw Exception('未找到数据表格');

    final rows = tbody.querySelectorAll('tr');
    final requirements = <GraduationRequirement>[];

    for (final row in rows) {
      final cells = row.children.whereType<Element>().toList();
      if (cells.length < 3) continue;

      // 序号
      final indexText = cells[0].text.trim();
      final index = int.tryParse(indexText) ?? 0;

      // 项目名称
      final itemCell = cells.firstWhere(
        (e) => e.attributes['name'] == 'xm',
        orElse: () => cells[1],
      );
      final item = itemCell.text.trim();

      // 学分
      final creditCell = cells.firstWhere(
        (e) => e.attributes['name'] == 'xf',
        orElse: () => cells[2],
      );
      final creditText = creditCell.text.trim();
      final credit = double.tryParse(creditText) ?? 0;

      // 是否为合计行
      final isTotal = item.contains('合计');

      requirements.add(
        GraduationRequirement(
          index: index,
          item: item,
          credit: credit,
          isTotal: isTotal,
        ),
      );
    }

    if (requirements.isEmpty) throw Exception('未解析到任何数据');

    return requirements;
  }
}
