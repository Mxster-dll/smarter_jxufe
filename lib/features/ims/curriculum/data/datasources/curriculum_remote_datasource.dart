import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/major_mapper.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_key.dart';

class CurriculumRemoteDataSource {
  final Dio _dio;

  CurriculumRemoteDataSource({
    required Dio dio,
    required MajorMapper majorMapper,
  }) : _dio = dio;

  Future<String> getCurriculumHtml(
    int year,
    String collegeId,
    String majorId,
  ) async {
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
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer':
              'https://jwxt.jxufe.edu.cn/student/pyfa.llkc.html?menucode=S20101',
        },
      ),
    );

    return response.data as String;
  }

  Future<String> getCurriculumHtmlByKey(CurriculumKey key) =>
      getCurriculumHtml(key.year, key.collegeId, key.majorId);
}
