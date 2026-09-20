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

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/core/network/cas_walk.dart';
import 'package:smarter_jxufe/core/network/cookie_jar.dart';
import 'package:smarter_jxufe/core/network/trace_text.dart';

/// 会话建立失败（票据被拒 / 网关不认 / 没拿到图书馆 Cookie）。
class LibspSessionException extends AppException {
  LibspSessionException(super.message);
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
    final jar = HostCookieJar();
    // 循环机制走地基件（`lib/core/network/cas_walk.dart`）；这里只留图书馆私有子协议：
    // 落在网关域 → 重放桥接接口（**异步，且下一跳地址是页面里算出来的**）→ 改跳回图书馆。
    // 成功与否仍由**罐里有没有 SESSION** 决定（见方法末尾 —— 与迁移前同一处判据）。
    final outcome = await walkCasRedirects<void>(
      startUrl: ticketUrl,
      jar: jar,
      send: (url, _) => _get(url, jar),
      spec: const CasWalkSpec(
        maxHops: 8,
        traceUrlMax: 120,
        traceLocationMax: 110,
      ),
      trace: trace,
      afterResponse: (step) async {
        // ① 先跟 Location（网关 302 回自己的 index 页 —— 继续跟）。
        if (step.hasLocation) return null;

        // ② 落到「跳转中…」页：抠出 data/time/enc 与用户信息，重放桥接接口。
        if (step.host == gatewayHost) {
          final params = parseGatewayBridgeParams(step.bodyText ?? '');
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
              'Referer': step.url,
              'X-Requested-With': 'XMLHttpRequest',
              'Accept': 'application/json, text/javascript, */*; q=0.01',
            },
          );
          jar.absorb(gatewayHost, login.headers['set-cookie']);
          final text = login.data?.toString() ?? '';
          if (!text.replaceAll(' ', '').contains('"status":true')) {
            throw LibspSessionException(
              '图书馆会话建立失败：网关身份桥接被拒（${clipForTrace(text, 160)}）',
            );
          }
          trace?.add('   网关身份桥接 status:true');

          // ③ 按页内 `jumpToRefer` 的规则**改跳**回图书馆（不跟 Location）。
          return CasHopGoto<void>(
            '$loginRefer&data=${params['data']}'
            '&time=${params['time']}&enc=${params['enc']}',
          );
        }

        if (step.host != libraryHost) {
          throw LibspSessionException(
            '图书馆会话建立失败：换证链走到了意料之外的主机 ${step.host}',
          );
        }
        return null; // 落在图书馆域：链路走完，收工
      },
    );
    if (outcome.exhausted) {
      trace?.add('   ⚠ 换证链跳数超过上限 ${outcome.hops}（一路没见到图书馆域）');
    }

    final cookie = jar.headerFor(libraryHost);
    if (!hasSession(cookie)) {
      throw LibspSessionException(
        '图书馆会话建立失败：未取得 $sessionCookieName '
        '（Cookie=[${jar.namesOf(libraryHost)}]）',
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
    HostCookieJar jar, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
  }) async {
    final host = Uri.parse(url).host;
    final cookie = jar.headerFor(host);
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


}
