import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/network/jw_page_decoding.dart';
import 'package:smarter_jxufe/features/ims/data/ims_exception.dart';

/// 加权成绩排名远程数据源。
class WeightedGradeRemoteDataSource {
  final Dio _dio;

  WeightedGradeRemoteDataSource(this._dio);

  /// [jsessionId] 教务系统会话 ID。
  /// [typeId] 加权类型：1=课程加权所有学年, 2=上学年, 3=上学期, 4=分流加权, 5=毕业加权, 6=辅修加权, 7=推免加权。
  Future<String> fetchWeightedGradeHtml({
    required String jsessionId,
    required int typeId,
  }) async {
    final response = await _dio.post(
      '/student/xscj.jqchjpm_data10421.jsp',
      data: 'jqlx=$typeId&menucode_current=S40309',
      options: Options(
        headers: {
          'Cookie': 'JSESSIONID=$jsessionId',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer':
              'https://jwxt.jxufe.edu.cn/student/xscj.jqchjpm10421.html?menucode=S40309&bqflag=1',
        },
      ),
    );

    final html = response.data as String?;
    if (html == null) throw ImsApiException('空的响应体');
    if (jwSessionExpired(html)) {
      throw const JwSessionExpiredException('凭证已失效，请重新登录！');
    }

    return html;
  }
}
