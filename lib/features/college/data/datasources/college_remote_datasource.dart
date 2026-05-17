import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/college/data/datasources/api_models/api_college.dart';

class CollegeRemoteDataSource {
  final Dio _dio;

  CollegeRemoteDataSource(this._dio);

  Future<List<ApiCollege>> getAllCollege() async {
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

    final rawList = response.data as List<dynamic>;
    return ApiCollege.fromJsonList(rawList);
  }
}
