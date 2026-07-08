import 'package:dio/dio.dart';

/// IMS 教务系统 Dio 拦截器 —— 自动检测"凭证失效"并刷新 JSESSIONID 重试。
///
/// 用法：
/// 1. 创建拦截器实例并添加到 IMS Dio
/// 2. 在 [ImsAuthRepository] 初始化后调用 [setRefreshCallback] 注入刷新函数
/// 3. 后续所有 IMS 请求若响应体包含"凭证失效"，拦截器会自动刷新重试一次
class ImsAuthInterceptor extends Interceptor {
  /// 用于刷新 JSESSIONID 的回调，由外部注入。
  Future<String> Function()? _refreshCallback;

  /// 发起请求的 Dio 实例，用于重试时保留原始配置（GBK 解码器等）。
  Dio _dio = Dio();

  /// 更新重试用的 Dio 实例（当账户切换需重建 Dio 时调用）。
  void setDio(Dio dio) {
    _dio = dio;
  }

  /// 注入刷新回调。应在 [ImsAuthRepository] 初始化完成后立即调用。
  void setRefreshCallback(Future<String> Function() callback) {
    _refreshCallback = callback;
  }

  /// IMS 服务端返回的凭证失效提示前缀（精确匹配）。
  static const _expiredPrefix = "<script>alert('温馨提示：凭证已失效，请重新登录!');";

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final data = response.data;
    if (data is String && data.startsWith(_expiredPrefix)) {
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

    // 已达最大重试次数（3 次）或未注入刷新回调，直接拒绝
    if (retryCount >= 3 || _refreshCallback == null) {
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
      // 刷新 JSESSIONID
      final newJsessionId = await _refreshCallback!();

      // 更新 Cookie 头中的 JSESSIONID
      final headers = <String, dynamic>{...?response.requestOptions.headers};
      final oldCookie = (headers['Cookie'] ?? '').toString();
      final newCookie = _replaceJsessionId(oldCookie, newJsessionId);
      headers['Cookie'] = newCookie;

      // 构造新请求选项。
      // 将 _ims_retry_count 设为 999 防止重试响应再次被本拦截器拦截。
      final newOptions = response.requestOptions.copyWith(
        headers: headers,
        extra: {...extra, '_ims_retry_count': 999},
      );

      // 使用同一个 Dio 实例发起重试（保留 GBK 解码器等原始配置）。
      // _ims_retry_count=999 保证重试响应不会再进入 _handleRetry。
      final retryResponse = await _dio.fetch(newOptions);
      handler.resolve(retryResponse);
    } on DioException {
      // 重试本身也失败了
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

  /// 将 Cookie 字符串中的 JSESSIONID 替换为新值；若不存在则追加。
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
