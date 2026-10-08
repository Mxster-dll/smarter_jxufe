import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';

/// 「任何状态码都算成功」——校园站点抓取这一族的**统一口径**。
///
/// 这些接口大量拿 302 / 404 / 500 承载业务语义（会话失效、无数据、要重新换证），
/// 必须由调用方自己看状态码与正文；若让 Dio 直接抛 `DioException`，
/// 「未登录」和「网络不通」就混成同一个错误了。
bool acceptAnyStatus(int? status) => true;

/// **Dio 自己的默认判据**（仅 2xx 算成功，其余抛 `DioException`）。
///
/// 给「就是要让非 2xx 抛异常」的调用方用——[createAppDio] 的默认是
/// [acceptAnyStatus]（校园站点口径），需要严格语义时必须**显式**传这个，
/// 别自己去写 `status >= 200 && status < 300`（口径会漂）。
bool rejectNon2xxStatus(int? status) =>
    status != null && status >= 200 && status < 300;

/// 从 `Content-Type` 中取 charset（小写、去空白、**剥掉引号**）。
///
/// 教务一族用 [gbkAwareResponseDecoder] 判 GBK 时的唯一出处。
///
/// ⚠ `charset="gbk"` 这种带引号的写法现实中就有（HTTP 头里字符串可以是 quoted）：
/// 原先三份手写实现（ims / 校历 / 桌面小组件）都不剥引号 → 值变成 `"gbk"` →
/// 落进 `_`（UTF-8）分支 → 整页乱码。这里一并修掉。
String extractCharset(String? contentType) {
  if (contentType == null) return '';
  final match = RegExp(
    r'charset=([^;]+)',
  ).firstMatch(contentType.toLowerCase());
  final raw = match?.group(1)?.trim() ?? '';
  if (raw.length >= 2 &&
      (raw.startsWith('"') || raw.startsWith("'")) &&
      raw.endsWith(raw[0])) {
    return raw.substring(1, raw.length - 1).trim();
  }
  return raw;
}

/// GBK / GB2312 感知的响应解码器。
///
/// 教务（`jwxt`）、校历、桌面小组件后台的正文是 GBK，而 `dart:convert` 只认 UTF-8
/// —— 不换解码器就是满屏乱码。三处原先各写一份（含各自的 charset 正则），
/// 2026-10-08 收到这里。
///
/// [allowMalformed] 供「字节可能被截断」的场景（后台小组件）用：那时宁可留
/// 替换字符，也不要为了一个坏字节把整次请求判失败。
ResponseDecoder gbkAwareResponseDecoder({bool allowMalformed = false}) =>
    (bytes, options, response) {
      final charset = extractCharset(response.headers['Content-Type']?.first);
      return switch (charset) {
        'gbk' || 'gb2312' => gbk.decode(bytes),
        _ => utf8.decode(bytes, allowMalformed: allowMalformed),
      };
    };

/// 全应用 **Dio 的唯一构造入口**（唯一例外 = AI 客户端，理由见
/// `test/dio_factory_test.dart` 的白名单）。
///
/// 2026-10-08 收敛了 23 处手写 `Dio(BaseOptions(...))`。默认值刻意对齐
/// 「校园站点抓取」的多数派，**少数派一律显式传参**（这样差异在调用点一眼可见）：
/// - [validateStatus] 默认 [acceptAnyStatus]（见上）；
/// - [followRedirects] 默认 **true**（Dio 自己的默认值）；只有需要逐跳看
///   `Set-Cookie` 的换证链（CAS）才传 false；
/// - 超时默认 12s / 20s（用得最多的一档）。
Dio createAppDio({
  String? baseUrl,
  String userAgent = '',
  Map<String, String> headers = const <String, String>{},
  Duration connectTimeout = const Duration(seconds: 12),
  Duration receiveTimeout = const Duration(seconds: 20),
  Duration? sendTimeout,
  bool followRedirects = true,
  ValidateStatus validateStatus = acceptAnyStatus,
  ResponseType responseType = ResponseType.json,
  ResponseDecoder? responseDecoder,
}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? '',
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      followRedirects: followRedirects,
      validateStatus: validateStatus,
      responseType: responseType,
      responseDecoder: responseDecoder,
      // `User-Agent` 排在最前（与原手写 map 的顺序一致），其余按调用方给的顺序。
      headers: {
        if (userAgent.isNotEmpty) 'User-Agent': userAgent,
        ...headers,
      },
    ),
  );
}
