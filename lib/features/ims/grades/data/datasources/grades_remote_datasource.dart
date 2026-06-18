import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';

/// 从教务系统获取成绩的远程数据源。
class GradesRemoteDataSource {
  final Dio _dio;

  GradesRemoteDataSource(this._dio);

  /// 获取成绩 HTML。
  Future<String> fetchGradesHtml({
    required String jsessionId,
    required GradesQueryParams params,
  }) async {
    final body = <String, dynamic>{
      'sjxz': params.timeLimit.value,
      'ysyx': params.showRawGrade ? 'yscj' : 'yxcj',
      'zx': params.selectMajor ? 1 : 0,
      'fx': params.selectMinor ? 1 : 0,
      'wz': 0,
      if (params.selectMajor) 'zxC': 'on',
      if (params.selectMinor) 'fxC': 'on',
      if (params.selectWeiZhuan) 'wzC': 'on',
      if (params.onlyNotPassed) 'xwtg': 1,
      'rxnj': params.enrollYear,
      'nj': params.enrollYear,
      'btnExport': '%B5%BC%B3%F6',
      if (params.academicYear != null) 'xn': params.academicYear,
      'xn1':
          params.academicYearNext ??
          params.academicYear ??
          DateTime.now().year.toString(),
      if (params.semesterXq != null) 'xq': params.semesterXq,
      'ysyxS': 'on',
      'sjxzS': 'on',
      'xsjd': '1',
      'menucode_current': 'S40303',
    };

    final queryString = body.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');

    final response = await _dio.post(
      '/student/xscj.stuckcj_data10421.jsp',
      data: queryString,
      options: Options(
        headers: {
          'Cookie': 'JSESSIONID=$jsessionId',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer':
              'https://jwxt.jxufe.edu.cn/student/xscj.stuckcj.jsp?menucode=S40303',
        },
      ),
    );

    final html = response.data as String?;
    if (html == null) throw Exception('空的响应体');
    if (html.contains('没有检索到记录!')) throw Exception('没有检索到记录!');
    if (html.contains('凭证已失效')) throw Exception('凭证已失效，请重新登录!');

    return html;
  }
}
