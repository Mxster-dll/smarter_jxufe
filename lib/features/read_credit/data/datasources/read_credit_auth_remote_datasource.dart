/// 阅读学分平台（jhread.zhixinst.com）会话建立数据源。
///
/// 登录链（2026-09-11 实测打通）与入馆教育同族，均为学校统一认证：
/// 1. TGC → `ssl.jxufe.edu.cn/cas/login?service=<平台 CASLogin 入口>`
///    （由 `AuthRepository.getServiceRedirectUrl` 完成）→ 带 ticket 的回调地址；
/// 2. `http://jhread.zhixinst.com/Web/CASLogin/Login?…&ticket=…` 校验票据 →
///    302 到 `https://jhread.zhixinst.com:443/Web/ReadMain/Index` → 200，
///    并下发平台自己的 `ASP.NET_SessionId` / `uid` / `token` / `uNickName`；
/// 3. 之后业务页（`/Web/ReadMain/Score`、`/Web/Read/Index/*`）凭该 Cookie 访问。
///
/// ⚠ **service 必须用 http**:平台自己下发的是 `https://jhread.zhixinst.com:443/…`，
/// 直接用会被 CAS 判为「未认证授权的服务」（返回 200 错误页、无 ticket），
/// 换成 `http://jhread.zhixinst.com/…` 才拿到 ticket（targetUrl 内层仍保持
/// 平台原始的 https 地址）。这与入馆教育的 `service` 必须 http 是同一个坑。
///
/// 与 tsgxs 相同：**Cookie 按 host 隔离**，只把各 host 自己下发的 Cookie 发回。
library;

import 'package:dio/dio.dart';

/// 阅读学分平台会话失效（被重定向回 CAS 登录入口）。
class ReadCreditSessionExpiredException implements Exception {
  final String message;

  ReadCreditSessionExpiredException([this.message = '阅读学分平台会话已失效']);

  @override
  String toString() => message;
}

/// 阅读学分平台会话建立数据源。
class ReadCreditAuthRemoteDataSource {
  final Dio _dio;

  ReadCreditAuthRemoteDataSource(this._dio);

  /// 平台域（会话 Cookie 归属域）。
  static const String host = 'jhread.zhixinst.com';

  /// 平台站点根（https，业务地址一律走它）。
  static const String origin = 'https://jhread.zhixinst.com';

  /// 统一认证 service 入口（platform CASLogin + `{base64}平台首页`）。
  static const String casServiceUrl =
      'https://ssl.jxufe.edu.cn/cas/login'
      '?service=http%3a%2f%2fjhread.zhixinst.com%2fWeb%2fCASLogin%2fLogin'
      '%3ftargetUrl%3d%7bbase64%7d'
      'aHR0cHM6Ly9qaHJlYWQuemhpeGluc3QuY29tOjQ0My9XZWIvUmVhZE1haW4vSW5kZXg%3d';

  /// 会话 Cookie 是否已带鉴权标识（`uid` 与 `token` 都缺即为匿名态）。
  static bool hasSession(String cookie) =>
      cookie.contains('uid=') && cookie.contains('token=');

  /// 建立会话：跟随换证链，返回**平台域**的 Cookie 串。
  Future<String> establishSession(
    String ticketUrl, {
    List<String>? trace,
  }) async {
    final jar = <String, Map<String, String>>{};
    var url = ticketUrl;
    for (var hop = 0; hop < 12; hop++) {
      final currentHost = Uri.parse(url).host;
      final cookieHeader = _cookieHeader(jar, currentHost);
      final response = await _dio.get<dynamic>(
        url,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => true,
          headers: {
            if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
            'Referer': 'https://$currentHost/',
          },
        ),
      );
      _store(jar, currentHost, response.headers['set-cookie']);
      final location = response.headers.value('location');
      if (trace != null) {
        final names = (response.headers['set-cookie'] ?? const <String>[])
            .map((c) => c.split(';').first.split('=').first)
            .join(',');
        trace.add(
          '跳[$hop] ${response.statusCode} ${_clip(url, 130)}'
          '${location != null && location.isNotEmpty ? ' -> ${_clip(location, 90)}' : ''}'
          '${names.isNotEmpty ? '  Set-Cookie($currentHost): $names' : ''}',
        );
      }
      if (location == null || location.isEmpty) {
        final session = _cookieHeader(jar, host);
        if (!hasSession(session)) {
          throw ReadCreditSessionExpiredException(
            '建立阅读学分会话失败：未取得平台会话 Cookie'
            '（得到 [${_cookieNamesOf(jar, host)}]，HTTP ${response.statusCode}）',
          );
        }
        return session;
      }
      url = Uri.parse(url).resolve(location).toString();
    }
    throw ReadCreditSessionExpiredException('建立阅读学分会话失败：重定向次数过多');
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
