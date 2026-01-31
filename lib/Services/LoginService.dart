import 'package:dio/dio.dart';
import 'dart:async';

class LoginService {
  final Dio _dio = Dio();

  static const baseUrl = 'https://ssl.jxufe.edu.cn';

  String? _execution;
  String? _fpVisitorId;
  Future<void>? _futureLoginPageInfo;

  late String _account;
  late String _password;

  LoginService() {
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
    preloadLoginPage();
  }

  void preloadLoginPage() => _futureLoginPageInfo ??= _getLoginPageInfo();

  void set(String account, String password) {
    _account = account;
    _password = password;
  }

  /// 获取登录页的 execution 和 fpVisitorId 字段
  Future<void> _getLoginPageInfo() async {
    try {
      /// index.html: 获取主页源代码
      final response = await _dio.get(
        '$baseUrl/cas/login',
        queryParameters: {
          'service': 'http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess',
        },
      );

      final data = response.data as String;

      _execution = RegExp(
        r'name="execution" value="([^"]+)"',
      ).firstMatch(data)?.group(1)!;

      _fpVisitorId = RegExp(
        r'name="fpVisitorId" value="([^"]+)"',
      ).firstMatch(data)?.group(1)!;
    } catch (e) {
      throw Exception('获取登录页面失败: $e');
    }
  }
}
