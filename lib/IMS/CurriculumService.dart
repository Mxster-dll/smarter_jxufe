import 'package:dio/dio.dart';
import 'package:get_storage/get_storage.dart';
import 'package:html/parser.dart';
import 'package:smarter_jxufe/ims/AcademicUnit.dart';

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

  Future<List<College>> getCollegeList() async {
    await _imsService.fetchJSessionId();

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

    final List colleges = response.data;
    return colleges.map((e) => College(e['code'], e['name'])).toList();
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
      String info(String key) => line[idx[key]!].trim();

      CourseBuilder builder = CourseBuilder();

      builder.codeAndName = info('课程');
      builder.credit = double.parse(info('学分'));
      builder.creditHour = CreditHour(
        int.parse(info('总学时')),
        int.parse(info('讲授学时')),
        int.parse(info('实验学时')),
        int.parse(info('实践学时')),
        int.parse(info('其它学时')),
        double.parse(info('周学时')),
      );

      builder.categories = info('课程类别');
      builder.nature = CourseNature.theory;
      builder.importance = (info('课程地位') == '主干课程') ? .core : .general;
      builder.assessmentMethod = AssessmentMethod.parse(info('考核方式'));
      builder.identification = info('标识');

      return builder.build();
    }

    return matrix.skip(1).map(lineToCourse).toList();
  }
}
