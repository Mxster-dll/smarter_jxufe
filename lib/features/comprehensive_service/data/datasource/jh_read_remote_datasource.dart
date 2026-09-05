import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/jh_read_record.dart';

/// 蛟湖阅读详单远程数据源（SSP 学工平台）。
///
/// 数据页：/admin/tzz/puVolunteer/read_list.html（服务端渲染表格）。
/// 页面按当前登录学生姓名过滤后返回该生的一条（或多条）考核记录。
/// 表格列（tbody tr 的 td 顺序）：
///   0 复选框 | 1 序号 | 2 学号 | 3 姓名 | 4 学院 | 5 班级 |
///   6 加分项名称 | 7 是否完成入馆学习 | 8 借阅数量是否合格 |
///   9 学分 | 10 操作（查看 read_detail.html?id=）
class JhReadRemoteDataSource {
  final Dio _dio;

  JhReadRemoteDataSource(this._dio);

  /// 获取指定学生的蛟湖阅读考核记录。
  ///
  /// [sessionId] 为综合管理平台（SSP）JSESSIONID；
  /// [studentName] 用于按姓名过滤（服务端不支持按当前用户自动过滤）。
  /// 会话失效抛 [SspSessionExpiredException]，由上层刷新会话后重试。
  Future<List<JhReadRecord>> fetchReadRecords({
    required String sessionId,
    required String studentName,
  }) async {
    final response = await _dio.get(
      '/admin/tzz/puVolunteer/read_list.html',
      queryParameters: {
        'pageInit': 'yes',
        'pageNumber': '1',
        'pageSize': '20',
        'search_like_studentInfo.name': studentName,
      },
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
  bool _looksLikeLoginRedirect(String body) {
    final trimmed = body.trimLeft();
    if (!trimmed.startsWith('<!DOCTYPE html') && !trimmed.startsWith('<html')) {
      return false;
    }
    return trimmed.contains('authFailure') ||
        trimmed.contains('/sso/login') ||
        RegExp(r'<title>\s*登录').hasMatch(trimmed);
  }

  List<JhReadRecord> _parseHtml(String html) {
    final document = html_parser.parse(html);
    final table = document.querySelector('#listTable');
    if (table == null) return [];

    final tbody = table.querySelector('tbody');
    if (tbody == null) return [];

    final rows = tbody.querySelectorAll('tr');
    final List<JhReadRecord> records = [];

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      // 需要 >= 11 列：checkbox + 10 个数据列
      if (cells.length < 11) continue;

      try {
        // 详情 id：操作列 onclick="showDetail(<id>)"，与复选框 value 一致。
        String detailId = '';
        final opHtml = cells[10].outerHtml;
        final showMatch = RegExp(r"showDetail\((\d+)\)").firstMatch(opHtml);
        if (showMatch != null) {
          detailId = showMatch.group(1) ?? '';
        } else {
          final cb = cells[0].querySelector('input[type="checkbox"]');
          if (cb != null) {
            final v = cb.attributes['value'] ?? '';
            if (v.isNotEmpty && RegExp(r'^\d+$').hasMatch(v)) detailId = v;
          }
        }

        records.add(
          JhReadRecord(
            index: cells[1].text.trim(),
            studentId: cells[2].text.trim(),
            name: cells[3].text.trim(),
            college: cells[4].text.trim(),
            className: cells[5].text.trim(),
            bonusName: cells[6].text.trim(),
            entryLearning: cells[7].text.trim(),
            borrowQualified: cells[8].text.trim(),
            credit: cells[9].text.trim(),
            detailId: detailId,
          ),
        );
      } catch (_) {
        // 跳过解析失败的行
      }
    }

    return records;
  }
}
