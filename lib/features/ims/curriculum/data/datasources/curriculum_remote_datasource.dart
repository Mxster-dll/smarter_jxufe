import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_key.dart';

class CurriculumRemoteDataSource {
  final Dio _dio;

  CurriculumRemoteDataSource(this._dio);

  Future<String> getCurriculumHtml(
    int year,
    String collegeId,
    String majorId, {
    required String jsessionId,
  }) async {
    final response = await _dio.post(
      '/taglib/DataTable.jsp?tableId=2508',
      data: {
        'count': '1',
        'initQry': '0',
        'nj_': year,
        'sel_yxb': collegeId,
        'sel_zy': majorId,
        'fzyxs': 'zx',
        'menucode_current': 'S20101',
      },
      options: Options(
        headers: {
          'Cookie': 'JSESSIONID=$jsessionId',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer':
              'https://jwxt.jxufe.edu.cn/student/pyfa.llkc.html?menucode=S20101',
        },
      ),
    );

    return response.data as String;
  }

  Future<String> getCurriculumHtmlByKey(
    CurriculumKey key, {
    required String jsessionId,
  }) => getCurriculumHtml(
    key.year,
    key.college.code,
    key.major.code,
    jsessionId: jsessionId,
  );
}
