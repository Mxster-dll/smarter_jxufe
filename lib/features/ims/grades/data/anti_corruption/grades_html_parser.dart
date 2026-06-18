import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';

/// 解析成绩 HTML 响应。
///
/// HTML 结构：3 个 table
/// - table[0]: style 含 border:none，学年学期信息（跳过）
/// - table[1]: 成绩明细表（tbody 中每行一门课）
/// - table[2]: 汇总统计表
class GradesHtmlParser {
  GradesResult parseHtml(String html) {
    final document = html_parser.parse(html);
    final tables = document.querySelectorAll('table');

    // 过滤掉 border:none 的元数据 table，取数据 table
    final dataTables = tables.where((t) {
      final style = t.attributes['style'] ?? '';
      return !style.contains('border:none');
    }).toList();

    if (dataTables.length < 2) {
      throw Exception('期望至少2个数据 table，找到了${dataTables.length}个');
    }

    // dataTables[0] = 成绩明细, dataTables[1] = 汇总
    final grades = _parseGrades(dataTables[0]);
    final summaries = _parseSummaries(dataTables[1]);

    return GradesResult(grades: grades, summaries: summaries);
  }

  List<Grade> _parseGrades(Element table) {
    final tbody = table.querySelector('tbody');
    if (tbody == null) return [];

    final rows = tbody.querySelectorAll('tr');
    final grades = <Grade>[];

    for (final row in rows) {
      final cells = row.children.whereType<Element>().toList();
      if (cells.length < 10) continue;

      final rawCourse = cells[1].text.trim();
      final codeMatch = RegExp(r'^\[(\w+)\]').firstMatch(rawCourse);
      final courseCode = codeMatch?.group(1) ?? '';
      final courseName = rawCourse.replaceFirst(RegExp(r'^\[\w+\]'), '').trim();

      grades.add(
        Grade(
          index: cells[0].text.trim(),
          courseCode: courseCode,
          courseName: courseName,
          credit: cells[2].text.trim(),
          category: cells[3].text.trim(),
          nature: cells[4].text.trim(),
          examType: cells[5].text.trim(),
          score: cells[6].text.trim(),
          earnedCredit: cells[7].text.trim(),
          gradePoint: cells[8].text.trim(),
          creditGradePoint: cells[9].text.trim(),
          notes: cells.length > 10 ? cells[10].text.trim() : '',
        ),
      );
    }

    return grades;
  }

  List<GradeSummary> _parseSummaries(Element table) {
    final tbody = table.querySelector('tbody');
    if (tbody == null) return [];

    final rows = tbody.querySelectorAll('tr');
    final summaries = <GradeSummary>[];

    for (final row in rows) {
      final cells = row.children.whereType<Element>().toList();
      if (cells.length < 7) continue;

      summaries.add(
        GradeSummary(
          category: cells[0].text.trim(),
          courseCount: cells[1].text.trim(),
          credit: cells[2].text.trim(),
          earnedCredit: cells[3].text.trim(),
          earnedGradePoint: cells[4].text.trim(),
          earnedCreditGradePoint: cells[5].text.trim(),
          avgGradePoint: cells[6].text.trim(),
        ),
      );
    }

    return summaries;
  }
}
