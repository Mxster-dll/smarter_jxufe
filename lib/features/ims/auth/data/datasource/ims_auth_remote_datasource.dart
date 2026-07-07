import 'package:dio/dio.dart';

class ImsAuthRemoteDataSource {
  final Dio _dio;

  ImsAuthRemoteDataSource(this._dio);

  /// 获取 JSESSIONID。
  ///
  /// 直接请求 IMS 的 `/jxcjcaslogin` 端点。
  /// [gid] 为 AMP 客户端标识符，优先使用从 CAS 重定向 URL 中提取的值，
  /// 提取失败时回退到内置默认值。
  Future<String> fetchJsessionId({String? gid}) async {
    // 内置默认值，作为无法从服务端提取时的回退
    const defaultGid =
        'S3lvSGM0NjRtSEtYcGhMcjZ2byszZnlGU0VkeXdGSTNOdllhckgy'
        'QVRaVnhhNi8zTUxRQ2hvWjhDbmlodWo1d0lVNGRzbDdqZ3hXU2FJ'
        'YmxrK054TlE9PQ';

    final queryParameters = {
      't_s': DateTime.now().millisecondsSinceEpoch,
      'amp_sec_version_': '1',
      'gid_': gid ?? defaultGid,
      'EMAP_LANG': 'zh',
      'THEME': 'cherry',
    };

    final response = await _dio.get(
      '/jxcjcaslogin',
      queryParameters: queryParameters,
      options: Options(
        followRedirects: false,
        validateStatus: (status) => true,
      ),
    );

    final setCookie = response.headers['set-cookie'];
    if (setCookie == null || setCookie.isEmpty) {
      throw Exception('Missing set-cookie header');
    }

    final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(setCookie.first);
    final jsessionId = match?.group(1);
    if (jsessionId == null) throw Exception('JSESSIONID not found');
    return jsessionId;
  }
}
