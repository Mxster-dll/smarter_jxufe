/// 畅想之星阅读器远程数据源（单页 PDF + 进度 + 目录）。
///
/// 全部接口都要 `nonce/stime/sign`（见 [cxstarReaderSign]），路径前缀 `/api`：
/// - `GET  /api/books/{id}/read?page=N&isNewPdf=1&from=default&pinst=…` → 阅读会话；
/// - `GET  /api/books/{id}/pdfContent?typecode=ebook&pageno=N&bookId=…` → 单页加密 PDF 字节；
/// - `GET  /api/books/{id}/catalog?filetype=0` → 目录；
/// - `GET  /api/books/{id}/read/progress` / `POST` 同路径 → 续读位；
/// - `GET  /api/books/{id}/state?now=&ipToken=null&pinst=` → 阅读资格。
///
/// 鉴权 = `Authorization: Bearer <个人 JWT>`（同一串也回传为 cookie `mtoken`）；
/// 每次请求带 `Referer: https://m.cxstar.com/book/<id>/pdf`（实测该 Referer
/// 下接口才稳定放行）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/cxstar/domain/cxstar_models.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_reader.dart';

class CxstarReaderRemoteDataSource {
  final Dio _dio;

  const CxstarReaderRemoteDataSource(this._dio);

  Map<String, String> _headers({
    required String token,
    required String bookId,
    bool json = true,
  }) => {
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    if (token.isNotEmpty) 'Cookie': 'mtoken=$token',
    'Referer': 'https://m.cxstar.com/book/$bookId/pdf',
    'Accept': json ? 'application/json, text/plain, */*' : '*/*',
  };

  /// 阅读会话（含总页数 / 试读页 / 水位 / 本次 logId）。
  ///
  /// 该接口同时是**计时心跳**:服务端按在线阅读行为累计时长，会话内定期调用
  /// 即可持续入账（实测 60s 间隔有效，且不必重复拉正文）。
  Future<CxstarReadSession> fetchSession({
    required String token,
    required String bookId,
    required String pinst,
    int page = 1,
  }) async {
    final sign = cxstarReaderSign();
    final json = await _json(
      '/api/books/$bookId/read',
      token: token,
      bookId: bookId,
      query: {
        'page': page,
        'isNewPdf': 1,
        'from': 'default',
        'pinst': pinst,
        ...sign.toQuery(),
      },
    );
    return CxstarReadSession.fromJson(json);
  }

  /// 单页正文（AES-128 加密的单页 PDF 字节）。
  Future<Uint8List> fetchPagePdf({
    required String token,
    required String bookId,
    required String pinst,
    required int pageNo,
  }) async {
    final sign = cxstarReaderSign();
    final Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        '/api/books/$bookId/pdfContent',
        queryParameters: {
          'typecode': 'ebook',
          'pageno': pageNo,
          'bookId': bookId,
          'pinst': pinst,
          ...sign.toQuery(),
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: _headers(token: token, bookId: bookId, json: false),
        ),
      );
    } on DioException catch (e) {
      throw CxstarApiException('畅想之星取书页失败:${e.message ?? e.type.name}');
    }
    final status = resp.statusCode ?? 0;
    final data = resp.data;
    final bytes = switch (data) {
      Uint8List b => b,
      List<int> l => Uint8List.fromList(l),
      _ => Uint8List(0),
    };
    if (status != 200 || bytes.isEmpty) {
      throw CxstarApiException('畅想之星取书页失败（HTTP $status，${bytes.length} 字节）');
    }
    return bytes;
  }

  /// 目录（`filetype=0` 为章级目录）。
  Future<List<CxstarCatalogNode>> fetchCatalog({
    required String token,
    required String bookId,
  }) async {
    final json = await _json(
      '/api/books/$bookId/catalog',
      token: token,
      bookId: bookId,
      query: {'filetype': 0},
    );
    final rows = (json['data'] as List?) ?? const [];
    return [
      for (final r in rows)
        if (r is Map) CxstarCatalogNode.fromJson(r.cast<String, dynamic>()),
    ];
  }

  /// 续读位（上次读到第几页）；取不到返回 null。
  Future<int?> fetchProgress({
    required String token,
    required String bookId,
  }) async {
    try {
      final json = await _json(
        '/api/books/$bookId/read/progress',
        token: token,
        bookId: bookId,
      );
      final page = json['page'];
      if (page is int) return page;
      if (page is num) return page.toInt();
      if (page is String) return int.tryParse(page.trim());
      return null;
    } on CxstarApiException {
      return null;
    }
  }

  /// 上报续读位（翻页后调用；失败静默由调用方决定）。
  Future<void> postProgress({
    required String token,
    required String bookId,
    required int page,
    String logId = '',
    int paragraph = 0,
    int charIndex = 0,
    int percent = 0,
  }) async {
    try {
      final resp = await _dio.post<dynamic>(
        '/api/books/$bookId/read/progress',
        data: {
          'page': page,
          'paragraph': paragraph,
          'charIndex': charIndex,
          'logId': logId,
          'percent': percent,
        },
        options: Options(
          responseType: ResponseType.plain,
          contentType: Headers.jsonContentType,
          headers: _headers(token: token, bookId: bookId),
        ),
      );
      final status = resp.statusCode ?? 0;
      if (status == 401) {
        throw const CxstarApiException('畅想之星会话已失效，请重新用统一身份认证登录');
      }
    } on DioException catch (e) {
      throw CxstarApiException('畅想之星进度上报失败:${e.message ?? e.type.name}');
    }
  }

  Future<Map<String, dynamic>> _json(
    String path, {
    required String token,
    required String bookId,
    Map<String, dynamic>? query,
  }) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        path,
        queryParameters: query,
        options: Options(
          responseType: ResponseType.plain,
          headers: _headers(token: token, bookId: bookId),
        ),
      );
    } on DioException catch (e) {
      throw CxstarApiException('畅想之星网络请求失败:${e.message ?? e.type.name}');
    }
    final status = resp.statusCode ?? 0;
    final raw = resp.data;
    final body = raw is String ? raw : (raw?.toString() ?? '');
    if (status == 401) {
      throw const CxstarApiException('畅想之星会话无效（HTTP 401）:请重新用统一身份认证登录');
    }
    if (status == 404) {
      throw CxstarApiException('畅想之星接口 404（$path）:签名或参数被拒');
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
      final snippet = trimmed
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      throw CxstarApiException(
        '畅想之星接口返回的不是 JSON:'
        '${snippet.length > 120 ? '${snippet.substring(0, 120)}…' : snippet}',
      );
    }
  }
}
