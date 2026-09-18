/// 图书馆订阅词 CRUD · 远端数据源（实测端点 2026-09-17）。
///
/// 全部是 `POST` + JSON body，靠 **Cookie 串**鉴权（`SESSION=…`）：
///
/// ```
/// POST /find/subscribe/list   {}                                        → {success, data:[{subId, subName, …}]}
/// POST /find/subscribe/add    {searchField:"keyWord", searchFieldContent:W, subName:W}
/// POST /find/subscribe/del    {subId:<id>}
/// ```
///
/// 三条实测约束（协议就建立在它们之上）：
/// 1. **单条上限 = 100 个字符**（不是字节；写 303 个汉字读回恰好 100 字 / 294 字节）；
/// 2. **超长是静默截断**：`add` 照样返回 `success:true`，所以调用方必须读回校验；
/// 3. **不去重**：同一条写两次列表里就有两条 —— 幂等由 App 自己保证，清理只能按结构全删。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/library_sync/domain/libsp_remote.dart';

/// 会话失效（401 / 落到登录页）。
class LibspSessionExpiredException implements Exception {
  LibspSessionExpiredException([this.message = '图书馆会话已失效']);

  final String message;

  @override
  String toString() => message;
}

/// 写入被服务端拒绝（配额 / 参数）。
class LibspWriteRejectedException implements Exception {
  LibspWriteRejectedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 订阅词远端数据源。
class LibspSubscribeRemoteDataSource {
  LibspSubscribeRemoteDataSource(this._dio);

  final Dio _dio;

  static const String base = 'https://findjxufe.libsp.cn';
  static const String listPath = '/find/subscribe/list';
  static const String addPath = '/find/subscribe/add';
  static const String delPath = '/find/subscribe/del';

  /// 新增时两个字段取同值（前端源码原样：`searchFieldContent` 与 `subName`）。
  static const String searchField = 'keyWord';

  Future<List<LibspRemoteWord>> listWords(String cookie) async {
    final data = await _post(listPath, cookie, const {});
    return _parseList(data);
  }

  Future<void> addWord(String cookie, String name) async {
    final data = await _post(addPath, cookie, {
      'searchField': searchField,
      'searchFieldContent': name,
      'subName': name,
    });
    if (data is Map && data['success'] == false) {
      throw LibspWriteRejectedException(
        '服务端拒绝新增订阅词：${data['message'] ?? data['errCode'] ?? '未知原因'}',
      );
    }
  }

  Future<void> deleteWord(String cookie, int subId) async {
    final data = await _post(delPath, cookie, {'subId': subId});
    if (data is Map && data['success'] == false) {
      throw LibspWriteRejectedException(
        '服务端拒绝删除订阅词：${data['message'] ?? data['errCode'] ?? '未知原因'}',
      );
    }
  }

  /// 解析列表回执；兼容 `data` 直接是数组或包在 `list/records/rows` 里。
  static List<LibspRemoteWord> _parseList(Object? data) {
    Object? payload = data is Map ? data['data'] : data;
    if (payload is Map) {
      payload =
          payload['list'] ?? payload['records'] ?? payload['rows'] ?? payload;
    }
    if (payload is! List) return const [];
    final out = <LibspRemoteWord>[];
    for (final item in payload) {
      if (item is! Map) continue;
      final id = item['subId'];
      final name = item['subName'];
      if (id is! num || name is! String) continue;
      out.add(LibspRemoteWord(subId: id.toInt(), subName: name));
    }
    return out;
  }

  Future<Object?> _post(
    String path,
    String cookie,
    Map<String, dynamic> body,
  ) async {
    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        '$base$path',
        data: body,
        options: Options(
          followRedirects: false,
          validateStatus: (_) => true,
          headers: {
            'Cookie': cookie,
            'Referer': '$base/',
            'Origin': base,
            'Content-Type': 'application/json;charset=UTF-8',
            'Accept': 'application/json, text/plain, */*',
          },
        ),
      );
    } on DioException catch (e) {
      throw LibspSessionExpiredException(
        '图书馆请求失败（${e.message ?? e.type.name}）',
      );
    }

    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw LibspSessionExpiredException('图书馆会话已过期（HTTP $status），请重新同步');
    }
    if (status >= 300 && status < 400) {
      // 被重定向到登录页 = 会话失效（实测未认证时也可能直接给 401 JSON）。
      throw LibspSessionExpiredException('图书馆会话已失效（被重定向到 $status）');
    }
    final raw = response.data;
    if (raw is Map) return raw;
    if (raw is String) {
      if (raw.trimLeft().startsWith('<')) {
        throw LibspSessionExpiredException('图书馆会话已失效（返回了网页而非 JSON）');
      }
      try {
        return jsonDecode(raw);
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }
}
