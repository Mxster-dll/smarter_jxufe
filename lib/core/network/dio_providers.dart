import 'dart:convert';
import 'dart:io' show HttpClient;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:riverpod/riverpod.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/interceptors/ims_auth_interceptor.dart';

/// 当前登录账户卡号，切换账户时更新此值。
final currentAccountProvider = StateProvider<String>((ref) => '');

/// 全局 IMS 认证拦截器实例（所有账户共用同一个拦截器，
/// 因为 JSESSIONID 刷新逻辑不区分账户）。
final _imsAuthInterceptor = ImsAuthInterceptor();

/// 注入 JSESSIONID 刷新回调。
/// 应在 [ImsAuthRepository] 初始化完成后调用。
void setJsessionIdRefreshCallback(Future<String> Function() callback) {
  _imsAuthInterceptor.setRefreshCallback(callback);
}

/// 按账户卡号分例的 IMS Dio。
final imsDioProvider = Provider.family<Dio, String>((ref, account) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://jwxt.jxufe.edu.cn',
      followRedirects: false,
      validateStatus: (status) => true,
      headers: {
        'User-Agent': deviceProfileRepo.userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'sec-ch-ua':
            '"Not:A-Brand";v="99", "Microsoft Edge";v="145", "Chromium";v="145"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'Referer': 'http://ehall.jxufe.edu.cn/',
      },
      responseDecoder: (bytes, options, response) {
        final contentType = response.headers['Content-Type']?.first;
        final charset = _extractCharset(contentType);
        return switch (charset) {
          'gbk' || 'gb2312' => gbk.decode(bytes),
          _ => utf8.decode(bytes),
        };
      },
    ),
  );
  // 添加凭证失效自动重试拦截器
  dio.interceptors.add(_imsAuthInterceptor);
  // _applyFiddlerProxy(dio); // [DEBUG] 抓包用，发布前取消注释
  return dio;
});

/// 按账户卡号分例的 Login Dio。
final loginDioProvider = Provider.family<Dio, String>((ref, account) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://ssl.jxufe.edu.cn',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (status) => true,
      followRedirects: false,
      headers: {'User-Agent': deviceProfileRepo.userAgent},
    ),
  );
  // _applyFiddlerProxy(dio); // [DEBUG] 抓包用，发布前取消注释
  return dio;
});

/// 当前账户的 IMS Dio，由 [currentAccountProvider] 驱动。
final currentImsDioProvider = Provider<Dio>((ref) {
  final account = ref.watch(currentAccountProvider);
  return ref.watch(imsDioProvider(account));
});

/// 当前账户的 Login Dio，由 [currentAccountProvider] 驱动。
final currentLoginDioProvider = Provider<Dio>((ref) {
  final account = ref.watch(currentAccountProvider);
  return ref.watch(loginDioProvider(account));
});

String _extractCharset(String? contentType) {
  if (contentType == null) return '';
  final match = RegExp(
    r'charset=([^;]+)',
  ).firstMatch(contentType.toLowerCase());
  return match?.group(1)?.trim() ?? '';
}

/// [DEBUG] 将所有 Dio 请求代理到 Fiddler（127.0.0.1:8888），
/// 用于抓包调试。发布前删除此函数及其调用。
void _applyFiddlerProxy(Dio dio) {
  final adapter = dio.httpClientAdapter;
  if (adapter is IOHttpClientAdapter) {
    adapter.createHttpClient = () {
      final client = HttpClient();
      client.findProxy = (uri) => 'PROXY 127.0.0.1:8888';
      client.badCertificateCallback = (_, __, ___) => true;
      return client;
    };
  }
}
