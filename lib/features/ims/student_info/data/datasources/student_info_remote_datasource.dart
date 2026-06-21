import 'package:dio/dio.dart';

class StudentInfoRemoteDataSource {
  final Dio _dio;

  StudentInfoRemoteDataSource(this._dio);

  Future<String> fetchStudentInfoXml({required String jsessionId}) async {
    final response = await _dio.post(
      '/STU_BaseInfoAction.do',
      queryParameters: {'hidOption': 'InitData', 'menucode_current': 'S10101'},
      options: Options(
        headers: {
          'Cookie': 'JSESSIONID=$jsessionId',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer':
              'https://jwxt.jxufe.edu.cn/student/stu.xsxj.xjda.jbxx.html?menucode=S10101',
        },
      ),
    );

    return response.data as String;
  }
}
