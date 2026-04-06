import 'package:dio/dio.dart';

class LoginRemoteDataSource {
  final Dio _dio;
  String? _execution;
  String? _fpVisitorId;

  // 固定的 gid（从原 LoginService 中获取）
  static const String gid =
      'S3lvSGM0NjRtSEtYcGhMcjZ2byszZnlGU0VkeXdGSTNOdllhckgyQVRaVnhhNi8zTUxRQ2hvWjhDbmlodWo1d0lVNGRzbDdqZ3hXU2FJYmxrK054TlE9PQ';

  LoginRemoteDataSource(this._dio);

  /// 预加载登录页面，获取 execution 和 fpVisitorId
  Future<void> preloadLoginPage() async {
    try {
      final response = await _dio.get(
        '/cas/login',
        queryParameters: {
          'service': 'http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess',
        },
      );
      final html = response.data as String;
      _execution = RegExp(
        r'name="execution" value="([^"]+)"',
      ).firstMatch(html)?.group(1);
      _fpVisitorId = RegExp(
        r'name="fpVisitorId" value="([^"]+)"',
      ).firstMatch(html)?.group(1);
      if (_execution == null) throw Exception('execution not found');
    } catch (e) {
      throw Exception('获取登录页面失败: $e');
    }
  }

  /// 提交用户名密码完成登录，返回重定向地址
  Future<String> login(String username, String password) async {
    // 确保预加载完成
    await preloadLoginPage();

    final data = {
      'username': username,
      'password': password,
      'execution': _execution,
      '_eventId': 'submit',
      'geolocation': '',
    };
    if (_fpVisitorId != null) {
      data['fpVisitorId'] = _fpVisitorId;
    }

    final response = await _dio.post(
      '/cas/login',
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
      ),
    );

    final location = response.headers.value('location');
    if (location == null) throw Exception('登录失败，无重定向');
    return location;
  }

  /// 从重定向地址中获取 JSESSIONID
  Future<String> getJSessionIdFromRedirect(String redirectUrl) async {
    final response = await _dio.get(
      redirectUrl,
      options: Options(followRedirects: false),
    );
    final setCookie = response.headers['set-cookie']?.first;
    if (setCookie == null) throw Exception('No Set-Cookie header');
    final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(setCookie);
    return match?.group(1) ?? (throw Exception('JSESSIONID not found'));
  }

  /// 原 redirectImsUrl 方法（可能用于其他场景）
  Future<String> redirectImsUrl() async {
    final response = await _dio.get(
      '/cas/login?service=https%3A%2F%2Fjwxt.jxufe.edu.cn%2F%2Fjxcjcaslogin',
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
          'Cookie':
              'SESSION=244ba8d5-8a24-49f6-90c1-0bf389761d4a; TGC=TGT-45663-PxwfpV5N0g0Chf0-Fj4PhGhLen0M4OHUntn8-ZEHYcGCa0AdnHji3NCaTX-rDDo-ukocas-server-webapp-f656944b5-ssctk; Hm_lvt_d605d8df6bf5ca8a54fe078683196518=1772443218,1772602433,1772688787,1772707913; HMACCOUNT=FF9688FA59688706; Hm_lpvt_d605d8df6bf5ca8a54fe078683196518=1772857139',
        },
        followRedirects: false,
      ),
    );
    final location = response.headers.value('location');
    if (location == null) throw Exception('location == null');
    return location;
  }
}
