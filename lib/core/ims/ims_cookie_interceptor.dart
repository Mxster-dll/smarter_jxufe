import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/ims/ims_session_manager.dart';

class ImsCookieInterceptor extends Interceptor {
  final ImsSessionManager _sessionManager;

  ImsCookieInterceptor(this._sessionManager);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['noAuth'] == true) {
      handler.next(options);
      return;
    }
    final jsessionId = _sessionManager.jSessionId;
    if (jsessionId != null) {
      options.headers['Cookie'] = 'JSESSIONID=$jsessionId';
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final setCookie = response.headers['set-cookie']?.first;
    if (setCookie != null) {
      final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(setCookie);
      final newId = match?.group(1);
      if (newId != null && newId != _sessionManager.jSessionId) {
        _sessionManager.saveJSessionId(newId); // 异步，但不等待
      }
    }
    handler.next(response);
  }
}
