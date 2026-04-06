import 'package:dio/dio.dart';

class ImsAuthRemoteDataSource {
  final Dio _dio;

  ImsAuthRemoteDataSource(this._dio);

  Future<String> fetchJSessionId(String gid) async {
    final queryParameters = {
      't_s': DateTime.now().millisecondsSinceEpoch,
      'amp_sec_version_': '1',
      'gid_': gid,
      'EMAP_LANG': 'zh',
      'THEME': 'cherry',
    };
    final response = await _dio.get(
      '/jxcjcaslogin',
      queryParameters: queryParameters,
      options: Options(extra: {'noAuth': true}),
    );
    final setCookie = response.headers['set-cookie']?.first;
    if (setCookie == null) throw Exception('No Set-Cookie header');
    final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(setCookie);
    return match?.group(1) ?? (throw Exception('JSESSIONID not found'));
  }
}
