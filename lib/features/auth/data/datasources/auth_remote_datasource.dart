import 'dart:math';

import 'package:dio/dio.dart';

/// CAS 登录页面的关键信息，从 HTML 中提取。
class CasLoginPageInfo {
  /// 登录表单的 action URL（含 service 参数和 sessionToken）
  final String loginUrl;

  /// 服务端生成的 execution token（每次页面加载都会变化）
  final String execution;

  /// CAS 服务端分配的 SESSION cookie。
  /// 后续 detectMfa / login 请求必须携带，否则服务端拒绝。
  final String sessionCookie;

  const CasLoginPageInfo({
    required this.loginUrl,
    required this.execution,
    required this.sessionCookie,
  });
}

class AuthRemoteDataSource {
  final Dio _dio;

  AuthRemoteDataSource(this._dio);

  // ---- CAS 登录入口 ----
  // 先请求 ehall 的 /amp-auth-adapter/login，服务端返回 302 Location
  // 指向 CAS 登录页（含动态 sessionToken），再用该 URL 获取登录页 HTML。
  static const _ehallLoginEntry =
      'http://ehall.jxufe.edu.cn/amp-auth-adapter/login'
      '?service=http%3A%2F%2Fehall.jxufe.edu.cn%2F';

  /// 预请求：通过 ehall 获取 CAS 登录页 URL，再从中提取 [execution] 和 [loginUrl]。
  Future<CasLoginPageInfo> fetchCasLoginPage() async {
    // 第一步：请求 ehall → 获取 CAS 登录页的重定向 URL（含 sessionToken）
    final ehallResponse = await _dio.get(
      _ehallLoginEntry,
      options: Options(
        followRedirects: false,
        validateStatus: (s) => true,
        headers: {
          'Host': 'ehall.jxufe.edu.cn',
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': 'http://ehall.jxufe.edu.cn/new/index.html',
          'Accept-Encoding': 'gzip, deflate',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
        },
      ),
    );

    final casLoginUrl = ehallResponse.headers.value('location');
    if (casLoginUrl == null) {
      throw Exception('ehall 未返回 CAS 重定向 URL，状态码=${ehallResponse.statusCode}');
    }

    // 第二步：访问 CAS 登录页，提取 execution 和 SESSION
    String currentUrl = casLoginUrl;

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
        // 初始 SESSION（登录页返回）
        var sessionCookie = _extractSessionCookie(response);

        // 请求二维码图片，将 SESSION 绑定到扫码会话。
        // 网页版登录时浏览器会自动加载 <img src="/cas/qr/qrcode?r=...">，
        // 这一步会更新/激活 SESSION，后续 login 请求必须携带绑定后的 cookie。
        final boundCookie = await _bindSessionViaQrCode(
          currentUrl,
          sessionCookie,
        );
        if (boundCookie != null) sessionCookie = boundCookie;

        return CasLoginPageInfo(
          loginUrl: currentUrl,
          execution: execution,
          sessionCookie: sessionCookie,
        );
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

  /// 从响应 Set-Cookie 中提取 SESSION= 值。
  static String _extractSessionCookie(Response response) {
    final cookies = response.headers['set-cookie'];
    if (cookies == null || cookies.isEmpty) return '';
    for (final c in cookies) {
      final match = RegExp(r'SESSION=([^;]+)').firstMatch(c);
      if (match != null) return 'SESSION=${match.group(1)}';
    }
    return '';
  }

  /// 请求二维码图片以绑定 SESSION。
  ///
  /// 网页版登录时浏览器自动加载 `<img src="/cas/qr/qrcode?r=...">`，
  /// 这一步使 CAS 服务端将当前的 SESSION 绑定为"允许提交登录"的状态。
  /// 返回绑定后更新的 SESSION；失败时返回 null（调用方回退到原值）。
  Future<String?> _bindSessionViaQrCode(
    String loginUrl,
    String sessionCookie,
  ) async {
    try {
      final r = DateTime.now().millisecondsSinceEpoch.toString();
      final headers = <String, String>{
        'Host': 'ssl.jxufe.edu.cn',
        'Accept':
            'image/avif,image/webp,image/apng,image/svg+xml,'
            'image/*,*/*;q=0.8',
        'sec-ch-ua':
            '"Not;A=Brand";v="8", "Chromium";v="150", "Microsoft Edge";v="150"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'Sec-Fetch-Site': 'same-origin',
        'Sec-Fetch-Mode': 'no-cors',
        'Sec-Fetch-Dest': 'image',
        'Referer': loginUrl,
        'Accept-Encoding': 'gzip, deflate, br, zstd',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
      };
      if (sessionCookie.isNotEmpty) headers['Cookie'] = sessionCookie;

      final response = await _dio.get(
        'https://ssl.jxufe.edu.cn/cas/qr/qrcode',
        queryParameters: {'r': r},
        options: Options(headers: headers, validateStatus: (s) => true),
      );

      // 检查响应中是否有更新后的 SESSION
      final updated = _extractSessionCookie(response);
      return updated.isNotEmpty ? updated : null;
    } catch (_) {
      return null; // 非关键步骤，失败不影响后续流程
    }
  }

  /// 第一步：检测是否需要 MFA（多因素认证）。
  Future<Response> detectMfa({
    required String username,
    required String password,
    required String fpVisitorId,
    required String referer,
    required String sessionCookie,
  }) async {
    const mfaUrl = 'https://ssl.jxufe.edu.cn/cas/mfa/detect';
    final headers = _ajaxHeaders(referer: referer);
    if (sessionCookie.isNotEmpty) headers['Cookie'] = sessionCookie;

    final response = await _dio.post(
      mfaUrl,
      options: Options(headers: headers),
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
    required String sessionCookie,
    String trustAgent = '',
  }) async {
    final headers = _formHeaders(referer: loginUrl);
    if (sessionCookie.isNotEmpty) headers['Cookie'] = sessionCookie;

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
      options: Options(headers: headers, followRedirects: false),
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
        '"Not;A=Brand";v="8", "Chromium";v="150", "Microsoft Edge";v="150"',
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"Windows"',
    'Upgrade-Insecure-Requests': '1',
    'Content-Type': 'application/x-www-form-urlencoded',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        ' (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36 Edg/150.0.0.0',
    'Origin': 'https://ssl.jxufe.edu.cn',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;'
        'q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,'
        'application/signed-exchange;v=b3;q=0.7',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Dest': 'document',
    'Referer': referer,
    'Accept-Encoding': 'gzip, deflate, br, zstd',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
  };
}
