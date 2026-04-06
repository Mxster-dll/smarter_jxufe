import 'package:dio/dio.dart';
import 'dart:async';

class LoginService {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://ssl.jxufe.edu.cn',
      validateStatus: (status) => true,
      followRedirects: false,
    ),
  );

  late final String _execution;
  String? _fpVisitorId;
  Future<void>? finishPreload;

  late String _account;
  late String _password;
  final gid =
      'S3lvSGM0NjRtSEtYcGhMcjZ2byszZnlGU0VkeXdGSTNOdllhckgyQVRaVnhhNi8zTUxRQ2hvWjhDbmlodWo1d0lVNGRzbDdqZ3hXU2FJYmxrK054TlE9PQ';

  // BUG 对单个账号未实现单例模式
  LoginService() {
    _dio.options.headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };
    preloadLoginPage();
  }

  void preloadLoginPage() => finishPreload ??= _getLoginPageInfo();

  void set(String account, String password) {
    _account = account;
    _password = password;
  }

  /// 获取登录页的 execution 等字段
  Future<void> _getLoginPageInfo() async {
    try {
      /// index.html: 获取主页源代码
      final response = await _dio.get(
        '/cas/login',
        queryParameters: {
          'service': 'http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess',
        },
      );

      final html = response.data as String;

      // _execution = RegExp(
      //   r'name="execution" value="([^"]+)"',
      // ).firstMatch(data)?.group(1)!;

      // _fpVisitorId = RegExp(
      //   r'name="fpVisitorId" value="([^"]+)"',
      // ).firstMatch(data)?.group(1)!;
    } catch (e) {
      throw Exception('获取登录页面失败: $e');
    }
  }

  Future<String> redirectImsUrl() async {
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
          'Cookie':
              'SESSION=03c4d9d5-c8d2-4fac-8d16-0f2c2b1cee1a; TGC=TGT-183166-kLVxBTYgwH8IOzz8NhXYatx3THeo8M-YSSKRgvpadt4tXZ7dItLwS5AfPDXKo7p12hscas-server-webapp-f656944b5-w4cqd; Hm_lvt_d605d8df6bf5ca8a54fe078683196518=1775387797,1775397037,1775466632,1775499134; Hm_lpvt_d605d8df6bf5ca8a54fe078683196518=1775499134; HMACCOUNT=FF9688FA59688706',
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
// import 'package:flutter/material.dart';
// import 'package:dio_cookie_manager/dio_cookie_manager.dart';
// import 'package:cookie_jar/cookie_jar.dart';
// import 'package:smarter_jxufe/Services/MfaService.dart';

// // 使用您的日志类
// import 'package:smarter_jxufe/Log.dart' as log;

// enum LoginState {
//   idle,
//   loading,
//   success,
//   error,
//   needCaptcha,
//   needMFA,
//   invalidCredentials,
//   networkError,
// }

// class JxufeLogin {
//   // 状态管理
//   LoginState _state = LoginState.idle;
//   String _errorMessage = '';
//   bool _needCaptcha = false;
//   String? _captchaImageUrl;
//   int _failCount = 0;

//   // CAS配置
//   final String _baseUrl = 'https://ssl.jxufe.edu.cn';
//   final String _casPath = '/cas';
//   String? _execution;
//   String? _publicKey;

//   // HTTP客户端
//   final Dio _dio;
//   final CookieJar _cookieJar;

//   // MFA服务接口（由外部注入）
//   final MfaService _mfaService;

//   // 状态访问器
//   LoginState get state => _state;
//   String get errorMessage => _errorMessage;
//   bool get isLoggedIn => _state == LoginState.success;
//   bool get needCaptcha => _needCaptcha;
//   String? get captchaImageUrl => _captchaImageUrl;
//   Map<String, String> get cookies => {}; // 需要从_cookieJar获取

//   JxufeLogin(MfaService mfaService)
//     : _dio = Dio(BaseOptions(baseUrl: 'https://ssl.jxufe.edu.cn')),
//       _cookieJar = CookieJar(),
//       _mfaService = mfaService {
//     _initDio();
//   }

//   void _initDio() {
//     _dio.options.baseUrl = _baseUrl;
//     _dio.options.connectTimeout = const Duration(seconds: 10);
//     _dio.options.receiveTimeout = const Duration(seconds: 10);

//     // 添加Cookie管理器
//     _dio.interceptors.add(CookieManager(_cookieJar));
//   }

//   Future<void> login({
//     required String username,
//     required String password,
//     required BuildContext context,
//     String? captcha,
//     bool rememberMe = false,
//   }) async {
//     try {
//       _setState(LoginState.loading);
//       _errorMessage = '';

//       // 1. 获取登录页面，解析execution
//       await _fetchLoginPage();

//       // 2. 获取RSA公钥
//       await _fetchPublicKey();

//       // 3. 加密密码
//       final encryptedPassword = _encryptPassword(password);

//       // 4. 设置MFA服务凭证
//       _mfaService.set(username, encryptedPassword);

//       // 5. 处理MFA验证
//       await _handleMfaVerification(context);

//       // 6. 提交登录表单
//       await _submitLoginForm(
//         username: username,
//         password: encryptedPassword,
//         captcha: captcha,
//         rememberMe: rememberMe,
//       );

//       _setState(LoginState.success);
//       log.logSuccess('登录成功');
//       _errorMessage = '';
//     } catch (e) {
//       _handleLoginError(e);
//     }
//   }

//   Future<void> _fetchLoginPage() async {
//     try {
//       final response = await _dio.get('$_casPath/login');

//       if (response.statusCode == 200) {
//         final html = response.data.toString();

//         // 解析execution参数
//         final regex = RegExp(r'name="execution" value="([^"]+)"');
//         final match = regex.firstMatch(html);
//         _execution = match?.group(1);

//         // 检查是否需要验证码
//         if (html.contains('captcha')) {
//           _needCaptcha = true;
//           _captchaImageUrl =
//               '$_baseUrl$_casPath/captcha.jpg?r=${DateTime.now().millisecondsSinceEpoch}';
//         }

//         log.logInfo('获取到execution: $_execution');
//       }
//     } catch (e) {
//       log.logError('获取登录页面失败: $e');
//       throw Exception('无法连接到登录服务器');
//     }
//   }

//   Future<void> _fetchPublicKey() async {
//     try {
//       final response = await _dio.get('$_casPath/jwt/publicKey');
//       if (response.statusCode == 200) {
//         _publicKey = response.data.toString().trim();
//         log.logInfo('获取到RSA公钥');
//       }
//     } catch (e) {
//       log.logWarning('获取公钥失败: $e');
//       _publicKey = null;
//     }
//   }

//   String _encryptPassword(String password) {
//     if (_publicKey == null || _publicKey!.isEmpty) {
//       log.logInfo('未获取到公钥，使用明文密码');
//       return password; // 不加密
//     }

//     try {
//       // RSA加密逻辑
//       // 注意：这里需要根据实际的RSA库实现
//       log.logInfo('使用RSA加密密码');
//       return '__RSA__${_publicKey!.length}'; // 简化示例
//     } catch (e) {
//       log.logError('密码加密失败: $e');
//       return password; // 返回明文
//     }
//   }

//   Future<void> _handleMfaVerification(BuildContext context) async {
//     try {
//       // 使用MfaService处理MFA验证
//       log.logInfo('开始MFA验证流程');
//       await _mfaService.process(context);
//       log.logSuccess('MFA验证成功');
//     } catch (e) {
//       if (e.toString().contains('需要MFA')) {
//         _setState(LoginState.needMFA);
//       }
//       log.logError('MFA验证失败: $e');
//       rethrow;
//     }
//   }

//   Future<void> _submitLoginForm({
//     required String username,
//     required String password,
//     String? captcha,
//     bool rememberMe = false,
//   }) async {
//     try {
//       final fingerprintId = await _getFingerprintId();

//       final response = await _dio.post(
//         '$_casPath/login',
//         data: {
//           'username': username,
//           'password': password,
//           'captcha': captcha ?? '',
//           'rememberMe': rememberMe ? 'on' : 'off',
//           'currentMenu': '1',
//           'failN': _failCount.toString(),
//           'mfaState': _mfaService.mfaState ?? '',
//           'execution': _execution ?? '',
//           '_eventId': 'submit',
//           'geolocation': '',
//           'fpVisitorId': fingerprintId ?? '',
//           'trustAgent': '',
//           'submit1': 'Login1',
//         },
//         options: Options(
//           contentType: 'application/x-www-form-urlencoded',
//           followRedirects: false,
//           validateStatus: (status) => status! < 500,
//         ),
//       );

//       // 处理响应
//       if (response.statusCode == 302) {
//         // 登录成功
//         final location = response.headers['location']?.first ?? '';
//         if (location.contains('ticket=')) {
//           log.logInfo('登录成功，重定向到: $location');
//           _failCount = 0;
//           await _saveCookies();
//         } else {
//           throw Exception('登录响应异常');
//         }
//       } else if (response.statusCode == 200) {
//         // 登录失败
//         _analyzeLoginError(response.data.toString());
//         _failCount++;

//         if (_failCount >= 3) {
//           _needCaptcha = true;
//           _captchaImageUrl =
//               '$_baseUrl$_casPath/captcha.jpg?r=${DateTime.now().millisecondsSinceEpoch}';
//         }

//         throw Exception(_errorMessage);
//       }
//     } catch (e) {
//       log.logError('提交登录表单失败: $e');
//       rethrow;
//     }
//   }

//   void _analyzeLoginError(String html) {
//     if (html.contains('账号或密码错误')) {
//       _setState(LoginState.invalidCredentials);
//       _errorMessage = '账号或密码错误';
//     } else if (html.contains('验证码错误')) {
//       _setState(LoginState.error);
//       _errorMessage = '验证码错误';
//     } else {
//       _setState(LoginState.error);
//       _errorMessage = '登录失败，请重试';
//     }
//     log.logWarning('登录失败: $_errorMessage');
//   }

//   Future<String?> _getFingerprintId() async {
//     // 简化的设备指纹
//     try {
//       return 'flutter_${DateTime.now().millisecondsSinceEpoch}';
//     } catch (e) {
//       log.logWarning('生成设备指纹失败: $e');
//       return null;
//     }
//   }

//   Future<void> _saveCookies() async {
//     try {
//       final uri = Uri.parse('$_baseUrl$_casPath');
//       final savedCookies = await _cookieJar.loadForRequest(uri);

//       log.logInfo('保存了 ${savedCookies.length} 个Cookie');
//     } catch (e) {
//       log.logError('保存Cookie失败: $e');
//     }
//   }

//   void _handleLoginError(dynamic error) {
//     if (_state == LoginState.needMFA) {
//       _errorMessage = '需要双因子认证，请完成验证';
//     } else if (error is DioException) {
//       if (error.type == DioExceptionType.connectionTimeout ||
//           error.type == DioExceptionType.receiveTimeout) {
//         _setState(LoginState.networkError);
//         _errorMessage = '连接超时，请检查网络';
//       } else {
//         _setState(LoginState.error);
//         _errorMessage = error.toString();
//       }
//     } else {
//       _setState(LoginState.error);
//       _errorMessage = error.toString();
//     }

//     log.logError('登录错误: $error');
//   }

//   void _setState(LoginState newState) {
//     _state = newState;
//     log.logInfo('登录状态变更: $newState');
//   }

//   // 刷新验证码
//   Future<void> refreshCaptcha() async {
//     try {
//       _captchaImageUrl =
//           '$_baseUrl$_casPath/captcha.jpg?r=${DateTime.now().millisecondsSinceEpoch}';
//       log.logInfo('验证码已刷新');
//     } catch (e) {
//       log.logError('刷新验证码失败: $e');
//     }
//   }

//   // 重置状态
//   void reset() {
//     _setState(LoginState.idle);
//     _errorMessage = '';
//     _needCaptcha = false;
//     _captchaImageUrl = null;
//     _failCount = 0;
//     _execution = null;
//     _publicKey = null;

//     // 清理MFA服务
//     // _mfaService.dispose();

//     // 清理Cookie
//     _cookieJar.deleteAll();

//     log.logInfo('登录服务已重置');
//   }

//   // 登出
//   Future<void> logout() async {
//     try {
//       await _dio.get('$_casPath/logout');
//       reset();
//       log.logSuccess('登出成功');
//     } catch (e) {
//       log.logError('登出失败: $e');
//       reset(); // 无论如何重置本地状态
//     }
//   }

//   // 检查登录状态
//   Future<bool> checkLoginStatus() async {
//     try {
//       final response = await _dio.get('$_casPath/validate');
//       final isLoggedIn = response.statusCode == 200;
//       if (isLoggedIn) {
//         log.logSuccess('登录状态有效');
//       } else {
//         log.logWarning('登录状态无效');
//       }
//       return isLoggedIn;
//     } catch (e) {
//       log.logError('检查登录状态失败: $e');
//       return false;
//     }
//   }

//   // 获取当前存储的Cookie
//   Future<Map<String, String>> _getCookiesMap() async {
//     try {
//       final uri = Uri.parse('$_baseUrl$_casPath');
//       final savedCookies = await _cookieJar.loadForRequest(uri);

//       final Map<String, String> cookies = {};
//       for (var cookie in savedCookies) {
//         cookies[cookie.name] = cookie.value;
//       }

//       return cookies;
//     } catch (e) {
//       log.logError('获取Cookie失败: $e');
//       return {};
//     }
//   }
// }
