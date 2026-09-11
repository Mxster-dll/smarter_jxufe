import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fast_gbk/fast_gbk.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository.dart';
import 'package:smarter_jxufe/core/network/interceptors/ims_auth_interceptor.dart';

/// IMS（教务 `jwxt.jxufe.edu.cn`）Dio 的**唯一构造入口**。
///
/// 返回 Dio 与其专属的凭证失效拦截器：
/// - 拦截器随 Dio 创建，**不再用全局单例 + `setDio`**——那样在多账户并存时
///   后建的 Dio 会覆盖重试用的 Dio，把重试发到别人的会话上；
/// - 调用方拿到后必须 `interceptor.setRefreshCallback(session.renew)`
///   （见 `features/ims/auth/data/providers/ims_session_provider.dart`）。
///
/// 全局只应存在一个 IMS Dio（由 `ImsSession` 持有）；除了别处确有需要的
/// 无会话场景（如桌面小组件后台），不要重复创建。
({Dio dio, ImsAuthInterceptor interceptor}) createImsDio(
  DeviceProfileRepository deviceProfileRepo,
) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://jwxt.jxufe.edu.cn',
      followRedirects: false,
      // 教务接口偶发挂起：必须给足超时，否则请求会无限转圈
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
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
        final charset = extractCharset(contentType);
        return switch (charset) {
          'gbk' || 'gb2312' => gbk.decode(bytes),
          _ => utf8.decode(bytes),
        };
      },
    ),
  );
  final interceptor = ImsAuthInterceptor(dio: dio);
  dio.interceptors.add(interceptor);
  // applyFiddlerProxy(dio); // [DEBUG] 抓包用，发布前取消注释
  return (dio: dio, interceptor: interceptor);
}

/// 从 `Content-Type` 中取 charset（小写、去空白）。
String extractCharset(String? contentType) {
  if (contentType == null) return '';
  final match = RegExp(
    r'charset=([^;]+)',
  ).firstMatch(contentType.toLowerCase());
  return match?.group(1)?.trim() ?? '';
}

/// [DEBUG] 将所有 Dio 请求代理到 Fiddler（127.0.0.1:8888），
/// 用于抓包调试。发布前删除此函数及其调用。
void applyFiddlerProxy(Dio dio) {
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
