import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/library_edu/data/anti_corruption/tsgxs_exam_parser.dart';
import 'package:smarter_jxufe/features/library_edu/data/anti_corruption/tsgxs_html_parser.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_models.dart';

/// 入馆教育业务接口异常(非会话问题)。
class TsgxsApiException implements Exception {
  final String message;
  const TsgxsApiException(this.message);

  @override
  String toString() => message;
}

/// 服务端明确**未授权**的业务响应(302 → `/html/401.html`)。
///
/// 与会话失效无关,不要触发重建会话:实测该账号(未开始学习)对
/// `GET /Web/Exam?cid=<章节>` 一律 302 到 `/html/401.html`
/// (本章线索未看完 / 前序章节未通过,答题尚未开放),
/// 章节地图同样如此(第 2~5 章需先通过上一章考试)。
class TsgxsAccessDeniedException implements Exception {
  final String message;
  const TsgxsAccessDeniedException(this.message);

  @override
  String toString() => message;
}

/// 章节考试状态。
enum TsgxsExamState {
  /// 已通过本章考试。
  passed,

  /// 可以开始考试(页面未通过态)。
  ready,

  /// 尚不可考(线索未看完等)。
  blocked,
}

/// 章节考试状态与提示。
class TsgxsExamStatus {
  final TsgxsExamState state;
  final String message;

  /// 通过后页面给出的下一章 id。
  final String? nextChapterId;

  const TsgxsExamStatus({
    required this.state,
    required this.message,
    this.nextChapterId,
  });
}

/// 入馆教育(tsgxs.jxufe.cn)业务数据源:全部页面服务端渲染,取回 HTML 后解析。
class TsgxsApiRemoteDataSource {
  final Dio _dio;

  TsgxsApiRemoteDataSource(this._dio);

  /// 请求诊断落盘(`%TEMP%\tsgxs_api_trace.log`):只记 方法/URL/状态码/
  /// Location/Cookie **名**,不含任何 Cookie 值或账号信息。
  static String get apiTracePath =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'tsgxs_api_trace.log';

  static Future<void> _apiTrace(String line) async {
    try {
      await File(apiTracePath).writeAsString(
        '${DateTime.now().toIso8601String()} $line\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // 诊断写盘失败可忽略。
    }
  }

  /// 记录一次请求(URL/状态码/Location/Referer/Cookie 名)。
  static void _trace(
    String method,
    String path,
    int status,
    Response<dynamic> resp,
    String? referer,
  ) {
    final location = resp.headers.value('location') ?? '';
    final cookieNames = (resp.requestOptions.headers['Cookie'] as String? ?? '')
        .split(';')
        .map((c) => c.split('=').first.trim())
        .where((c) => c.isNotEmpty)
        .join(',');
    unawaited(
      _apiTrace(
        '$method ${resp.requestOptions.uri} -> $status'
        '${location.isNotEmpty ? ' Location=$location' : ''}'
        '${referer != null ? ' referer=$referer' : ''}'
        ' cookie=[$cookieNames]',
      ),
    );
  }

  /// 响应正文的一行摘要(去标签/压缩空白,截断 160 字),用于错误提示与诊断日志。
  static String _snippet(String body) {
    final plain = body
        .replaceAll(RegExp(r'<script.*?</script>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<style.*?</style>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.isEmpty) return '(空正文)';
    return plain.length <= 160 ? plain : '${plain.substring(0, 160)}…';
  }

  /// 3xx 会话异常的报错文案。  ///
  /// 302 → `/web/user/logout` 表示当前 Cookie 是**匿名态**(缺 cblogin 签发的
  /// `uid`),与票据过期不同:刷新后若仍未登录会再次抛此处,便于区分。
  static String _expiredMessage(int status, Response<dynamic> resp) {
    final location = resp.headers.value('location') ?? '';
    if (location.toLowerCase().contains('logout')) {
      return '入馆教育会话未登录(HTTP $status → $location),已尝试刷新';
    }
    return '入馆教育会话已失效(HTTP $status),已尝试刷新';
  }

  /// 3xx 分流:会话问题 → [TsgxsSessionExpiredException](可刷新重试);
  /// 服务端未授权/不存在 → [TsgxsAccessDeniedException](业务状态,勿刷新)。
  static Exception _redirectError(int status, Response<dynamic> resp) {
    final location = resp.headers.value('location') ?? '';
    final lower = location.toLowerCase();
    if (lower.contains('/html/401.html')) {
      return const TsgxsAccessDeniedException(
        '服务端未授权(401):本章答题尚未开放,需先学完本章全部线索/通过上一章考试',
      );
    }
    if (lower.contains('/html/404.html')) {
      return const TsgxsAccessDeniedException(
        '服务端返回 404:内容不存在(章节可能已调整,请返回首页刷新)',
      );
    }
    return TsgxsSessionExpiredException(_expiredMessage(status, resp));
  }

  /// 取回页面 HTML;会话失效(302 回登录页 / 被顶下线提示)抛
  /// [TsgxsSessionExpiredException],由仓库层刷新会话后重试。
  Future<String> _getHtml(
    String path, {
    required String cookie,
    String? referer,
  }) async {
    final resp = await _dio.get(
      path,
      options: Options(
        headers: {'Cookie': cookie, 'Referer': ?referer},
        followRedirects: false,
        validateStatus: (s) => true,
      ),
    );
    final status = resp.statusCode ?? 0;
    final body = resp.data?.toString() ?? '';
    _trace('GET', path, status, resp, referer);
    if (status >= 300 && status < 400) {
      throw _redirectError(status, resp);
    }
    if (body.contains('已在别处登录') || body.contains('被迫下线')) {
      throw TsgxsSessionExpiredException('账号已在别处登录,本会话被顶下线');
    }
    if (status != 200) {
      throw TsgxsApiException('入馆教育请求失败(HTTP $status)');
    }
    return body;
  }

  /// JSON 接口(GET 无 body / POST 表单),统一做会话与错误判定。
  Future<Map<String, dynamic>> _json(
    String path, {
    required String cookie,
    String? referer,
    Map<String, dynamic>? query,
    Map<String, dynamic>? form,
  }) async {
    final resp = await _dio.request<dynamic>(
      path,
      queryParameters: query,
      data: form,
      options: Options(
        method: form == null ? 'GET' : 'POST',
        headers: {
          'Cookie': cookie,
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': ?referer,
        },
        contentType: form == null ? null : Headers.formUrlEncodedContentType,
        // 关键:必须自己拿原始字符串。这些接口的 JSON 响应会带
        // `Content-Type: application/json`,Dio 默认**已经把它解析成 Map**,
        // 若再对 `resp.data.toString()`(Dart Map 的 toString,键值无引号)做
        // jsonDecode 必然失败 → 误报「返回非 JSON」。取 plain 后统一自行解码。
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (s) => true,
      ),
    );
    final status = resp.statusCode ?? 0;
    final raw = resp.data;
    final body = raw is String ? raw : (raw?.toString() ?? '');
    _trace(form == null ? 'GET' : 'POST', path, status, resp, referer);
    if (status >= 300 && status < 400) {
      throw _redirectError(status, resp);
    }
    if (body.contains('已在别处登录') || body.contains('被迫下线')) {
      throw TsgxsSessionExpiredException('账号已在别处登录,本会话被顶下线');
    }
    if (status != 200) {
      throw TsgxsApiException('入馆教育请求失败(HTTP $status)');
    }
    // 兜底:万一哪个 Dio 适配器仍把 JSON 解析掉了,直接用现成的 Map。
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    final text = body.startsWith('\uFEFF') ? body.substring(1) : body;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      // 服务端认不出请求(如题目 id 不属于当前开考记录)时,会给 **HTTP 200 +
      // text/html 的「500 服务器错误」页** —— 必须把状态码/类型/正文片段带出来,
      // 否则界面只显示一句「非 JSON」,无从判断。
      final ct = resp.headers.value('content-type') ?? 'unknown';
      final snippet = _snippet(text);
      unawaited(_apiTrace('  非 JSON 响应: status=$status ct=$ct body=$snippet'));
      throw TsgxsApiException('接口返回的不是 JSON(HTTP $status,$ct):$snippet');
    }
    if (decoded is! Map) {
      throw const TsgxsApiException('答题接口返回格式异常');
    }
    return decoded.map((k, v) => MapEntry(k.toString(), v));
  }

  /// 首页:章节 id 列表与皮肤 id。
  Future<({List<String> chapterIds, String? themeId})> fetchHome(
    String cookie,
  ) async {
    final html = await _getHtml('/Web/User', cookie: cookie);
    final home = parseTsgxsHome(html);
    if (home.chapterIds.isEmpty) {
      throw TsgxsApiException('未能从首页解析出章节列表(页面结构可能已变化)');
    }
    return home;
  }

  /// 章节地图(含线索节点、是否看完、考试状态码)。
  ///
  /// 未解锁的章节(需先通过上一章考试)服务端返回 302 `/html/401.html`,
  /// 这里转成可读的业务提示,不当作会话问题。
  Future<TsgxsChapter> fetchChapter(
    String cookie, {
    required String chapterId,
    required String themeId,
  }) async {
    final String html;
    try {
      html = await _getHtml(
        '/Web/Chapter/Index/$chapterId?tid=$themeId',
        cookie: cookie,
        referer: 'http://tsgxs.jxufe.cn/Web/User',
      );
    } on TsgxsAccessDeniedException {
      throw const TsgxsAccessDeniedException('本章尚未解锁:需先学完上一章线索并通过上一章的闯关考试');
    }
    return parseTsgxsChapter(html, chapterId);
  }

  /// 学习内容页(正文图片 + 前后导航)。
  Future<TsgxsContent> fetchContent(
    String cookie, {
    required String nodeId,
    required String themeId,
  }) async {
    final html = await _getHtml(
      '/Web/Chapter/Content/$nodeId?tid=$themeId',
      cookie: cookie,
    );
    final content = parseTsgxsContent(html, nodeId);
    if (content.imageUrls.isEmpty && content.title.isEmpty) {
      throw TsgxsApiException('内容页解析失败(节点可能不存在)');
    }
    return content;
  }

  /// 我的成绩(本次成绩 + 考试记录)。
  Future<List<TsgxsGrade>> fetchGrades(String cookie) async {
    final html = await _getHtml('/Web/Center/MyGrades', cookie: cookie);
    return parseTsgxsGrades(html);
  }

  /// 排行榜。
  Future<TsgxsRanking> fetchRanking(String cookie) async {
    final html = await _getHtml('/Web/Center/Top', cookie: cookie);
    return parseTsgxsRanking(html);
  }

  /// 个人资料。
  Future<TsgxsProfile> fetchProfile(String cookie) async {
    final html = await _getHtml('/Web/Center/Info', cookie: cookie);
    return parseTsgxsProfile(html);
  }

  /// 章节考试状态(`/Web/Exam?cid=<章节 id>`)。
  ///
  /// 答题尚未开放时服务端 302 `/html/401.html`(线索未看完 / 上一章未通过)
  /// → 返回 [TsgxsExamState.blocked] 并把原因交给界面,**不**触发会话重建。
  Future<TsgxsExamStatus> fetchExamStatus(
    String cookie, {
    required String chapterId,
  }) async {
    final String html;
    try {
      html = await _getHtml(
        '/Web/Exam?cid=$chapterId',
        cookie: cookie,
        referer: 'http://tsgxs.jxufe.cn/Web/Chapter/Index/$chapterId',
      );
    } on TsgxsAccessDeniedException {
      return const TsgxsExamStatus(
        state: TsgxsExamState.blocked,
        message: '答题尚未开放:需先学完本章全部线索(上一章未通过也会锁定本章)',
      );
    }
    if (html.contains('已通过本章节考试')) {
      final next = RegExp(
        r'/Web/Chapter/Index/([0-9a-f\-]{36})',
      ).firstMatch(html)?.group(1);
      return TsgxsExamStatus(
        state: TsgxsExamState.passed,
        message: '已通过本章节考试',
        nextChapterId: next,
      );
    }
    final plain = html
        .replaceAll(RegExp(r'<script.*?</script>', dotAll: true), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return TsgxsExamStatus(
      state: TsgxsExamState.ready,
      message: plain.length > 120 ? plain.substring(0, 120) : plain,
    );
  }

  // ---------------- 闯关答题 ----------------

  /// 打开答题页(`GET /Web/Exam?cid=<章节id>`):拿本次考试的题目清单;
  /// 本章已通过时返回 [TsgxsExamPage.passed]。
  Future<TsgxsExamPage> fetchExamPage(
    String cookie, {
    required String chapterId,
  }) async {
    final String html;
    try {
      html = await _getHtml(
        '/Web/Exam?cid=$chapterId',
        cookie: cookie,
        referer: 'http://tsgxs.jxufe.cn/Web/Chapter/Index/$chapterId',
      );
    } on TsgxsAccessDeniedException {
      return const TsgxsExamPage(message: '答题尚未开放:需先学完本章全部线索(上一章未通过也会锁定本章)');
    }
    return parseTsgxsExamPage(html);
  }

  /// 取一道题的题干与选项(`GET /web/Exam/GetQueOpt`)。
  Future<TsgxsQuestion> fetchExamQuestion(
    String cookie, {
    required String questionId,
    String? examPageUrl,
  }) async {
    final json = await _json(
      '/web/Exam/GetQueOpt',
      cookie: cookie,
      query: {'id': questionId},
      referer: examPageUrl,
    );
    final question = parseTsgxsQuestion(json);
    if (question.id.isEmpty) {
      throw const TsgxsApiException('题目解析失败(题目可能已失效,请返回章节重新开考)');
    }
    return question;
  }

  /// 提交单题评分(`POST /web/Exam/GetAnswer`)。
  ///
  /// [answer] 选择题传选项 id 逗号串,填空/抄写传文本;[spendtime] 为本场已用
  /// 秒数;[helpId] 为使用道具重答时回传的道具 id(默认全零 GUID = 不用道具)。
  Future<TsgxsAnswerResult> submitAnswer(
    String cookie, {
    required String questionId,
    required String answer,
    required String chapterId,
    required String examRecordDetailsId,
    required int spendtime,
    String? helpId,
    String? examPageUrl,
  }) async {
    final json = await _json(
      '/web/Exam/GetAnswer',
      cookie: cookie,
      referer: examPageUrl,
      form: {
        'stid': questionId,
        'answer': answer,
        'zid': chapterId,
        'examRecordDetailsId': examRecordDetailsId,
        'spendtime': '$spendtime',
        'helpId': helpId ?? tsgxsNilGuid,
      },
    );
    return parseTsgxsAnswerResult(json);
  }

  /// 末题结算(`POST /web/exam/GetGameRole`):通过 / 获得道具 / 需重新闯关。
  Future<TsgxsExamFinishResult> finishExam(
    String cookie, {
    required String examRecordDetailsId,
    required String chapterId,
    required int spendtime,
    String? examPageUrl,
  }) async {
    final json = await _json(
      '/web/exam/GetGameRole',
      cookie: cookie,
      referer: examPageUrl,
      form: {
        'examRecordDetailsId': examRecordDetailsId,
        'zid': chapterId,
        'spendtime': '$spendtime',
      },
    );
    return parseTsgxsFinishResult(json);
  }
}
