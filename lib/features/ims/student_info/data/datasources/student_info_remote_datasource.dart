import 'package:dio/dio.dart';

/// 从教务系统 STU_BaseInfoAction.do 获取学生基本信息的远程数据源。
///
/// 响应为 GBK 编码的 XML（imsDio 已内置 GBK 解码），
/// 解析工作由 [StudentInfoXmlParser] 负责。
class StudentInfoRemoteDataSource {
  final Dio _dio;

  StudentInfoRemoteDataSource(this._dio);

  /// 获取学生基本信息 XML 原始字符串。
  ///
  /// [jsessionId] 由 [ImsAuthRepository] 提供。
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
