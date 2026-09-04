import 'package:dio/dio.dart';

/// 综合管理平台（ssp.jxufe.edu.cn）SSO 入口信息。
///
/// 访问 `/sso/login.html` 会返回重定向到统一认证 CAS 的地址
/// （service 指向 ssp 自身，targetUrl 为原始目标页面），
/// 同时下发一个匿名 JSESSIONID，供后续换取正式会话使用。
class SspSsoEntry {
  /// 跳转到的 CAS 登录 URL（含 ssp 的 service 参数）。
  final String casLoginUrl;

  /// 本次访问下发的匿名 JSESSIONID。
  final String jsessionId;

  const SspSsoEntry({required this.casLoginUrl, required this.jsessionId});
}

/// 综合管理平台会话已失效（被重定向回登录页 / CAS）。
///
/// 由上层仓库捕获后自动执行「刷新会话 + 重试一次」。
class SspSessionExpiredException implements Exception {
  final String message;
  SspSessionExpiredException([this.message = '综合管理平台会话已过期']);

  @override
  String toString() => message;
}

/// 综合管理平台认证相关的远端数据源。
///
/// 只负责网络交互，不持有会话状态：
/// 每次调用由调用方显式传入 Cookie / 回调地址。
class SspAuthRemoteDataSource {
  final Dio _dio;

  SspAuthRemoteDataSource(this._dio);

  /// 获取 SSO 登录入口：GET /sso/login.html。
  ///
  /// 预期行为：302 + `Set-Cookie: JSESSIONID=...` + `Location: cas/login?...`。
  /// 返回入口信息后由上层携带 TGC 完成 CAS 跳转。
  Future<SspSsoEntry> fetchSsoLoginEntry() async {
    final response = await _dio.get(
      '/sso/login.html',
      options: Options(followRedirects: false, validateStatus: (s) => true),
    );

    final status = response.statusCode;
    final location = response.headers.value('location');
    final jsessionId = _extractJsessionId(response.headers);

    if (status == null || status < 300 || status >= 400) {
      throw Exception('获取综合管理平台登录入口失败（status=$status）');
    }
    if (location == null || location.isEmpty) {
      throw Exception('获取综合管理平台登录入口失败：未收到重定向地址');
    }
    if (jsessionId == null || jsessionId.isEmpty) {
      throw Exception('获取综合管理平台登录入口失败：未收到 JSESSIONID');
    }

    return SspSsoEntry(casLoginUrl: location, jsessionId: jsessionId);
  }

  /// 携带匿名 JSESSIONID 访问 CAS 回调地址（带 ticket），激活平台会话。
  ///
  /// 返回最终可用的 JSESSIONID：
  /// - 服务端通过 `Set-Cookie` 下发了新 ID → 使用新 ID；
  /// - 未下发 → 沿用调用方传入的 [jsessionId]（会话建在它之上）。
  ///
  /// 若响应把请求引回登录页（Location 含 `/sso/login` 或 `cas/login`），
  /// 说明激活失败，抛出 [SspSessionExpiredException]。
  Future<String> activateSession({
    required String callbackUrl,
    required String jsessionId,
  }) async {
    final response = await _dio.get(
      callbackUrl,
      options: Options(
        headers: {'Cookie': 'JSESSIONID=$jsessionId', 'Referer': callbackUrl},
        followRedirects: false,
        validateStatus: (s) => true,
      ),
    );

    final location = response.headers.value('location') ?? '';
    if (location.contains('/sso/login') || location.contains('cas/login')) {
      throw SspSessionExpiredException();
    }

    final updated = _extractJsessionId(response.headers);
    return (updated == null || updated.isEmpty) ? jsessionId : updated;
  }

  /// 从 Set-Cookie 头中提取首个 JSESSIONID 值。
  static String? _extractJsessionId(Headers headers) {
    final cookies = headers['set-cookie'];
    if (cookies == null || cookies.isEmpty) return null;
    for (final cookie in cookies) {
      final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(cookie);
      if (match != null) return match.group(1);
    }
    return null;
  }
}
