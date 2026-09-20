/// 学习通 · 通知（收件箱）数据源 —— **JSON，最省的一条**。
///
/// 一次取数只要 2 个请求（token 在场时只要 1 个：token 是登录链最后一跳顺手抠的）。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/network/trace_text.dart';
import 'package:smarter_jxufe/features/chaoxing/data/anti_corruption/chaoxing_notice_parser.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_endpoints.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_http_client.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_session.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_notice.dart';

/// 通知远端数据源。
class ChaoxingNoticeRemoteDataSource {
  ChaoxingNoticeRemoteDataSource(this._http);

  final ChaoxingHttpClient _http;

  /// 收件箱更新提示（`msg` 为布尔 = 有没有新通知）。
  ///
  /// ⚠ 它不是「未读条数」：实测本账号有 20 条通知时也是 `false`。
  /// 拿不到就返回 false（宁少报不多报）。
  Future<bool> hasNew(ChaoxingSession session) async {
    final response = await _http.get(
      'https://${ChaoxingEndpoints.spaceHost}${ChaoxingEndpoints.noticeCountPath}',
      jar: session.jar,
      referer: ChaoxingEndpoints.spaceBase,
      headers: const {'X-Requested-With': 'XMLHttpRequest'},
      followRedirects: true,
      throttle: true,
    );
    final body = _body(response);
    ChaoxingHttpClient.ensureUsable(response, body);
    try {
      return chaoxingNoticeHasNew(jsonDecode(body));
    } catch (_) {
      return false;
    }
  }

  /// 通知列表（实测一次给最近 20 条，最新在前）。
  ///
  /// ⚠ **翻页未破解**：加 `lastGetId` / `lastPage` / `page` / `pageNum` 都返回同一页
  /// （见 `reverse_engineering/学习通接口.md` §2.2），所以这里只取第一页。
  Future<List<ChaoxingNotice>> list(ChaoxingSession session) async {
    final token = (session.noticeToken ?? '').trim();
    if (token.isEmpty) {
      throw ChaoxingSessionException('学习通通知暂不可用：本次会话没取到收件箱 token');
    }
    final inbox =
        'https://${ChaoxingEndpoints.noticeHost}${ChaoxingEndpoints.noticeInboxPath}?s=$token';
    final response = await _http.get(
      'https://${ChaoxingEndpoints.noticeHost}${ChaoxingEndpoints.noticeListPath}',
      jar: session.jar,
      query: {'s': token},
      referer: inbox,
      headers: const {'X-Requested-With': 'XMLHttpRequest'},
      followRedirects: true,
      throttle: true,
    );
    final body = _body(response);
    ChaoxingHttpClient.ensureUsable(response, body);

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw ChaoxingSessionException(
        '学习通通知解析失败：服务端返回的不是 JSON（${clipForTrace(body, 120)}）',
      );
    }
    return parseChaoxingNotices(decoded);
  }

  static String _body(Response<dynamic> response) =>
      response.data?.toString() ?? '';

}
