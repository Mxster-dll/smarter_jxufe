import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 调试代理配置。
///
/// 将 [enabled] 设为 `true` 即可将所有 Dio 请求路由到
/// `127.0.0.1:8888`（如 Fiddler / Charles / mitmproxy）。
///
/// ⚠️ 仅供调试使用，发布前务必将 [enabled] 改回 `false`。
const _proxyEnabled = true;
const _proxyHost = '127.0.0.1';
const _proxyPort = 8888;

/// 创建一个配置了代理的 [HttpClientAdapter]。
///
/// 当 [_proxyEnabled] 为 `false` 时返回 `null`，
/// 调用方可将返回值的非空判断作为是否设置代理的依据。
HttpClientAdapter? createProxyAdapter() {
  if (!_proxyEnabled) return null;

  final httpClient = HttpClient();

  httpClient.findProxy = (uri) => 'PROXY $_proxyHost:$_proxyPort';

  // 调试用：信任代理的 HTTPS 证书（如 Fiddler 根证书）
  httpClient.badCertificateCallback = (cert, host, port) => true;

  return IOHttpClientAdapter(createHttpClient: () => httpClient);
}
