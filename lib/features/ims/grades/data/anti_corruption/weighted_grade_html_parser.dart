import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/ims/grades/domain/weighted_grade.dart';

/// 解析加权成绩排名 HTML。
///
/// 响应格式：
/// ```
/// <table>
///   <thead><tr><td>学号</td><td>姓名</td><td>课程加权成绩</td>...</tr></thead>
///   <tbody><tr><td>REDACTED_USERNAME</td><td>陈煜仕</td><td>91.50746</td>
///   <td>1</td><td>5</td><td>10</td></tr></tbody>
/// </table>
/// ```
class WeightedGradeHtmlParser {
  WeightedGrade parseHtml(String html) {
    final document = html_parser.parse(html);

    // 找到数据行（tbody 中的 tr）
    final tbody = document.querySelector('tbody');
    if (tbody == null) throw Exception('解析排名数据失败：未找到 tbody');

    final dataRow = tbody.querySelector('tr');
    if (dataRow == null) throw Exception('解析排名数据失败：未找到数据行');

    final cells = dataRow.querySelectorAll('td');
    if (cells.length < 6) throw Exception('解析排名数据失败：单元格数量不足');

    final grade = cells[2].text.trim();
    final classRank = int.tryParse(cells[3].text.trim());
    final majorRank = int.tryParse(cells[4].text.trim());
    final gradeRank = int.tryParse(cells[5].text.trim());

    if (grade.isEmpty ||
        classRank == null ||
        majorRank == null ||
        gradeRank == null) {
      throw Exception('解析排名数据失败：数据格式错误');
    }

    return WeightedGrade(
      grade: grade,
      classRank: classRank,
      majorRank: majorRank,
      gradeRank: gradeRank,
    );
  }
}
