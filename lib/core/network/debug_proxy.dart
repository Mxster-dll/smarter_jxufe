import 'dart:io' show HttpClient;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 抓包代理开关（**编译期常量，默认关闭**）。
///
/// 开启方式：`flutter run -d windows --dart-define=FIDDLER_PROXY=true`
/// （Fiddler 监听 `127.0.0.1:8888`）。
///
/// 从前这里写的是「`// applyFiddlerProxy(dio);` + 发布前取消注释」—— 那是靠人肉
/// 记忆的发布闸门：忘了取消注释只是抓不到包，忘了注释回去却会把代理与
/// `badCertificateCallback` 一起打进正式包。改成 `bool.fromEnvironment` 之后，
/// **不传 define 就是关**，而且编译器能把整段 tree-shake 掉。
const bool kFiddlerProxyEnabled = bool.fromEnvironment('FIDDLER_PROXY');

/// 把 Dio 的请求代理到 Fiddler（`127.0.0.1:8888`），仅供抓包调试。
///
/// ⚠ 它会同时放行**任意**证书（`badCertificateCallback => true`），因此只允许在
/// [kFiddlerProxyEnabled] 为真时调用，不要在业务代码里直接调它。
void applyFiddlerProxy(Dio dio) {
  final adapter = dio.httpClientAdapter;
  if (adapter is IOHttpClientAdapter) {
    adapter.createHttpClient = () {
      final client = HttpClient();
      client.findProxy = (uri) => 'PROXY 127.0.0.1:8888';
      client.badCertificateCallback = (_, _, _) => true;
      return client;
    };
  }
}
