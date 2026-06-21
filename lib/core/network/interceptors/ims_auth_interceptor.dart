import 'package:dio/dio.dart';

class ImsAuthInterceptor extends Interceptor {
  Future<String> Function()? _refreshCallback;

  void setRefreshCallback(Future<String> Function() callback) {
    _refreshCallback = callback;
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final data = response.data;
    if (data is String && data.contains('凭证失效')) {
      _handleRetry(response, handler);
      return;
    }
    handler.next(response);
  }

  Future<void> _handleRetry(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final extra = response.requestOptions.extra;
    final retryCount = (extra['_ims_retry_count'] as int?) ?? 0;

    if (retryCount >= 1 || _refreshCallback == null) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: '凭证已失效，请重新登录',
        ),
      );
      return;
    }

    try {
      final newJsessionId = await _refreshCallback!();

      final headers = <String, dynamic>{...?response.requestOptions.headers};
      final oldCookie = (headers['Cookie'] ?? '').toString();
      final newCookie = _replaceJsessionId(oldCookie, newJsessionId);
      headers['Cookie'] = newCookie;

      final newOptions = response.requestOptions.copyWith(
        headers: headers,
        extra: {...extra, '_ims_retry_count': retryCount + 1},
      );

      final retryResponse = await Dio().fetch(newOptions);
      handler.resolve(retryResponse);
    } on DioException {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: '凭证已失效，请重新登录',
        ),
      );
    } catch (_) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: '凭证已失效，请重新登录',
        ),
      );
    }
  }

  String _replaceJsessionId(String cookie, String newId) {
    if (cookie.contains('JSESSIONID=')) {
      return cookie.replaceAll(
        RegExp(r'JSESSIONID=[^;]+'),
        'JSESSIONID=$newId',
      );
    }
    final separator = cookie.isNotEmpty && !cookie.endsWith(';') ? ';' : '';
    return '$cookie$separator JSESSIONID=$newId';
  }
}
