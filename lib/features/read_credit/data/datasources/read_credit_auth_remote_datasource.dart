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

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/core/network/cas_walk.dart';
import 'package:smarter_jxufe/core/network/cookie_jar.dart';

/// 阅读学分平台会话失效（被重定向回 CAS 登录入口）。
class ReadCreditSessionExpiredException extends SessionExpiredException {

  ReadCreditSessionExpiredException([super.message = '阅读学分平台会话已失效']);
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
    final jar = HostCookieJar();
    // 循环机制走地基件（`lib/core/network/cas_walk.dart`）；这里只留本平台的语义：
    // 12 跳上限、trace 宽度（url 130 / location 90）、以及「没有 Location 且
    // Cookie 已带 uid+token 才算成功」这道判据。
    final outcome = await walkCasRedirects<String>(
      startUrl: ticketUrl,
      jar: jar,
      send: casDioSender(_dio),
      spec: const CasWalkSpec(
        maxHops: 12,
        traceUrlMax: 130,
        traceLocationMax: 90,
      ),
      trace: trace,
      afterResponse: (step) {
        if (step.hasLocation) return null;
        final session = jar.headerFor(host);
        return hasSession(session) ? CasHopFinish(session) : null;
      },
    );

    final session = outcome.result;
    if (session != null) return session;
    if (outcome.exhausted) {
      throw ReadCreditSessionExpiredException('建立阅读学分会话失败：重定向次数过多');
    }
    throw ReadCreditSessionExpiredException(
      '建立阅读学分会话失败：未取得平台会话 Cookie'
      '（得到 [${jar.namesOf(host)}]，HTTP ${outcome.lastStatusCode}）',
    );
  }
}
