import 'dart:math';

import 'package:dio/dio.dart';

/// 教务系统校历公开页远程数据源（免登录）。
///
/// 服务端按会话发放数据：`SchoolCalendar.show.jsp` 必须复用
/// `SchoolCalendar.jsp` 建立起的 JSESSIONID，否则返回空页。
/// 因此这里手动缓存首个响应的会话 cookie，并在查询请求中带回。
class SchoolCalendarRemoteDataSource {
  final Dio _dio;

  /// 首个请求（GET 校历首页）种下的会话 cookie，原样复用。
  String? _sessionCookie;

  SchoolCalendarRemoteDataSource(this._dio);

  /// 拉取指定学年（[xn] = 起始年）与学段（[xq] ∈ {0 第一学期, 1 第二学期,
  /// 2 第二阶段}）的校历 HTML 源码（已按 GBK 解码为字符串）。
  Future<String> fetchCalendarHtml({
    required int xn,
    required int xq,
  }) async {
    await _ensureSession();

    final random = '${Random().nextDouble()}';
    final form = <String, String>{
      'menucode': '',
      'xn': '$xn',
      'xq_m': '$xq',
      'rad': '1',
      'sel_xn_xq': '$xn-$xq',
    };
    final body = form.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    final response = await _dio.post<String>(
      '/public/SchoolCalendar.show.jsp',
      queryParameters: {'random': random},
      data: body,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: _sessionCookie == null ? null : {'Cookie': _sessionCookie},
      ),
    );

    final html = response.data;
    if (html == null || html.isEmpty) {
      throw Exception('校历查询无响应数据');
    }
    // 会话失效时服务端会返回「凭证已失效」提示脚本。
    if (html.contains('凭证已失效')) {
      _sessionCookie = null;
      throw Exception('校历会话已失效，请下拉刷新重试');
    }
    return html;
  }

  /// 复用或重建匿名会话。
  Future<void> _ensureSession() async {
    if (_sessionCookie != null) return;
    final response = await _dio.get<String>('/public/SchoolCalendar.jsp');
    final cookies = <String>[];
    for (final entry in response.headers.map.entries) {
      if (entry.key.toLowerCase() == 'set-cookie') {
        cookies.addAll(entry.value);
      }
    }
    final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(cookies.join(';'));
    if (match != null) {
      _sessionCookie = 'JSESSIONID=${match.group(1)}';
    } else {
      // 服务端不种会话 cookie 时，查询页拿不到同一会话会返回空模板。
      throw Exception('校历服务未返回会话标识，请稍后重试');
    }
  }
}
