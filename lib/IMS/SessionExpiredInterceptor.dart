import 'package:dio/dio.dart';
import 'package:smarter_jxufe/utils/Log.dart';

class SessionExpiredInterceptor extends Interceptor {
  final Dio _dio;
  final int _maxRetries;
  final Future<String?> Function() _onSessionExpired;

  SessionExpiredInterceptor(
    this._dio, {
    int maxRetries = 2,
    required Future<String?> Function() onSessionExpired,
  }) : _maxRetries = maxRetries,
       _onSessionExpired = onSessionExpired;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (response.data.toString().contains(
      "<script>alert('温馨提示：凭证已失效，请重新登录!');if (window.frmbody){  window.top.location.href='/'; } else if (window.parent.frmbody) {  window.parent.top.location.href='/'; } else if (window.parent.parent.frmbody) {  window.parent.parent.top.location.href='/'; }else if (window.parent.parent.parent.frmbody) {  window.parent.parent.parent.top.location.href='/'; } else if (window.parent.parent.parent.parent.frmbody) {  window.parent.parent.parent.parent.top.location.href='/'; } else { window.top.location.href='/'; }</script>",
    )) {
      final RequestOptions requestOptions = response.requestOptions;

      int retryCount = requestOptions.extra['retryCount'] ?? 0;

      if (retryCount < _maxRetries) {
        logInfo('正在重试: $retryCount');
        try {
          final jSessionId = await _onSessionExpired();

          final newOptions = requestOptions.copyWith(
            headers: {
              ...requestOptions.headers,
              'Cookie': 'JSESSIONID=$jSessionId',
            },
            extra: {...requestOptions.extra, 'retryCount': retryCount + 1},
          );

          final retryResponse = await _dio.fetch<dynamic>(newOptions);
          return handler.next(retryResponse);
        } catch (e) {
          return handler.reject(
            DioException(requestOptions: requestOptions, error: '重试失败: $e'),
          );
        }
      } else {
        logError('重试超出最大次数限制');
      }
    }
    return handler.next(response);
  }
}
