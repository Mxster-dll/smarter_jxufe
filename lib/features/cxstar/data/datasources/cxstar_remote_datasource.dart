/// 畅想之星「经典阅读」远程数据源（m.cxstar.com）。
///
/// 全部接口都在 `/api` 前缀下（裸路径会命中 SPA 壳，恒 200 + HTML）：
/// - `POST /api/auth/ip_login` 校园网 IP 免密登录 → JWT（全校公用号）；
/// - `GET  /api/user` 账号信息；
/// - `GET  /api/user/readsummary` 阅读本数 / 时长统计；
/// - `GET  /api/user/readings?page=N` 逐书阅读记录（`/api/user/GetReadTJ` 为同构兜底）。
///
/// 会话令牌走 **`Authorization: Bearer <JWT>`**（2026-09-12 抓包实测的正式口径；
/// 早期误用的 `userToken` 请求头已废弃），同一串也回传为 cookie `mtoken`。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/cxstar/domain/cxstar_book_report.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_models.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_shelf.dart';

class CxstarRemoteDataSource {
  final Dio _dio;

  const CxstarRemoteDataSource(this._dio);

  static const String ipLoginPath = '/api/auth/ip_login';
  static const String userPath = '/api/user';
  static const String summaryPath = '/api/user/readsummary';
  static const String readingsPath = '/api/user/readings';
  static const String readTjPath = '/api/user/GetReadTJ';

  // 书架（分类 / 书单 / 检索）：`/api/system/categories` 与
  // `/api/system/hotSearch` **必须带 `pinst`**（缺参数服务端 500）。
  static const String categoriesPath = '/api/system/categories';
  static const String hotSearchPath = '/api/system/hotSearch';

  /// 单本书阅读报告路径（逐书时长 / 阅读天数 / 读完时间）。
  static String bookReportPath(String bookId) => '/api/books/$bookId/readreport';

  /// 分类书单路径；`categoryId` 取分类树节点 id（传 `0` 为全库）。
  static String booksPath(String categoryId) =>
      '/api/categories/${categoryId.isEmpty ? '0' : categoryId}/books';

  Map<String, String> _authHeaders(String token) => {
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        if (token.isNotEmpty) 'Cookie': 'mtoken=$token',
      };

  /// 校园网 IP 免密登录，返回 JWT 令牌。
  Future<String> ipLogin() async {
    final json = await _request(
      ipLoginPath,
      method: 'POST',
      data: const <String, dynamic>{},
    );
    final code = '${json['code'] ?? ''}';
    final token = '${json['token'] ?? ''}';
    if (code != '1' || token.isEmpty) {
      final text = '${json['text'] ?? ''}';
      throw CxstarApiException(
        '畅想之星免密登录失败${text.isEmpty ? '' : '：$text'}',
      );
    }
    return token;
  }

  Future<CxstarUser> fetchUser(String token) async {
    final json = await _request(userPath, token: token);
    return CxstarUser.fromJson(json);
  }

  Future<CxstarReadSummary> fetchSummary(String token) async {
    final json = await _request(summaryPath, token: token);
    return CxstarReadSummary.fromJson(json);
  }

  /// 逐书阅读记录：`readings` 分页优先，失败回退 `GetReadTJ`。
  Future<List<CxstarReadRecord>> fetchRecords(String token, {int page = 1}) async {
    List<dynamic> rows = const [];
    try {
      final json = await _request(
        readingsPath,
        token: token,
        query: {'page': page},
      );
      rows = (json['data'] as List?) ?? const [];
    } catch (_) {
      final json = await _request(readTjPath, token: token);
      rows = (json['readData'] as List?) ?? const [];
    }
    return [
      for (final r in rows)
        if (r is Map) CxstarReadRecord.fromJson(r.cast<String, dynamic>()),
    ];
  }

  /// 逐书阅读报告：累计时长（分钟）/ 阅读天数 / 阅读次数 / **读完时间**。
  ///
  /// `filetype` 参数对结果无影响（0/1/2/3/4 与不传完全同构），故不传。
  /// 取不到报告（非 200 或 `data` 为空）返回 null，由界面静默省略该行。
  Future<CxstarBookReport?> fetchBookReport(
    String token,
    String bookId,
  ) async {
    if (bookId.isEmpty) return null;
    final json = await _request(bookReportPath(bookId), token: token);
    final data = json['data'];
    if (data is! Map) return null;
    return CxstarBookReport.fromJson(data.cast<String, dynamic>());
  }

  /// 分类字典（中图法 / 学科 / 院系三套体系）。
  ///
  /// `pinst` 必传（缺参数服务端 500）；返回体是**字典**，键为三套体系名。
  Future<CxstarShelfCategories> fetchShelfCategories(
    String token, {
    required String pinst,
  }) async {
    final json = await _request(
      categoriesPath,
      token: token,
      query: {'pinst': pinst},
    );
    return CxstarShelfCategories.fromJson(json);
  }

  /// 分类书单（`keyword` 非空即检索；`categoryId` 传空/`0` 为全库）。
  Future<CxstarBookPage> fetchCategoryBooks(
    String token, {
    required String categoryId,
    required String pinst,
    int page = 1,
    int size = 20,
    String keyword = '',
    String sortField = 'orderno',
  }) async {
    final json = await _request(
      booksPath(categoryId),
      token: token,
      query: {
        'page': page,
        'size': size,
        'pinst': pinst,
        'sortField': sortField,
        'sortType': 'DESC',
        'keyword': keyword,
        'Publishers': '',
        'Authors': '',
        'Pubdates': '',
        'Types': '',
        'Aggs': false,
      },
    );
    final rows = (json['data'] as List?) ?? const [];
    return CxstarBookPage(
      books: [
        for (final r in rows)
          if (r is Map) CxstarBook.fromJson(r.cast<String, dynamic>()),
      ],
      total: cxstarNum(json['total']),
      page: page,
      size: size,
    );
  }

  /// 热门检索词。
  Future<List<String>> fetchHotSearch({required String pinst}) async {
    final json = await _request(hotSearchPath, query: {'pinst': pinst});
    final rows = (json['data'] as List?) ?? const [];
    return [
      for (final w in rows)
        if (cxstarPlainText('$w').isNotEmpty) cxstarPlainText('$w'),
    ];
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    String token = '',
    Map<String, dynamic>? query,
    Object? data,
  }) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          responseType: ResponseType.plain,
          contentType: method == 'POST' ? Headers.jsonContentType : null,
          headers: _authHeaders(token),
        ),
      );
    } on DioException catch (e) {
      throw CxstarApiException('畅想之星网络请求失败：${e.message ?? e.type.name}');
    }
    final status = resp.statusCode ?? 0;
    final raw = resp.data;
    final body = raw is String ? raw : (raw?.toString() ?? '');
    if (status == 401) {
      throw const CxstarApiException(
        '畅想之星会话无效（HTTP 401）：请重新用统一身份认证登录，'
        '或确认当前在校园网内',
      );
    }
    if (status != 200) {
      throw CxstarApiException('畅想之星接口异常（HTTP $status）');
    }
    final trimmed = body.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
    if (trimmed.isEmpty) {
      throw const CxstarApiException('畅想之星接口返回空内容');
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return decoded.cast<String, dynamic>();
      throw const CxstarApiException('畅想之星接口返回格式异常（非对象）');
    } on FormatException {
      // 非 JSON 通常是命中了 SPA 壳（缺 /api 前缀）或网关错误页。
      final snippet = trimmed.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(
            RegExp(r'\s+'),
            ' ',
          );
      throw CxstarApiException(
        '畅想之星接口返回的不是 JSON：${snippet.length > 120 ? '${snippet.substring(0, 120)}…' : snippet}',
      );
    }
  }
}
