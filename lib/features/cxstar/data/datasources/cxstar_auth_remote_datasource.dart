/// 畅想之星（m.cxstar.com）个人会话建立数据源。
///
/// 登录链（2026-09-12 抓包 + CDP 实测）：
/// 1. `https://m.cxstar.com/login` → 302 →
///    `https://ssl.jxufe.edu.cn/cas/login?service=http%3a%2f%2fua.cxstar.com`
///    `%2funiauth%2foutLogin%2flogin517%3fgotoUrl%3d2`（学校统一身份认证，
///    换票由 `AuthRepository.getServiceRedirectUrl` 完成，**service 必须 http**）；
/// 2. CAS 校验票据后经 `ua.cxstar.com/uniauth/outLogin/login517` 回跳
///    `m.cxstar.com`，个人 JWT 出现在**回跳地址的 query**（SPA 内的 `paramToken`
///    就是从 query 取 token 的机制）或 **Set-Cookie `mtoken`**；
/// 3. 业务请求凭 `Authorization: Bearer <JWT>`（同一串也接受 cookie `mtoken`），
///    有效期 24 小时（JWT `exp - iat` = 86400）。
///
/// 与 tsgxs / jhread 相同：**Cookie 按 host 隔离**，只把各 host 自己下发的
/// Cookie 发回；不同之处是登录态不是 Cookie 串而是 **token 本体**。
library;

import 'package:dio/dio.dart';

/// 畅想之星会话建立失败。
class CxstarSessionException implements Exception {
  final String message;

  CxstarSessionException([this.message = '畅想之星会话建立失败']);

  @override
  String toString() => message;
}

/// 畅想之星会话建立数据源。
class CxstarAuthRemoteDataSource {
  final Dio _dio;

  CxstarAuthRemoteDataSource(this._dio);

  /// 平台入口域（`/login` 会 302 到学校 CAS）。
  static const String origin = 'https://m.cxstar.com';

  /// 统一认证 service 入口（`ua.cxstar.com` 统一认证回调，登录后回跳 m.cxstar.com）。
  static const String casServiceUrl =
      'https://ssl.jxufe.edu.cn/cas/login'
      '?service=http%3a%2f%2fua.cxstar.com%2funiauth%2foutLogin%2flogin517'
      '%3fgotoUrl%3d2';

  /// 平台登录入口（未登录访问 `/user` 时的「前往登录」目标）。
  static const String loginPath = '/login';

  /// JWT 形态（三段 base64url，`eyJ` 开头 = `{"`）。
  static final RegExp jwtPattern = RegExp(
    r'eyJ[A-Za-z0-9_\-]{6,}\.[A-Za-z0-9_\-]{6,}\.[A-Za-z0-9_\-]{6,}',
  );

  /// 会话 token 的候选 cookie 名（实测回跳时下发 `mtoken`）。
  static const List<String> tokenCookieNames = ['mtoken', 'token', 'access_token'];

  /// 字符串是否像平台会话 token（JWT）。
  static bool looksLikeToken(String? value) =>
      value != null && value.isNotEmpty && jwtPattern.hasMatch(value);

  /// 从地址（含 query）里取 token。
  static String? tokenFromUri(Uri uri) {
    for (final name in tokenCookieNames) {
      final value = uri.queryParameters[name];
      if (looksLikeToken(value)) return value;
    }
    return jwtPattern.firstMatch(uri.toString())?.group(0);
  }

  /// 从 `Set-Cookie` 原始行里取 token。
  static String? tokenFromCookies(List<String>? rawCookies) {
    if (rawCookies == null || rawCookies.isEmpty) return null;
    for (final raw in rawCookies) {
      final first = raw.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final name = first.substring(0, eq).trim().toLowerCase();
      final value = first.substring(eq + 1).trim();
      if (tokenCookieNames.contains(name) && looksLikeToken(value)) {
        return value;
      }
    }
    for (final raw in rawCookies) {
      final match = jwtPattern.firstMatch(raw);
      if (match != null) return match.group(0);
    }
    return null;
  }

  /// 从响应正文里取 token（SPA 壳里的 token 是给 localStorage 用的，跳过）。
  static String? tokenFromBody(String? body) {
    if (body == null || body.isEmpty) return null;
    if (body.contains('<div id="root">')) return null;
    if (body.length > 200000) return null;
    return jwtPattern.firstMatch(body)?.group(0);
  }

  /// 打码（只露头部与尾部，用于日志/异常）。
  static String maskToken(String token) {
    if (token.length <= 18) return '***';
    return '${token.substring(0, 12)}…${token.substring(token.length - 6)}';
  }

  /// 建立个人会话：跟随换证链，返回**个人 JWT**。
  Future<String> establishSession(
    String ticketUrl, {
    List<String>? trace,
  }) async {
    final jar = <String, Map<String, String>>{};
    var url = ticketUrl;
    for (var hop = 0; hop < 15; hop++) {
      final uri = Uri.parse(url);
      final host = uri.host;

      // ① 回跳地址本身带 token（CAS → ua.cxstar.com → m.cxstar.com?token=…）。
      final inUrl = tokenFromUri(uri);
      if (inUrl != null) {
        trace?.add('跳[$hop] 回跳地址已带个人 token（${maskToken(inUrl)}）');
        return inUrl;
      }

      final cookieHeader = _cookieHeader(jar, host);
      final Response<dynamic> response;
      try {
        response = await _dio.get<dynamic>(
          url,
          options: Options(
            followRedirects: false,
            validateStatus: (status) => true,
            responseType: ResponseType.plain,
            headers: {
              if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
              'Referer': 'https://$host/',
            },
          ),
        );
      } on DioException catch (e) {
        throw CxstarSessionException(
          '畅想之星换证请求失败（$host）：${e.message ?? e.type.name}',
        );
      }

      final setCookies = response.headers['set-cookie'];
      _store(jar, host, setCookies);

      // ② Set-Cookie 里带 token（实测回跳域会下发 mtoken）。
      final inCookie = tokenFromCookies(setCookies);
      final location = response.headers.value('location');
      if (trace != null) {
        final names = (setCookies ?? const <String>[])
            .map((c) => c.split(';').first.split('=').first)
            .join(',');
        trace.add(
          '跳[$hop] ${response.statusCode} ${_clip(url, 120)}'
          '${location != null && location.isNotEmpty ? ' -> ${_clip(location, 80)}' : ''}'
          '${names.isNotEmpty ? '  Set-Cookie($host): $names' : ''}',
        );
      }
      if (inCookie != null) {
        trace?.add('  取得个人 token（cookie，${maskToken(inCookie)}）');
        return inCookie;
      }

      // ③ 正文里带 token（JSON 回执 / 非 SPA 页面）。
      final raw = response.data;
      final inBody = tokenFromBody(raw is String ? raw : raw?.toString());
      if (inBody != null) {
        trace?.add('  取得个人 token（正文，${maskToken(inBody)}）');
        return inBody;
      }

      if (location == null || location.isEmpty) {
        // 链路终止却没拿到 token：多半是落到未登录页（票被拒 / 需要重新登录）。
        throw CxstarSessionException(
          '畅想之星会话建立失败：换证链结束时未取得个人 token'
          '（最后停在 $host，HTTP ${response.statusCode}，'
          'Cookie=[${_cookieNamesOf(jar, host)}]）。'
          '若刚在别处登录过，可能是票据一次性或会话被顶；重试即可。',
        );
      }
      url = uri.resolve(location).toString();
    }
    throw CxstarSessionException('畅想之星会话建立失败：重定向次数过多');
  }

  static String _cookieNamesOf(
    Map<String, Map<String, String>> jar,
    String host,
  ) {
    final map = jar[host];
    if (map == null || map.isEmpty) return '(空)';
    return map.keys.join(',');
  }

  static String _cookieHeader(
    Map<String, Map<String, String>> jar,
    String host,
  ) {
    final map = jar[host];
    if (map == null || map.isEmpty) return '';
    return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 把某 host 响应的 Set-Cookie 存入其专属 jar（同名覆盖）。
  static void _store(
    Map<String, Map<String, String>> jar,
    String host,
    List<String>? setCookies,
  ) {
    if (setCookies == null || setCookies.isEmpty) return;
    final map = jar.putIfAbsent(host, () => <String, String>{});
    for (final raw in setCookies) {
      final first = raw.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq > 0) {
        map[first.substring(0, eq).trim()] = first.substring(eq + 1);
      }
    }
  }

  static String _clip(String value, int max) =>
      value.length > max ? '${value.substring(0, max)}…' : value;
}
