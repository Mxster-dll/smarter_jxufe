import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:html/dom.dart' as dom;

import 'package:smarter_jxufe/Log.dart';
import 'package:smarter_jxufe/ims/Subject.dart';
import 'package:smarter_jxufe/ims/AcademicTime.dart';
import 'package:smarter_jxufe/ims/Grades.dart';
import 'package:smarter_jxufe/ims/imsService.dart';

class GradeService {
  final ImsService _imsService;

  WeightedType weightedType = .courseAll;
  TimeLimit timeLimit = .semester;
  AcademicYear academicYear = .now;
  SemesterType semesterType = .first;
  SubjectFilter subjectFilter = .all;
  bool showRawGrade = false;
  bool onlyNotPassed = false;

  bool get selectedMajor => subjectFilter != .minor;
  bool get selectedMinor => subjectFilter != .major;

  void nextSubjectFilter() {
    subjectFilter =
        .values[(subjectFilter.index + 1) % SubjectFilter.values.length];
  }

  GradeService(this._imsService);

  void refresh() => _imsService.clearJSessionId();

  Future<WeightedGrade?> getWeightedGrade() async {
    await _imsService.fetchJSessionId();

    final response = await _imsService.dio.post(
      '/student/xscj.jqchjpm_data10421.jsp',
      data: {'jqlx': weightedType.id, 'menucode_current': 'S40309'},
      options: Options(
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      ),
    );

    final String? html = response.data;
    if (html == null) throw Exception('空的响应体');
    if (html.contains('没有检索到记录!')) throw Exception('没有检索到记录!');
    if (html.contains('温馨提示：凭证已失效，请重新登录!')) {
      throw Exception('温馨提示：凭证已失效，请重新登录!');
    }

    final tables = parse(html).getElementsByTagName('table');

    if (tables.length != 1) {
      logInfo(html);
      throw Exception('期望有1个 table，但找到了${tables.length}个 table\n $tables');
    }

    List<List<String>> m = toMatrix(tables.first);
    return WeightedGrade.fromMap(Map.fromIterables(m[0], m[1]));
  }

  List<List<String>> toMatrix(dom.Element table) => table
      .querySelectorAll('tr')
      .map(
        (dom.Element row) => row
            .querySelectorAll('th, td')
            .map((dom.Element cell) => cell.text)
            .toList(),
      )
      .toList();

  final sem2xq = {
    SemesterType.first: '0',
    SemesterType.second: '1',
    SemesterType.next: '2',
  };

  Future<GradeTable?> getGrade() async {
    await Future.delayed(Duration(milliseconds: 1000));
    await _imsService.fetchJSessionId();

    try {
      final response = await _imsService.dio.post(
        '/student/xscj.stuckcj_data10421.jsp',
        data: {
          'sjxz': timeLimit.value, // 时间限制
          'ysyx': showRawGrade ? 'yscj' : 'yxcj', // 原始有效 原始成绩 有效成绩
          'zx': selectedMajor ? 1 : 0, // 主修
          'fx': selectedMinor ? 1 : 0, // 辅修
          if (selectedMajor) 'zxC': 'on', // ？？
          if (selectedMinor) 'fxC': 'on', // ？？
          if (onlyNotPassed) 'xwtg': 1, // 限未通过
          'rxnj': '2025', // TODO 待实现获取功能
          'nj': '2025', // TODO 待实现获取功能
          'btnExport': '%B5%BC%B3%F6',
          if (timeLimit != .sinceEnrollment) 'xn': academicYear.value, // 学年下界
          'xn1': timeLimit == .sinceEnrollment
              ? AcademicYear.now.value
              : academicYear.nextYear.value, // 学年上界
          if (timeLimit == .semester) 'xq': sem2xq[semesterType], // 学期
          'ysyxS': 'on',
          'sjxzS': 'on',
          'xsjd': '1',
          'menucode_current': 'S40303',
        },
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer':
                'https://jwxt.jxufe.edu.cn/student/xscj.stuckcj.jsp?menucode=S40303',
          },
        ),
      );

      final String? html = response.data;
      if (html == null) throw Exception('空的响应体');
      if (html.contains('没有检索到记录!')) throw Exception('没有检索到记录!');
      if (html.contains('温馨提示：凭证已失效，请重新登录!')) {
        throw Exception('温馨提示：凭证已失效，请重新登录!');
      }

      final tables = parse(html).querySelectorAll('table').where((table) {
        final style = table.attributes['style'];
        if (style == null) return true;

        return !style.contains('border:none');
      }).toList();

      if (tables.length != 2) {
        logInfo(html);
        throw Exception('期望有2个 table，但找到了${tables.length}个 table\n $tables');
      }

      // final table = toMatrix(tables.first);
      // for (final title in table.first)
      // {
      //   for (final )
      // }

      // DataTable buildTable(dom.Element table) {
      //   final matrix = toMatrix(table);

      //   return DataTable(
      //     columns: matrix[0]
      //         .map((cell) => DataColumn(label: Text(cell)))
      //         .toList(),
      //     rows: matrix
      //         .sublist(1)
      //         .map(
      //           (line) => DataRow(
      //             cells: line.map((cell) => DataCell(Text(cell))).toList(),
      //           ),
      //         )
      //         .toList(),
      //   );
      // }

      // return Column(
      //   children: [buildTable(tables.first), buildTable(tables[1])],
      // );
    } catch (e) {
      throw Exception('查询成绩异常: $e\n');
    }
  }
}
