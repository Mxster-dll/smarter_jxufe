/// 学习通 · 签到数据源（清单 1 请求 / 课；我的状态 1 请求 / 活动）。
///
/// ⚠ 成本口径（2026-10-09 实测）：
/// - **清单**：`POST /widget/pcpick/stu/activeList` —— **1 个请求拿到一门课的
///   全部签到**（进行中 + 已结束），和课程清单同量级；
/// - **我的状态**：只能逐活动打详情页（**1 请求 / 活动**），一门课一学期可能十几次
///   → **绝不在扫描里批量拉**，只按需（用户点开某条、或手动「全量更新」时）取。
///   请求预算见 `chaoxing_limits.dart`（实测 ≈60 个/窗口就撞验证码页）。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/chaoxing/data/anti_corruption/chaoxing_sign_parser.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_endpoints.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_http_client.dart';
import 'package:smarter_jxufe/features/chaoxing/data/chaoxing_session.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_course.dart';
import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_sign.dart';

/// 签到远端数据源。
class ChaoxingSignRemoteDataSource {
  ChaoxingSignRemoteDataSource(this._http);

  final ChaoxingHttpClient _http;

  /// 这门课的签到活动清单（进行中 + 已结束）。
  ///
  /// **空列表是合法结果**（这门课确实没签到）；区别于失败：
  /// - 非 JSON / `result != 1` / 正文是验证码页 → 抛异常（见 [ChaoxingHttpClient.ensureUsable]）；
  /// - 因此调用方**不能**把空列表当成「没取到」。
  Future<List<ChaoxingSign>> signsOf(
    ChaoxingSession session,
    ChaoxingCourse course,
  ) async {
    final response = await _http.post(
      'https://${ChaoxingEndpoints.signHost}${ChaoxingEndpoints.signListPath}',
      jar: session.jar,
      form: {
        'courseId': course.courseId,
        'classId': course.classId,
        // 实测：不带 puid 也返回同样数据；带上更贴近站方调用（值取罐里的 `_uid`，
        // **不需要**额外请求去页面上抠）。
        if (uidOf(session).isNotEmpty) 'puid': uidOf(session),
      },
      referer: signPageReferer(course),
      throttle: true,
    );
    final body = _body(response);
    ChaoxingHttpClient.ensureUsable(response, body);
    final decoded = _decode(body);
    if (!chaoxingSignListOk(decoded)) {
      throw ChaoxingPageException(
        '课程 ${course.key} 的签到清单返回了非预期内容'
        '（${response.statusCode} · ${body.length} B）——多半是取到了验证页',
      );
    }
    return parseChaoxingSigns(
      decoded,
      courseId: course.courseId,
      courseName: course.name,
    );
  }

  /// 单个活动的详情（**我的状态 + 签到时刻**）。
  ///
  /// 认不出状态时返回 `statusLoaded == false` 的那条（界面说「状态未知」），
  /// 不抛 —— 「查了但没认出来」不该让整页报错。
  Future<ChaoxingSign> detailOf(
    ChaoxingSession session,
    ChaoxingSign sign,
  ) async {
    final response = await _http.get(
      'https://${ChaoxingEndpoints.signHost}${ChaoxingEndpoints.signDetailPath}',
      jar: session.jar,
      query: {
        'activeId': sign.activeId,
        'classId': sign.classId,
        'courseId': sign.courseId,
      },
      referer: 'https://${ChaoxingEndpoints.signHost}'
          '${ChaoxingEndpoints.signPagePath}',
      followRedirects: true,
      throttle: true,
    );
    final body = _body(response);
    ChaoxingHttpClient.ensureUsable(response, body);
    if (body.trim().isEmpty) {
      throw ChaoxingPageException(
        '签到详情 ${sign.activeId} 返回空页（${response.statusCode}）',
      );
    }
    return chaoxingSignDetailFromPage(body, base: sign);
  }

  /// 活动首页 Referer（清单请求的 `Referer`，也是人工核对时的入口地址）。
  static String signPageReferer(ChaoxingCourse course) =>
      'https://${ChaoxingEndpoints.signHost}${ChaoxingEndpoints.signPagePath}'
      '?courseId=${course.courseId}&jclassId=${course.classId}';

  /// 罐里的 `_uid`（学生 uid）—— 清单接口的 `puid` 就是它（实测两者逐字相同）。
  static String uidOf(ChaoxingSession session) {
    final header = session.jar.headerFor(ChaoxingEndpoints.signHost);
    for (final name in const ['_uid', 'UID', 'uid']) {
      final m = RegExp('(?:^|; )${RegExp.escape(name)}=([^;]+)').firstMatch(header);
      final value = m?.group(1)?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _body(Response<dynamic> response) =>
      response.data?.toString() ?? '';

  /// 正文 → JSON（不是 JSON 就给 null，由调用方判「非预期内容」）。
  static Object? _decode(String body) {
    final t = body.trimLeft();
    if (!t.startsWith('{') && !t.startsWith('[')) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}
