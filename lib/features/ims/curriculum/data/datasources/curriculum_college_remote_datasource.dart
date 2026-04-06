import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/api_models/api_college.dart';

class CurriculumCollegeRemoteDataSource {
  final Dio _dio;

  CurriculumCollegeRemoteDataSource(this._dio);

  Future<List<ApiCollege>> getCollegeList() async {
    final response = await _dio.post(
      '/frame/droplist/getDropLists.action',
      data: {
        'comboBoxName': 'MsYXB',
        'paramValue': '',
        'isYXB': 0, // 院系部
        'isCDDW': 0,
        'isXQ': 0, // 学期？
        'isDJKSLB': 0,
        'isZY': 0, // 专业？
      },
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Referer':
              'https://jwxt.jxufe.edu.cn/student/pyfa.llkc.html?menucode=S20101',
        },
      ),
    );

    final List<dynamic> rawList = response.data;
    return rawList
        .map((e) => ApiCollege.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
