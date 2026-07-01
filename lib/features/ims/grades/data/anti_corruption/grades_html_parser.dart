import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_result.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/semester.dart';

/// 解析成绩 HTML 响应。
///
/// 新 HTML 结构（无汇总表）：
/// - 每个学期由 "border:none" 的学期标题 table + 数据 table 组成
/// - 多个学期依次排列，全部合并为一张大表
class GradesHtmlParser {
  GradesResult parseHtml(String html) {
    final document = html_parser.parse(html);
    final tables = document.querySelectorAll('table');

    // 分离学期标题表和数据表
    final semesterTables = <Element>[];
    final dataTables = <Element>[];

    for (final table in tables) {
      final style = table.attributes['style'] ?? '';
      if (style.contains('border:none')) {
        semesterTables.add(table);
      } else {
        dataTables.add(table);
      }
    }

    if (dataTables.isEmpty) {
      throw Exception('未找到数据 table');
    }

    // 学期标题表和数据表一一对应：
    // semesterTables[i] → dataTables[i]（学期标题在数据表之前）
    // 如果数量不匹配，尽可能配对
    final allGrades = <Grade>[];
    for (int i = 0; i < dataTables.length; i++) {
      String semesterCode = '';
      if (i < semesterTables.length) {
        semesterCode = _extractSemesterCode(semesterTables[i]);
      }
      final grades = _parseGrades(dataTables[i], semesterCode);
      allGrades.addAll(grades);
    }

    return GradesResult(grades: allGrades);
  }

  /// 从学期标题 table 中提取学期短编号，如 "251"。
  String _extractSemesterCode(Element table) {
    final text = table.text.trim();
    final match = RegExp(r'学年学期：(.+)').firstMatch(text);
    if (match != null) {
      try {
        return Semester.parse(match.group(1)!).shortCode;
      } catch (_) {
        return '';
      }
    }
    return '';
  }

  List<Grade> _parseGrades(Element table, String semesterCode) {
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
          semester: semesterCode,
        ),
      );
    }

    return grades;
  }
}
