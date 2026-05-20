import 'package:dio/dio.dart';

class AuthRemoteDataSource {
  final Dio _dio;

  AuthRemoteDataSource(this._dio);

  /// 第一步：检测是否需要 MFA（多因素认证），返回 state 参数
  Future<String> detectMfa({
    required String username,
    required String password,
    required String fpVisitorId,
  }) async {
    const url = 'https://ssl.jxufe.edu.cn/cas/mfa/detect';
    final headers = {
      'Host': 'ssl.jxufe.edu.cn',
      'Connection': 'keep-alive',
      'sec-ch-ua-platform': '"Windows"',
      'X-Requested-With': 'XMLHttpRequest',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0',
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'sec-ch-ua':
          '"Chromium";v="148", "Microsoft Edge";v="148", "Not/A)Brand";v="99"',
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'sec-ch-ua-mobile': '?0',
      'Origin': 'https://ssl.jxufe.edu.cn',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Dest': 'empty',
      'Referer':
          'https://ssl.jxufe.edu.cn/cas/login?service=http%3A%2F%2Fehall.jxufe.edu.cn%2Famp-auth-adapter%2FloginSuccess%3FsessionToken%3DTESTSESSIONTOKEN0000000000000002',
      'Accept-Encoding': 'gzip, deflate, br, zstd',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
    };

    final body = {
      'username': username,
      'password': password,
      'fpVisitorId': fpVisitorId,
    };

    final response = await _dio.post(
      url,
      options: Options(headers: headers),
      data: body,
    );

    if (response.statusCode != 200) {
      throw Exception('MFA detection failed: ${response.statusCode}');
    }

    final json = response.data;
    if (json['code'] != 0) {
      throw Exception('MFA detection error: ${json['code']}');
    }

    final state = json['data']['state'] as String;
    return state;
  }

  /// 第二步：提交登录，返回 TGC Cookie 值
  Future<String> login({
    required String username,
    required String password,
    required String fpVisitorId,
    required String mfaState,
  }) async {
    const url =
        'https://ssl.jxufe.edu.cn/cas/login?service=http%3A%2F%2Fehall.jxufe.edu.cn%2Famp-auth-adapter%2FloginSuccess%3FsessionToken%3DTESTSESSIONTOKEN0000000000000002';
    final headers = {
      'Host': 'ssl.jxufe.edu.cn',
      'Connection': 'keep-alive',
      'Cache-Control': 'max-age=0',
      'sec-ch-ua':
          '"Chromium";v="148", "Microsoft Edge";v="148", "Not/A)Brand";v="99"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
      'Upgrade-Insecure-Requests': '1',
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0',
      'Origin': 'https://ssl.jxufe.edu.cn',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-User': '?1',
      'Sec-Fetch-Dest': 'document',
      'Referer':
          'https://ssl.jxufe.edu.cn/cas/login?service=http%3A%2F%2Fehall.jxufe.edu.cn%2Famp-auth-adapter%2FloginSuccess%3FsessionToken%3DTESTSESSIONTOKEN0000000000000002',
      'Accept-Encoding': 'gzip, deflate, br, zstd',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
    };

    // 固定参数（实际应从登录页面预请求获取，此处为示例）
    const execution =
        '<REDACTED_EXECUTION>';
    const eventId = 'submit';
    const geolocation = '';
    const trustAgent = '';
    const submit1 = 'Login1';

    final body = {
      'username': username,
      'password': password,
      'captcha': '',
      'currentMenu': '1',
      'failN': '0',
      'mfaState': mfaState,
      'execution': execution,
      '_eventId': eventId,
      'geolocation': geolocation,
      'fpVisitorId': fpVisitorId,
      'trustAgent': trustAgent,
      'submit1': submit1,
    };

    final response = await _dio.post(
      url,
      options: Options(
        headers: headers,
        followRedirects: false, // 不自动跟随重定向，以便获取 Location 和 Set-Cookie
      ),
      data: body,
    );

    // 登录成功应返回 302 重定向
    if (response.statusCode != 302) {
      throw Exception('Login failed: expected 302, got ${response.statusCode}');
    }

    final cookies = response.headers['set-cookie'];
    if (cookies == null || cookies.isEmpty) {
      throw Exception('No Set-Cookie header found');
    }

    // 查找 TGC cookie
    for (var cookie in cookies) {
      final parts = cookie.split(';');
      for (var part in parts) {
        final trimmed = part.trim();
        if (trimmed.startsWith('TGC=')) {
          return trimmed.substring(4); // 返回 TGC 值（不含“TGC=”前缀）
        }
      }
    }

    throw Exception('TGC cookie not found in Set-Cookie');
  }

  Future<String> getRedirectImsUrl(String token) async {
    final response = await _dio.get(
      'https://ssl.jxufe.edu.cn/cas/login?service=https%3A%2F%2Fjwxt.jxufe.edu.cn%2F%2Fjxcjcaslogin',
      options: Options(
        headers: {
          'Host': 'ssl.jxufe.edu.cn',
          'Connection': 'keep-alive',
          'Upgrade-Insecure-Requests': '1',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
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
          'Cookie': 'TGC=$token; ',
        },
        followRedirects: false,
      ),
    );

    final location = response.headers.value('location');
    if (location == null) throw Exception('location == null\n${response.data}');
    // 这里报错要考虑是不是统一登录的 Cookie 过期了

    return location;
  }
}
