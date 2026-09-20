import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/network/jw_page_decoding.dart';
import 'package:smarter_jxufe/features/ims/data/ims_exception.dart';

/// 从教务系统获取毕业学分要求的远程数据源。
class GraduationRequirementsRemoteDataSource {
  final Dio _dio;

  GraduationRequirementsRemoteDataSource(this._dio);

  /// 获取毕业学分要求 HTML。
  Future<String> fetchGraduationRequirementsHtml({
    required String jsessionId,
  }) async {
    const body = 'sysf=&menucode_current=S20103';

    final response = await _dio.post(
      '/taglib/DataTable.jsp?tableId=6033',
      data: body,
      options: Options(
        headers: {
          'Cookie': 'JSESSIONID=$jsessionId',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer':
              'https://jwxt.jxufe.edu.cn/student/pyfa.byxfyq.html?menucode=S20103&bqflag=1',
        },
      ),
    );

    final html = response.data as String?;
    if (html == null) throw ImsApiException('空的响应体');
    if (jwSessionExpired(html)) {
      throw const JwSessionExpiredException('凭证已失效，请重新登录!');
    }

    return html;
  }
}
