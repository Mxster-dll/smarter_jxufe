/// 图书馆（findjxufe.libsp.cn）会话建立 · 统一认证链（实测 2026-09-17 抓通）。
///
/// 完整链路（**零密码**：只要 App 已登录过，TGC 就在 `auth.hive` 里）：
///
/// 1. `AuthRepository.getServiceRedirectUrl(casServiceUrl)` —— 用已有 TGC 向学校 CAS
///    换票，返回跳出 CAS 域后的地址：
///    `https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index?ticket=ST-…`；
///    ⚠ service 必须写**超星网关**那个（`…/login_auth/cas/jxufe/index`）—— 图书馆自己的
///    域名不在学校 CAS 白名单里（实测：`findjxufe.libsp.cn` 的 5 个变体全部返回
///    「未认证授权的服务」，而网关这个拿到登录页）。
/// 2. 网关消费票据 → 302 回 `/login_auth/cas/jxufe/index` → 200 一张「跳转中…」页
///    （约 3.2 KB），页内 JS 带三个签名值 `data` / `time` / `enc` 与一份用户信息；
/// 3. 按页内脚本原样重放 `GET /login_auth/cas/jxufe/login?data=…&time=…&enc=…`
///    → `{"cxuser":{…},"status":true}`（**失败时是 `{"msg":"参数错误","status":false}`**）；
/// 4. 最后按页内 `jumpToRefer()` 的规则跳
///    `<refer>?data=…&time=…&enc=…`（refer = `…/find/sso/login/jxufe/0?pageType=0`）
///    → 302 到 `#/Home?jwt=…`，并在 **findjxufe.libsp.cn 域**下发会话 Cookie。
///
/// ⚠ 会话 Cookie 名是 **`SESSION`**（Spring Session），不是 `JSESSIONID`；另有两个
/// 辅助 Cookie（`_passport_login` / `route`）。回跳 URL 里那个 `jwt` 是给 SPA 存
/// localStorage 用的，App 侧不需要它。
///
/// **Cookie 按 host 隔离**（与 `tsgxs`/`cxstar` 同口径）：网关与图书馆各自签发
/// 同名 Cookie，混发会把会话搞坏。
library;

import 'package:dio/dio.dart';

/// 会话建立失败（票据被拒 / 网关不认 / 没拿到图书馆 Cookie）。
class LibspSessionException implements Exception {
  LibspSessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 图书馆统一认证数据源。
class LibspAuthRemoteDataSource {
  LibspAuthRemoteDataSource(this._dio);

  final Dio _dio;

  /// 学校 CAS 入口（service = **超星统一认证网关**）。
  ///
  /// 传给 `AuthRepository.getServiceRedirectUrl` 的正是这一串。
  static const String casServiceUrl =
      'https://ssl.jxufe.edu.cn/cas/login'
      '?service=https%3A%2F%2Funified-auth.chaoxing.com%2Flogin_auth%2Fcas%2Fjxufe%2Findex';

  /// 超星统一认证网关 host。
  static const String gatewayHost = 'unified-auth.chaoxing.com';

  /// 图书馆 host（会话 Cookie 的归属域）。
  static const String libraryHost = 'findjxufe.libsp.cn';

  /// 网关的票据回调入口。
  static const String gatewayCallback =
      'https://unified-auth.chaoxing.com/login_auth/cas/jxufe/index';

  /// 网关的身份桥接接口（页内脚本调用的那个）。
  static const String gatewayLoginPath = '/login_auth/cas/jxufe/login';

  /// 回跳目标（页内 `refer`，来自服务端 `findConfig.unifieAuthenLoginUrl`）。
  static const String loginRefer =
      'https://findjxufe.libsp.cn/find/sso/login/jxufe/0?pageType=0';

  /// 会话 Cookie 名（Spring Session）。
  static const String sessionCookieName = 'SESSION';

  /// Cookie 串里是否已有会话。
  static bool hasSession(String cookie) =>
      RegExp('(?:^|;\\s*)$sessionCookieName=[^;]+').hasMatch(cookie);

  /// 建立会话：跟随换证链，返回**图书馆域**的 Cookie 串。
  ///
  /// [trace] 非空时逐跳追加诊断行（调试期观察链路用，**不要打日志到生产**）。
  Future<String> establishSession(
    String ticketUrl, {
    List<String>? trace,
  }) async {
    final jar = <String, Map<String, String>>{};
    var url = ticketUrl;

    // ① 票据 → 网关回调（可能直接 302，也可能落页）
    var response = await _get(url, jar);
    _storeCookies(jar, Uri.parse(url).host, response);
    trace?.add('跳[0] ${response.statusCode} ${_clip(url, 120)}');

    for (var hop = 1; hop <= 8; hop++) {
      final location = response.headers.value('location');
      if (location != null && location.isNotEmpty) {
        url = Uri.parse(url).resolve(location).toString();
        // 网关回跳到自己的 index 页（不带 query）—— 继续跟。
        response = await _get(url, jar);
        _storeCookies(jar, Uri.parse(url).host, response);
        trace?.add('跳[$hop] ${response.statusCode} → ${_clip(url, 110)}');
        continue;
      }

      final host = Uri.parse(url).host;
      if (host == gatewayHost) {
        // ② 落到「跳转中…」页：抠出 data/time/enc 与用户信息，重放桥接接口。
        final body = response.data?.toString() ?? '';
        final params = parseGatewayBridgeParams(body);
        if (params.isEmpty) {
          throw LibspSessionException(
            '图书馆会话建立失败：网关跳转页里没有找到桥接参数（页面结构可能已改版）',
          );
        }
        trace?.add('   网关桥接参数：${params.keys.join(',')}');
        final login = await _get(
          'https://$gatewayHost$gatewayLoginPath',
          jar,
          query: params,
          extraHeaders: {
            'Referer': url,
            'X-Requested-With': 'XMLHttpRequest',
            'Accept': 'application/json, text/javascript, */*; q=0.01',
          },
        );
        _storeCookies(jar, gatewayHost, login);
        final text = login.data?.toString() ?? '';
        if (!text.replaceAll(' ', '').contains('"status":true')) {
          throw LibspSessionException(
            '图书馆会话建立失败：网关身份桥接被拒（${_clip(text, 160)}）',
          );
        }
        trace?.add('   网关身份桥接 status:true');

        // ③ 按页内 jumpToRefer 的规则跳回图书馆。
        final target =
            '$loginRefer&data=${params['data']}&time=${params['time']}&enc=${params['enc']}';
        response = await _get(target, jar);
        _storeCookies(jar, libraryHost, response);
        url = target;
        trace?.add('跳[$hop] 回跳图书馆 ${response.statusCode}');
        continue;
      }

      if (host == libraryHost) break;

      throw LibspSessionException(
        '图书馆会话建立失败：换证链走到了意料之外的主机 $host',
      );
    }

    final cookie = _cookieHeader(jar, libraryHost);
    if (!hasSession(cookie)) {
      throw LibspSessionException(
        '图书馆会话建立失败：未取得 $sessionCookieName '
        '（Cookie=[${jar[libraryHost]?.keys.join(',') ?? '空'}]）',
      );
    }
    return cookie;
  }

  /// 从「跳转中…」页里抠出桥接参数（`data` / `time` / `enc` + 用户信息）。
  ///
  /// 页面结构：`var data = "…";` 之类的声明 + `jQuery.ajax({ data:{ data:data, … } })`。
  /// 右侧可能是字面量也可能是标识符 —— **标识符要回代到 var 声明**，否则会把
  /// 变量名当成值传过去（实测这会得到 `{"msg":"参数错误","status":false}`）。
  static Map<String, String> parseGatewayBridgeParams(String html) {
    final decl = <String, String>{};
    for (final m in RegExp(
      r'''var\s+(\w+)\s*=\s*["']([^"']*)["']''',
    ).allMatches(html)) {
      decl[m.group(1)!] = m.group(2)!;
    }
    final block = RegExp(r'data:\s*\{(.*?)\}\s*,', dotAll: true).firstMatch(html);
    if (block == null) return const {};
    final out = <String, String>{};
    for (final m in RegExp(
      r'''(\w+)\s*:\s*(?:'([^']*)'|"([^"]*)"|([\w.\-]+))''',
    ).allMatches(block.group(1)!)) {
      final literal = m.group(2) ?? m.group(3);
      final bare = m.group(4);
      if (literal != null) {
        out[m.group(1)!] = literal;
      } else if (bare != null) {
        out[m.group(1)!] = decl[bare] ?? bare;
      }
    }
    return out;
  }

  Future<Response<dynamic>> _get(
    String url,
    Map<String, Map<String, String>> jar, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
  }) async {
    final host = Uri.parse(url).host;
    final cookie = _cookieHeader(jar, host);
    try {
      return await _dio.get<dynamic>(
        url,
        queryParameters: query,
        options: Options(
          followRedirects: false,
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
          headers: {
            if (cookie.isNotEmpty) 'Cookie': cookie,
            'Referer': 'https://$host/',
            if (extraHeaders != null) ...extraHeaders,
          },
        ),
      );
    } on DioException catch (e) {
      throw LibspSessionException(
        '图书馆换证请求失败（$host）：${e.message ?? e.type.name}',
      );
    }
  }

  static void _storeCookies(
    Map<String, Map<String, String>> jar,
    String host,
    Response<dynamic> response,
  ) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final map = jar.putIfAbsent(host, () => <String, String>{});
    for (final line in raw) {
      final first = line.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq > 0) map[first.substring(0, eq).trim()] = first.substring(eq + 1);
    }
  }

  static String _cookieHeader(
    Map<String, Map<String, String>> jar,
    String host,
  ) {
    final map = jar[host];
    if (map == null || map.isEmpty) return '';
    return map.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  static String _clip(String value, int max) =>
      value.length > max ? '${value.substring(0, max)}…' : value;
}
