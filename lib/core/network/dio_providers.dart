import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:riverpod/riverpod.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/interceptors/ims_auth_interceptor.dart';

final currentAccountProvider = StateProvider<String>((ref) => '');

final _imsAuthInterceptor = ImsAuthInterceptor();

void setJsessionIdRefreshCallback(Future<String> Function() callback) {
  _imsAuthInterceptor.setRefreshCallback(callback);
}

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
  dio.interceptors.add(_imsAuthInterceptor);
  return dio;
});

final loginDioProvider = Provider.family<Dio, String>((ref, account) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return Dio(
    BaseOptions(
      baseUrl: 'https://ssl.jxufe.edu.cn',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (status) => true,
      followRedirects: false,
      headers: {'User-Agent': deviceProfileRepo.userAgent},
    ),
  );
});

final currentImsDioProvider = Provider<Dio>((ref) {
  final account = ref.watch(currentAccountProvider);
  return ref.watch(imsDioProvider(account));
});

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
