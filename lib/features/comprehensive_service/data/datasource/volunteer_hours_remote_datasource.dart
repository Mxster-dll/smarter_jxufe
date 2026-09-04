import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';

class VolunteerHoursRemoteDataSource {
  final Dio _dio;

  VolunteerHoursRemoteDataSource(this._dio);

  /// 获取志愿服务时长列表。
  ///
  /// [sessionId] 为当前账户在综合管理平台（SSP）的 JSESSIONID。
  /// 会话失效时服务端会返回 302（跳转到登录页/authFailure）或
  /// 200 登录页 HTML，此时抛 [SspSessionExpiredException]，
  /// 由上层触发会话刷新后重试。
  Future<List<VolunteerActivity>> fetchVolunteerActivities({
    required String sessionId,
  }) async {
    final response = await _dio.get(
      '/admin/tzz/StuVolWork/stu_list.html',
      options: Options(
        headers: {
          'Cookie': 'JSESSIONID=$sessionId',
          'Referer': 'http://ssp.jxufe.edu.cn/admin/common/main.html',
        },
        followRedirects: false,
      ),
    );

    final status = response.statusCode ?? 0;

    // 3xx（登录页/失效页重定向）→ 会话已过期
    if (status >= 300 && status < 400) {
      throw SspSessionExpiredException();
    }

    if (status != 200) {
      throw Exception('请求失败: $status');
    }

    final body = response.data?.toString() ?? '';
    if (_looksLikeLoginRedirect(body)) {
      throw SspSessionExpiredException();
    }

    return _parseHtml(body);
  }

  /// 判断响应体是否为登录页/失效页（authFailure 或 SSO 登录入口）。
  /// 仅当页面以 HTML 开头时才检测，避免误判业务数据。
  bool _looksLikeLoginRedirect(String body) {
    final trimmed = body.trimLeft();
    if (!trimmed.startsWith('<!DOCTYPE html') && !trimmed.startsWith('<html')) {
      return false;
    }
    return trimmed.contains('authFailure') ||
        trimmed.contains('/sso/login') ||
        RegExp(r'<title>\s*登录').hasMatch(trimmed);
  }

  List<VolunteerActivity> _parseHtml(String html) {
    final document = html_parser.parse(html);
    final table = document.querySelector('#listTable');
    if (table == null) return [];

    final tbody = table.querySelector('tbody');
    if (tbody == null) return [];

    final rows = tbody.querySelectorAll('tr');
    final List<VolunteerActivity> activities = [];

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 10) continue;

      try {
        final indexText = cells[0].text.trim();
        final index = int.tryParse(indexText) ?? 0;

        final activityName = cells[1].text.trim();
        final initiator = cells[2].text.trim();
        final responsiblePerson = cells[3].text.trim();
        final department = cells[4].text.trim();
        final activityCategory = cells[5].text.trim();
        final recognizedHours = cells[6].text.trim();
        final applicationStatus = cells[7].text.trim();
        final recognitionStatus = cells[8].text.trim();

        // 从操作列中提取 detail id 和 type
        String detailId = '';
        String detailType = '';
        final detailLink = cells[9].querySelector('a[href]');
        if (detailLink != null) {
          final href = detailLink.attributes['href'] ?? '';
          final idMatch = RegExp(
            "detail\\((\\d+),\\s*['\"]?(\\d+)['\"]?\\)",
          ).firstMatch(href);
          if (idMatch != null) {
            detailId = idMatch.group(1) ?? '';
            detailType = idMatch.group(2) ?? '';
          }
        }

        activities.add(
          VolunteerActivity(
            index: index,
            activityName: activityName,
            initiator: initiator,
            responsiblePerson: responsiblePerson,
            department: department,
            activityCategory: activityCategory,
            recognizedHours: recognizedHours,
            applicationStatus: applicationStatus,
            recognitionStatus: recognitionStatus,
            detailId: detailId,
            detailType: detailType,
          ),
        );
      } catch (_) {
        // 跳过解析失败的行
      }
    }

    return activities;
  }
}
