import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/anti_corruption/competition_parser.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';

/// 第二课堂「学科竞赛」数据源（综合管理服务平台 · 团委模块）。
///
/// 全部端点都是登录后页面 / 接口，需要 `Cookie: JSESSIONID=<ssp 会话>`：
///
/// | 用途 | 端点 |
/// |---|---|
/// | 我的申请列表 | GET `/admin/tzz/dektSubjectGame/apply_list.html` |
/// | 竞赛公示列表 | GET `/admin/tzz/dektSubjectGame/gs_list.html` |
/// | 比赛目录 | GET `/admin/tzz/dektSubjectGame/find_game.do` |
/// | 比赛奖项（JSON） | GET `/admin/tzz/dektSubjectGame/getCredit.do?gameId=` |
/// | 学生检索（团队用） | GET `/admin/tzz/dektSubjectGame/find_student.do` |
/// | 申请详情 | GET `/admin/tzz/dektSubjectGame/detail.html?id=&code=look` |
/// | 公示详情 | GET `/admin/tzz/dektSubjectGame/xd_detail.html?id=&code=look&team=` |
/// | 提交申请 | POST `/admin/tzz/dektSubjectGame/add.do` |
/// | 删除申请 | POST `/admin/tzz/dektSubjectGame/delete.do`（`ids[]`） |
/// | 上传证书图片 | POST `/admin/accessory/upload.do?system_dir_path=base/indexdownload` |
///
/// 会话失效（302 / 登录页 HTML）统一抛 [SspSessionExpiredException]，
/// 由 [CompetitionRepository] 刷新会话后重试一次。
class CompetitionRemoteDataSource {
  final Dio _dio;

  CompetitionRemoteDataSource(this._dio);

  /// 平台根地址（Referer 用）。
  static const String sspOrigin = 'http://ssp.jxufe.edu.cn';

  static const String _module = '/admin/tzz/dektSubjectGame';

  static const String applyListPath = '$_module/apply_list.html';
  static const String publicityListPath = '$_module/gs_list.html';
  static const String gameListPath = '$_module/find_game.do';
  static const String studentListPath = '$_module/find_student.do';
  static const String awardPath = '$_module/getCredit.do';
  static const String applyDetailPath = '$_module/detail.html';
  static const String publicityDetailPath = '$_module/xd_detail.html';
  static const String addPath = '$_module/add.do';
  static const String deletePath = '$_module/delete.do';
  static const String uploadPath = '/admin/accessory/upload.do';

  /// 列表页每页条数（官网默认 20）。
  static const int pageSize = 20;

  /// 详情页的 `code` 参数（官网固定传 `look`）。
  static const String detailCode = 'look';

  static String get _moduleReferer => '$sspOrigin$applyListPath';

  // ---- 列表 ----

  /// 我的申请列表。
  Future<CompetitionPage<CompetitionApply>> fetchApplyList({
    required String sessionId,
    int page = 1,
    String year = '',
    String gameName = '',
  }) async {
    final body = await _getPage(
      applyListPath,
      sessionId: sessionId,
      query: competitionPageRequestParams(
        page: page,
        pageSize: pageSize,
        filters: {
          'search_eq_parent.year': year,
          'search_like_parent.gameName': gameName,
        },
      ),
    );
    return CompetitionPage(
      items: parseCompetitionApplyList(body),
      page: page,
      totalPages: competitionTotalPages(body),
    );
  }

  /// 竞赛公示列表（全校）。
  Future<CompetitionPage<CompetitionPublicity>> fetchPublicityList({
    required String sessionId,
    int page = 1,
    String studentId = '',
    String name = '',
    String className = '',
  }) async {
    final body = await _getPage(
      publicityListPath,
      sessionId: sessionId,
      query: competitionPageRequestParams(
        page: page,
        pageSize: pageSize,
        filters: {
          'search_like_applyStudent.studentId': studentId,
          'search_like_applyStudent.name': name,
          'search_like_applyStudent.adminClassInformation.className': className,
        },
      ),
    );
    return CompetitionPage(
      items: parseCompetitionPublicityList(body),
      page: page,
      totalPages: competitionTotalPages(body),
    );
  }

  /// 比赛目录（208 页，必须靠搜索缩小范围）。
  Future<CompetitionPage<CompetitionGame>> fetchGames({
    required String sessionId,
    int page = 1,
    String year = '',
    String gameName = '',
  }) async {
    final body = await _getPage(
      gameListPath,
      sessionId: sessionId,
      query: competitionPageRequestParams(
        page: page,
        pageSize: pageSize,
        filters: {'search_eq_year': year, 'search_like_gameName': gameName},
      ),
    );
    return CompetitionPage(
      items: parseCompetitionGameList(body),
      page: page,
      totalPages: competitionTotalPages(body),
    );
  }

  /// 学生检索（团队申请加成员）。
  Future<CompetitionPage<CompetitionStudent>> fetchStudents({
    required String sessionId,
    int page = 1,
    String name = '',
    String studentId = '',
  }) async {
    final body = await _getPage(
      studentListPath,
      sessionId: sessionId,
      query: competitionPageRequestParams(
        page: page,
        pageSize: pageSize,
        filters: {'search_like_name': name, 'search_like_studentId': studentId},
      ),
    );
    return CompetitionPage(
      items: parseCompetitionStudentList(body),
      page: page,
      totalPages: competitionTotalPages(body),
    );
  }

  // ---- 详情 ----

  /// 申请详情（`detail.html`，官网同页可改，这里只读展示）。
  ///
  /// ⚠ 官网 `detail.html` 自 2026-09-18 起对全部记录返回 200 +「出错了」页（实测 4/4 条、
  /// 换 id 同样；与志愿活动详情同一类故障），而 `xd_detail.html` 对**同一个 id** 正常返回
  /// 同一条记录 → 解析出空字段时自动回落到公示详情端点（`competition_apply_detail.html`
  /// fixture 是失效前抓的，结构一致）。
  Future<CompetitionDetail> fetchApplyDetail({
    required String sessionId,
    required int id,
    CompetitionType type = CompetitionType.individual,
  }) async {
    final body = await _getPage(
      applyDetailPath,
      sessionId: sessionId,
      query: {'id': '$id', 'code': detailCode},
    );
    final detail = parseCompetitionDetail(body);
    if (detail.fields.isNotEmpty || detail.attachments.isNotEmpty) return detail;
    return _fetchPublicityDetailBody(sessionId: sessionId, id: id, type: type);
  }

  /// 公示详情（`xd_detail.html`，含最终奖项与个人得分）。
  Future<CompetitionDetail> fetchPublicityDetail({
    required String sessionId,
    required int id,
    CompetitionType type = CompetitionType.individual,
  }) => _fetchPublicityDetailBody(sessionId: sessionId, id: id, type: type);

  /// 一条学科竞赛记录的**加分信息**（申报奖项 / 最终奖项 / 个人得分 / 该赛别分值表）。
  ///
  /// 走公示详情端点 `xd_detail.html`：申请列表（`apply_list.html`）没有奖项与分值列，
  /// 申请详情端点 `detail.html` 又已失效，而**申请记录的 id 与公示记录是同一套**，
  /// `xd_detail.html?id=<申请 id>&code=look&team=个人` 直接返回同一条记录的
  /// 「学生提交的奖项 / 最终获得奖项（= 该赛别分值表）/ 个人得分」。
  Future<CompetitionApplyAward> fetchApplyAward({
    required String sessionId,
    required int id,
    CompetitionType type = CompetitionType.individual,
  }) async {
    final body = await _getPage(
      publicityDetailPath,
      sessionId: sessionId,
      query: {'id': '$id', 'code': detailCode, 'team': type.label},
      referer: '$sspOrigin$publicityListPath',
    );
    return parseCompetitionApplyAward(body);
  }

  Future<CompetitionDetail> _fetchPublicityDetailBody({
    required String sessionId,
    required int id,
    CompetitionType type = CompetitionType.individual,
  }) async {
    final body = await _getPage(
      publicityDetailPath,
      sessionId: sessionId,
      query: {'id': '$id', 'code': detailCode, 'team': type.label},
      referer: '$sspOrigin$publicityListPath',
    );
    return parseCompetitionDetail(body);
  }

  // ---- 写入 ----

  /// 某个比赛的可选奖项（`getCredit.do`，JSON）。
  Future<List<CompetitionAward>> fetchAwards({
    required String sessionId,
    required int gameId,
  }) async {
    final body = await _getPage(
      awardPath,
      sessionId: sessionId,
      query: {'gameId': '$gameId'},
      referer: '$sspOrigin$_module/toAdd.html',
    );
    return parseCompetitionAwards(body, gameId: gameId);
  }

  /// 上传一张证书图片，返回官网附件 id（进 `enclosure`）。
  Future<int> uploadAttachment({
    required String sessionId,
    required CompetitionAttachment attachment,
  }) async {
    final form = FormData.fromMap({
      'accessorys': MultipartFile.fromBytes(
        attachment.bytes,
        filename: attachment.fileName,
        contentType: _mediaTypeOf(attachment),
      ),
    });
    final response = await _post(
      uploadPath,
      sessionId: sessionId,
      data: form,
      query: {'system_dir_path': 'base/indexdownload'},
      referer: '$sspOrigin$_module/toAdd.html',
      contentType: null,
    );
    final reply = CompetitionJsonReply.parse(response);
    final ids = reply.attachmentIds;
    if (!reply.ok || ids.isEmpty) {
      throw Exception(reply.message.isEmpty ? '证书上传失败' : reply.message);
    }
    return ids.first;
  }

  /// 提交申请。返回官网提示文案（成功时形如「申请成功」）。
  ///
  /// ⚠ 官网 `add.do` **不做服务端校验**：字段为空也会返回「申请成功」而记录不落库
  /// （实测）。因此前端必须比照官网 `checkSubmit` 自行校验必填项。
  Future<String> submitApply({
    required String sessionId,
    required int gameId,
    required String remark,
    required CompetitionType type,
    required List<String> memberIds,
    required List<int> attachmentIds,
  }) async {
    final response = await _post(
      addPath,
      sessionId: sessionId,
      data: {
        'gameId': '$gameId',
        'remark': remark,
        'type': type.formValue,
        'team': memberIds.join(';'),
        'enclosure': attachmentIds.join(','),
      },
      referer: '$sspOrigin$_module/toAdd.html',
    );
    final reply = CompetitionJsonReply.parse(response);
    if (!reply.ok) {
      throw Exception(reply.message.isEmpty ? '提交失败' : reply.message);
    }
    return reply.message.isEmpty ? '提交成功' : reply.message;
  }

  /// 删除申请（官网参数是数组 `ids[]`）。
  Future<void> deleteApplies({
    required String sessionId,
    required List<int> ids,
  }) async {
    if (ids.isEmpty) return;
    final response = await _post(
      deletePath,
      sessionId: sessionId,
      data: {
        'ids[]': [for (final id in ids) '$id'],
      },
      referer: _moduleReferer,
    );
    final reply = CompetitionJsonReply.parse(response);
    if (!reply.ok) {
      throw Exception(reply.message.isEmpty ? '删除失败' : reply.message);
    }
  }

  // ---- HTTP ----

  Future<String> _getPage(
    String path, {
    required String sessionId,
    Map<String, dynamic>? query,
    String? referer,
  }) async {
    final response = await _dio.get(
      path,
      queryParameters: query,
      options: Options(
        headers: _headers(sessionId, referer: referer),
        followRedirects: false,
      ),
    );
    return _bodyOf(response);
  }

  Future<String> _post(
    String path, {
    required String sessionId,
    required Object data,
    Map<String, dynamic>? query,
    String? referer,
    String? contentType = Headers.formUrlEncodedContentType,
  }) async {
    final response = await _dio.post(
      path,
      data: data,
      queryParameters: query,
      options: Options(
        headers: _headers(sessionId, referer: referer, xhr: true),
        followRedirects: false,
        contentType: contentType,
      ),
    );
    return _bodyOf(response);
  }

  Map<String, String> _headers(
    String sessionId, {
    String? referer,
    bool xhr = false,
  }) => {
    'Cookie': 'JSESSIONID=$sessionId',
    'Referer': referer ?? _moduleReferer,
    if (xhr) 'X-Requested-With': 'XMLHttpRequest',
  };

  /// 3xx / 非 200 / 登录页 → 明确错误；其余返回响应体原文。
  ///
  /// ⚠ dio 的默认 `ResponseType.json` 会把 `application/json` 应答**自动解码**成
  /// Map/List（`data.toString()` 出来的是 Dart 字面量、不是 JSON）→ 一律重新
  /// `jsonEncode` 回 JSON 文本，交给上层解析器（否则 `getCredit.do` 的奖项与
  /// `add.do` 的应答全会被当成「格式不对」）。
  String _bodyOf(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    if (status >= 300 && status < 400) {
      throw SspSessionExpiredException();
    }
    if (status != 200) {
      throw Exception('请求失败: $status');
    }
    final data = response.data;
    final body = switch (data) {
      null => '',
      String text => text,
      Map() || List() => jsonEncode(data),
      _ => data.toString(),
    };
    if (competitionLooksLikeLoginRedirect(body)) {
      throw SspSessionExpiredException();
    }
    return body;
  }

  /// 由文件名 / MIME 推断上传类型（官网只接受 jpg / jpeg / png）。
  MediaType _mediaTypeOf(CompetitionAttachment attachment) {
    final declared = attachment.mimeType;
    if (declared != null && declared.contains('/')) {
      final parts = declared.split('/');
      return MediaType(parts.first, parts.last);
    }
    final name = attachment.fileName.toLowerCase();
    if (name.endsWith('.png')) return MediaType('image', 'png');
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }
    return MediaType('application', 'octet-stream');
  }
}
