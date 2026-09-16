import 'dart:math';

import 'package:dio/dio.dart';

/// 教务作息时间表公开页远程数据源（免登录）。
///
/// 与 `SchoolCalendarRemoteDataSource` 同构：`SchoolTimetable.show.jsp`
/// 必须复用 `SchoolTimetable.jsp` 建立起的 JSESSIONID，否则返回空页。
/// 两者都在 `/public/` 下，共用同一份免认证 Dio（见 `period_table_providers.dart`）。
class PeriodTableRemoteDataSource {
  final Dio _dio;

  /// 首个请求（GET 作息时间首页）种下的会话 cookie，原样复用。
  String? _sessionCookie;

  PeriodTableRemoteDataSource(this._dio);

  /// 拉取指定学年（[xn] = 起始年）与学段（[xq] ∈ {0 第一学期, 1 第二学期,
  /// 2 第二阶段}）的作息时间表 HTML（已按 GBK 解码为字符串）。
  ///
  /// 未来学期尚无数据时服务端返回空表（实测 2026-1 为 0 行），
  /// 此时返回的 HTML 可正常解析但无节次，由仓库层回退。
  Future<String> fetchTimetableHtml({required int xn, required int xq}) async {
    await _ensureSession();

    final random = '${Random().nextDouble()}';
    final form = <String, String>{
      'menucode': '',
      'xn': '$xn',
      'xq_m': '$xq',
      'is_ssxq': '0',
      'sel_xn_xq': '$xn-$xq',
    };
    final body = form.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    final response = await _dio.post<String>(
      '/public/SchoolTimetable.show.jsp',
      queryParameters: {'random': random},
      data: body,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: _sessionCookie == null ? null : {'Cookie': _sessionCookie},
      ),
    );

    final html = response.data;
    if (html == null || html.isEmpty) {
      throw Exception('作息时间查询无响应数据');
    }
    if (html.contains('凭证已失效')) {
      _sessionCookie = null;
      throw Exception('作息时间会话已失效，请重试');
    }
    return html;
  }

  /// 复用或重建匿名会话。
  Future<void> _ensureSession() async {
    if (_sessionCookie != null) return;
    final response = await _dio.get<String>('/public/SchoolTimetable.jsp');
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
      throw Exception('作息时间服务未返回会话标识，请稍后重试');
    }
  }
}
