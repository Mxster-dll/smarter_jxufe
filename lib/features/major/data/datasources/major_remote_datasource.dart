import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/major/data/datasources/api_models/api_major.dart';

class MajorRemoteDataSource {
  final Dio _dio;

  MajorRemoteDataSource(this._dio);

  Future<List<ApiMajor>> getMajorList(int year, String collegeId) async {
    final response = await _dio.post(
      '/frame/droplist/getDropLists.action',
      data: {
        'comboBoxName': 'MsYXB_Specialty',
        'paramValue': 'nj=$year&dwh=$collegeId',
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

    final List<dynamic> rawList = response.data;
    return ApiMajor.fromJsonList(rawList);
  }
}
