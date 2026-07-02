import 'dart:convert';

import 'package:dio/dio.dart';

class ScheduleRemoteDataSource {
  final Dio _dio;

  ScheduleRemoteDataSource(this._dio);

  /// 获取学生课表 HTML。
  ///
  /// [jsessionId] 教务系统会话 ID。
  /// [year] 学年，如 "2025" 表示 2025-2026 学年。
  /// [semester] 学期，"1" 或 "2"。
  /// [studentId] 学号。
  Future<String> getScheduleInTableHtml({
    required String jsessionId,
    required String year,
    required String semester,
    required String studentId,
  }) async {
    final rawParams = 'xn=$year&xq=$semester&xh=$studentId';
    final encodedParams = base64.encode(utf8.encode(rawParams));

    final response = await _dio.get(
      '/wsxk/xkjg.ckdgxsxdkchj_data10319.jsp',
      queryParameters: {'params': encodedParams},
      options: Options(
        headers: {
          'Cookie': 'JSESSIONID=$jsessionId',
          'Referer':
              'https://jwxt.jxufe.edu.cn/student/xkjg.wdkb.jsp?menucode=S20301',
        },
      ),
    );

    final html = response.data as String?;
    if (html == null) throw Exception('空的响应体');
    if (html.contains('凭证已失效')) throw Exception('凭证已失效，请重新登录！');

    return html;
  }
}
