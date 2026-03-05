import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:get_storage/get_storage.dart';
import 'package:html/parser.dart';

import 'package:smarter_jxufe/ims/Course.dart';
import 'package:smarter_jxufe/ims/AcademicTime.dart';
import 'package:smarter_jxufe/ims/ImsService.dart';
import 'package:smarter_jxufe/utils/Data.dart';
import 'package:smarter_jxufe/utils/Log.dart';

class CurriculumService {
  final box = GetStorage();
  late final ImsService _imsService;

  CurriculumService([ImsService? imsService]) {
    _imsService = imsService ?? ImsService();
  }

  Future<List> getCollegeList() async {
    await _imsService.fetchJSessionId();

    try {
      final response = await _imsService.dio.post(
        '/frame/droplist/getDropLists.action',
        data: {
          'comboBoxName': 'MsYXB',
          'paramValue': '',
          'isYXB': 0,
          'isCDDW': 0,
          'isXQ': 0,
          'isDJKSLB': 0,
          'isZY': 0,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Referer':
                'https://jwxt.jxufe.edu.cn/student/pyfa.llkc.html?menucode=S20101',
          },
        ),
      );

      return response.data;
    } catch (e) {
      return ['getCollegeList() Error: $e'];
    }
  }

  /// 最早 2010 年还有记录，2009 之前无记录
  Future<List> getMajorList(int year, String dwh) async {
    await _imsService.fetchJSessionId();

    try {
      final response = await _imsService.dio.post(
        '/frame/droplist/getDropLists.action',
        data: {
          'comboBoxName': 'MsYXB_Specialty',
          'paramValue': 'nj=$year&dwh=$dwh',
          'isYXB': 0,
          'isCDDW': 0,
          'isSXJD': 0,
          'isXQ': 0,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'Referer':
                'https://jwxt.jxufe.edu.cn/student/pyfa.llkc.html?menucode=S20101',
          },
        ),
      );

      return response.data;
    } catch (e) {
      return ['getMajorList() Error: $e'];
    }
  }

  // TODO 进一步打开每个课程的信息页，获取更多信息
  Future<List<Course>> getCurriculum(
    int year,
    String selYxb,
    String selZy,
  ) async {
    await _imsService.fetchJSessionId();

    final Response<dynamic> response;
    try {
      response = await _imsService.dio.post(
        '/taglib/DataTable.jsp?tableId=2508',
        data: {
          // 'nj': year,
          // 'fxnj': '',
          // 'menucode': 'S20101',
          // 'yxdm': '44',
          // 'zydm': '4405',
          // 'zyfxdm': '',
          // 'fxzydm': '',
          'count': '1',
          'initQry': '0',
          'nj_': year,
          'sel_yxb': selYxb,
          'sel_zy': selZy,
          // 'sel_zyfx': '',
          'fzyxs': 'zx',
          'menucode_current': 'S20101',
        },
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer':
                'https://jwxt.jxufe.edu.cn/student/pyfa.llkc.html?menucode=S20101',
          },
        ),
      );
    } catch (e) {
      throw Exception('getCurriculum()Error: $e');
    }

    final html = response.data;
    final tables = parse(html).querySelectorAll('table');

    if (tables.length != 1) {
      logInfo(html);
      throw Exception('期望有1个 table，但找到了${tables.length}个 table\n $tables');
    }

    final matrix = tables.first.toMatrix;
    Map<String, int> idx = {};

    final thead = matrix.first;
    for (int i = 0; i < thead.length; i++) {
      idx[thead[i]] = i;
    }

    Course lineToCourse(List<String> line) {
      if (line[idx['课程地位']!].trim().isNotEmpty &&
          line[idx['课程地位']!] != '主干课程') {
        throw FormatException('未知的课程地位的值: "${line[idx['课程地位']!]}"');
      }

      CourseBuilder builder = CourseBuilder();

      builder.codeAndName = line[idx['课程']!];

      builder.credit = double.parse(line[idx['学分']!]);
      builder.creditHour = CreditHour(
        int.parse(line[idx['总学时']!]),
        int.parse(line[idx['讲授学时']!]),
        int.parse(line[idx['实验学时']!]),
        int.parse(line[idx['实践学时']!]),
        int.parse(line[idx['其它学时']!]),
        double.parse(line[idx['周学时']!]),
      );

      builder.categories = line[idx['课程类别']!];
      builder.nature = CourseNature.theory;
      builder.importance = (line[idx['课程地位']!] == '主干课程') ? .core : .general;
      builder.assessmentMethod = AssessmentMethod.parse(line[idx['考核方式']!]);
      builder.identification = line[idx['标识']!];

      return builder.build();
    }

    return matrix.skip(1).map(lineToCourse).toList();
  }
}
