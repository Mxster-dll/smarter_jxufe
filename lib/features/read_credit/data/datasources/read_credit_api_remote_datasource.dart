/// 阅读学分平台业务数据源（学分查询页 + 明细页，均为服务端渲染 HTML）。
library;

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/core/network/cas_redirect.dart';
import 'package:smarter_jxufe/features/read_credit/data/anti_corruption/read_credit_parser.dart';
import 'package:smarter_jxufe/features/read_credit/data/datasources/read_credit_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';

/// 阅读学分平台业务请求失败。
class ReadCreditApiException extends AppException {

  const ReadCreditApiException(super.message);
}

/// 业务数据源：带会话 Cookie 取页面并交给解析器。
class ReadCreditApiRemoteDataSource {
  final Dio _dio;

  const ReadCreditApiRemoteDataSource(this._dio);

  static const String scorePath = '/Web/ReadMain/Score';

  /// 学分查询页。
  Future<ReadCreditScore> fetchScore(String cookie) async =>
      parseReadCreditScore(await _html(scorePath, cookie));

  /// 某一项的明细表。
  Future<ReadCreditDetail> fetchDetail(
    String cookie,
    ReadCreditKind kind,
  ) async => parseReadCreditDetail(await _html(kind.detailPath, cookie), kind);

  Future<String> _html(String path, String cookie) async {
    final response = await _dio.get<dynamic>(
      path,
      options: Options(
        followRedirects: false,
        validateStatus: (status) => true,
        headers: {
          'Cookie': cookie,
          'Referer': '${ReadCreditAuthRemoteDataSource.origin}$scorePath',
        },
      ),
    );
    final status = response.statusCode ?? 0;
    final location = response.headers.value('location') ?? '';
    final body = response.data?.toString() ?? '';
    if (status >= 300 && status < 400) {
      // 会话失效时平台一律 302 回 CASLogin(再 302 到统一认证)。
      // CASLogin 是平台私有入口（保留本标记），学校 CAS 走共用判据。
      if (location.contains('CASLogin') || isCasLoginRedirect(location)) {
        throw ReadCreditSessionExpiredException(
          '阅读学分平台会话已失效(HTTP $status)，已尝试刷新',
        );
      }
      throw ReadCreditApiException('请求被重定向(HTTP $status)→$location');
    }
    if (status != 200) {
      throw ReadCreditApiException('阅读学分平台请求失败(HTTP $status)');
    }
    if (body.trim().isEmpty) {
      throw const ReadCreditApiException('阅读学分平台返回空页面');
    }
    return body;
  }
}
