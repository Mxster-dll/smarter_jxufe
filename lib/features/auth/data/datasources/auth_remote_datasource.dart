import 'dart:math';

import 'package:dio/dio.dart';

/// CAS 登录页面的关键信息，从 HTML 中提取。
class CasLoginPageInfo {
  /// 登录表单的 action URL（含 service 参数和 sessionToken）
  final String loginUrl;

  /// 服务端生成的 execution token（每次页面加载都会变化）
  final String execution;

  const CasLoginPageInfo({required this.loginUrl, required this.execution});
}

class AuthRemoteDataSource {
  final Dio _dio;

  AuthRemoteDataSource(this._dio);

  // ---- CAS 登录入口 ----
  // ehall 门户首页是纯 HTML（JS 驱动跳转，非 HTTP 302），无法程序化跟踪。
  // 因此直接请求 CAS 登录页，service 参数指向 ehall 的回调地址。
  // CAS 协议本身不强制要求 sessionToken —— 它仅由 ehall 侧用于会话匹配。
  static const _casLoginPageUrl =
      'https://ssl.jxufe.edu.cn/cas/login'
      '?service=http%3A%2F%2Fehall.jxufe.edu.cn'
      '%2Famp-auth-adapter%2FloginSuccess';

  /// 预请求：获取 CAS 登录页面，从中提取 [execution] 和表单提交的 [loginUrl]。
  ///
  /// 直接访问 CAS 登录页（绕过 ehall 的 JS 重定向）。
  /// 如果 CAS 返回了带 sessionToken 的重定向，循环跟踪之。
  Future<CasLoginPageInfo> fetchCasLoginPage() async {
    String currentUrl = _casLoginPageUrl;

    for (int i = 0; i < 5; i++) {
      final response = await _dio.get(
        currentUrl,
        options: Options(followRedirects: false, validateStatus: (s) => true),
      );

      final status = response.statusCode;

      // 3xx → 继续追踪重定向（如 CAS 补全 sessionToken）
      if (status != null && status >= 300 && status < 400) {
        final location = response.headers.value('location');
        if (location == null) {
          throw Exception('重定向缺少 Location 头: $currentUrl');
        }
        currentUrl = _resolveUrl(currentUrl, location);
        continue;
      }

      // 非重定向 → 视为终到页，尝试提取 execution
      final html = response.data?.toString() ?? '';
      if (html.isEmpty) {
        throw Exception('空响应: $currentUrl (status=$status)');
      }

      // 从 HTML 中提取 execution token
      final execMatch = RegExp(
        r'name="execution"\s+value="([^"]+)"',
      ).firstMatch(html);
      final execution = execMatch?.group(1);
      if (execution != null && execution.isNotEmpty) {
        return CasLoginPageInfo(loginUrl: currentUrl, execution: execution);
      }

      // 页面不含 execution 且不是重定向 → 异常
      final preview = html.substring(0, min(300, html.length));
      throw Exception('非 CAS 登录页: $currentUrl (status=$status)\n$preview');
    }

    throw Exception('重定向次数过多，最后 URL: $currentUrl');
  }

  /// 将相对 URL 解析为绝对 URL
  static String _resolveUrl(String base, String target) {
    final uri = Uri.parse(target);
    if (uri.hasScheme) return target; // 已是绝对 URL
    return Uri.parse(base).resolve(target).toString();
  }

  /// 第一步：检测是否需要 MFA（多因素认证）。
  Future<Response> detectMfa({
    required String username,
    required String password,
    required String fpVisitorId,
    required String referer,
  }) async {
    const mfaUrl = 'https://ssl.jxufe.edu.cn/cas/mfa/detect';

    final response = await _dio.post(
      mfaUrl,
      options: Options(headers: _ajaxHeaders(referer: referer)),
      data: {
        'username': username,
        'password': password,
        'fpVisitorId': fpVisitorId,
      },
    );

    return response;
  }

  /// 第二步：提交登录表单。
  Future<Response> login({
    required String username,
    required String password,
    required String fpVisitorId,
    required String mfaState,
    required String execution,
    required String loginUrl,
    String trustAgent = '',
  }) async {
    final body = {
      'username': username,
      'password': password,
      'captcha': '',
      'currentMenu': '1',
      'failN': '0',
      'mfaState': mfaState,
      'execution': execution,
      '_eventId': 'submit',
      'geolocation': '',
      'fpVisitorId': fpVisitorId,
      'trustAgent': trustAgent,
      'submit1': 'Login1',
    };

    final response = await _dio.post(
      loginUrl,
      options: Options(
        headers: _formHeaders(referer: loginUrl),
        followRedirects: false,
      ),
      data: body,
    );

    return response;
  }

  /// 通过 TGC 获取 IMS（教务系统）的重定向 URL，同时从中提取 [gid_]。
  ///
  /// 返回 (重定向URL, gid_字符串)。
  /// [gid_] 为 null 时调用方应回退到内置默认值。
  Future<(String url, String? gid)> getRedirectImsUrl(String tgc) async {
    const imsServiceUrl =
        'https://ssl.jxufe.edu.cn/cas/login'
        '?service=https%3A%2F%2Fjwxt.jxufe.edu.cn%2F%2Fjxcjcaslogin';

    final response = await _dio.get(
      imsServiceUrl,
      options: Options(
        headers: {
          'Host': 'ssl.jxufe.edu.cn',
          'Connection': 'keep-alive',
          'Upgrade-Insecure-Requests': '1',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;'
              'q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,'
              'application/signed-exchange;v=b3;q=0.7',
          'Sec-Fetch-Site': 'cross-site',
          'Sec-Fetch-Mode': 'navigate',
          'Sec-Fetch-User': '?1',
          'Sec-Fetch-Dest': 'document',
          'sec-ch-ua':
              '"Not:A-Brand";v="99", "Microsoft Edge";v="145", "Chromium";v="145"',
          'sec-ch-ua-mobile': '?0',
          'sec-ch-ua-platform': '"Windows"',
          'Referer': 'http://ehall.jxufe.edu.cn/',
          'Accept-Encoding': 'gzip, deflate, br, zstd',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Cookie': 'TGC=$tgc; ',
        },
        followRedirects: false,
      ),
    );

    final location = response.headers.value('location');
    if (location == null) {
      throw Exception('IMS 重定向失败（TGC 可能已过期）\n${response.data}');
    }

    // 从重定向 URL 的查询参数中提取 gid_
    final gid = Uri.parse(location).queryParameters['gid_'];

    return (location, gid);
  }

  // ---- 请求头构建 ----

  /// MFA detect 接口的 AJAX 请求头
  static Map<String, String> _ajaxHeaders({required String referer}) => {
    'Host': 'ssl.jxufe.edu.cn',
    'Connection': 'keep-alive',
    'sec-ch-ua-platform': '"Windows"',
    'X-Requested-With': 'XMLHttpRequest',
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'sec-ch-ua':
        '"Chromium";v="148", "Microsoft Edge";v="148", "Not/A)Brand";v="99"',
    'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
    'sec-ch-ua-mobile': '?0',
    'Origin': 'https://ssl.jxufe.edu.cn',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Dest': 'empty',
    'Referer': referer,
    'Accept-Encoding': 'gzip, deflate, br, zstd',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
  };

  /// 表单 POST 登录的请求头
  static Map<String, String> _formHeaders({required String referer}) => {
    'Host': 'ssl.jxufe.edu.cn',
    'Connection': 'keep-alive',
    'Cache-Control': 'max-age=0',
    'sec-ch-ua':
        '"Chromium";v="148", "Microsoft Edge";v="148", "Not/A)Brand";v="99"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
    'Upgrade-Insecure-Requests': '1',
    'Content-Type': 'application/x-www-form-urlencoded',
    'Origin': 'https://ssl.jxufe.edu.cn',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;'
        'q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,'
        'application/signed-exchange;v=b3;q=0.7',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-User': '?1',
    'Sec-Fetch-Dest': 'document',
    'Referer': referer,
    'Accept-Encoding': 'gzip, deflate, br, zstd',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
  };
}
