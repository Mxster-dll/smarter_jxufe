import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/curriculum_mapper.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';
import 'package:smarter_jxufe/features/ims/data/ims_exception.dart';

/// 解析「培养方案 · 实践环节」的 HTML（`DataTable.jsp?tableId=2509`）。
///
/// 口径：**按 `<td name="…">` 取列**，不按下标 —— 表里夹着隐藏列
/// （`hjdm`，`style='display:none'`），按下标在别的专业上会错位。
/// 单测用真实抓包 `test/fixtures/curriculum_practice_2509.html` 钉着。
class PracticeCurriculumHtmlParser {
  const PracticeCurriculumHtmlParser();

  List<PracticeStage> parseHtml(String html) {
    final document = html_parser.parse(html);
    final tbody = document.querySelector('#sdTable_tbody');
    if (tbody == null) throw ImsApiException('未找到实践环节数据表格');

    final stages = <PracticeStage>[];
    for (final row in tbody.querySelectorAll('tr')) {
      final cells = row.children.whereType<Element>().toList();
      if (cells.isEmpty) continue;

      String named(String name) {
        for (final c in cells) {
          if (c.attributes['name'] == name) return c.text.trim();
        }
        return '';
      }

      // 「环节」列是 [代码]名称；没带 [代码] 时整串当名称
      final rawStage = named('hj');
      final (code, name) = CurriculumMapper.extractCodeAndName(rawStage);
      if (name.isEmpty && code.isEmpty) continue;

      final indexText = cells.first.text.trim();
      stages.add(
        PracticeStage(
          index: int.tryParse(indexText) ?? stages.length + 1,
          semester: named('xnxq'),
          code: code,
          name: name.isEmpty ? rawStage : name,
          credit: double.tryParse(named('xf')) ?? 0,
          category: named('hjlb'),
          assessment: named('khfs'),
          weeks: double.tryParse(named('zs')) ?? 0,
          identification: named('bs'),
          detailId: named('hjdm'),
        ),
      );
    }
    return stages;
  }
}
