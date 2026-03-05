import 'package:dio/dio.dart';
import 'package:html/parser.dart';
import 'package:smarter_jxufe/utils/Data.dart';

import 'package:smarter_jxufe/utils/Log.dart';
import 'package:smarter_jxufe/ims/Course.dart';
import 'package:smarter_jxufe/ims/AcademicTime.dart';
import 'package:smarter_jxufe/ims/Grades.dart';
import 'package:smarter_jxufe/ims/imsService.dart';

class GradeService {
  late final ImsService _imsService;

  WeightedType weightedType = .courseAll;
  TimeLimit timeLimit = .semester;
  AcademicYear academicYear = .now;
  SemesterType semesterType = .first;
  CourseFilter courseFilter = .all;
  bool showRawGrade = false;
  bool onlyNotPassed = false;

  bool get selectedMajor => courseFilter != .minor;
  bool get selectedMinor => courseFilter != .major;

  void nextCourseFilter() {
    courseFilter =
        .values[(courseFilter.index + 1) % CourseFilter.values.length];
  }

  GradeService([ImsService? imsService]) {
    _imsService = imsService ?? ImsService();
  }

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

    List<List<String>> m = tables.first.toMatrix;
    return WeightedGrade.fromMap(Map.fromIterables(m[0], m[1]));
  }

  final sem2xq = {
    SemesterType.first: '0',
    SemesterType.second: '1',
    SemesterType.short: '2',
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

      final table = tables.first.toMatrix;

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
