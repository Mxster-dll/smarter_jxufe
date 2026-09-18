import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/ims/grades/domain/transcript_report.dart';

/// 本科生成绩单接口异常（message 面向 UI 直显，服务端 message 优先）。
class TranscriptApiException implements Exception {
  final String message;

  const TranscriptApiException(this.message);

  @override
  String toString() => message;
}

/// 智慧江财「本科生成绩单」数据源（门户 H5 `layuiApp` 域）。
///
/// 认证链与网费同款：平台 GUID → `checkAppAuth` 换**加密账号 enc**（appid 1741570971384）
/// → 业务接口。⚠ H5 在发请求前会 `encodeURIComponent(enc)`（enc 里含 `+` / `=`），
/// 所以这里用 form 编码提交（Dio 的 urlEncodeMap 与 encodeURIComponent 同口径）。
class TranscriptRemoteDataSource {
  TranscriptRemoteDataSource(this._dio);

  final Dio _dio;

  /// 本科生成绩单的应用 id（H5 = `/jxufeLayuiApp/certificate/undergraduate/scoreIndex.html`）。
  static const String appId = '1741570971384';

  /// checkAppAuth 在平台管理域（与业务域不同 host，走绝对 URL）。
  static const String checkAppAuthUrl =
      'https://wxcourse.jxufe.edu.cn/platForm/api/littleProgram/application/checkAppAuth';

  /// 业务域前缀（H5 里的 `qianzhui`）。
  static const String layuiBasePath = '/layuiApp';

  /// 用平台 GUID 换取加密账号（H5 的 `?userId=` 参数）。
  Future<String> fetchEncUserId(String guid) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        checkAppAuthUrl,
        queryParameters: <String, dynamic>{
          'appid': appId,
          'platformUsername': guid,
        },
      );
    } on DioException catch (e) {
      throw TranscriptApiException('平台账号换取失败：${_dioText(e)}');
    }
    final data = _body(resp);
    final code = data['code'];
    if (code != 200 && code != '200') {
      throw TranscriptApiException(
        '平台账号换取失败：${_message(data, 'code $code')}',
      );
    }
    final result = data['result'];
    if (result is! Map) {
      throw const TranscriptApiException('平台账号换取失败：响应缺少 result');
    }
    final username = result['username'];
    if (username is! String || username.trim().isEmpty) {
      throw const TranscriptApiException('平台账号换取失败：未返回加密账号');
    }
    return username.trim();
  }

  /// 可申请的报表类型（服务端按有无辅修下发）。
  Future<List<TranscriptReportType>> fetchReportTypes(String enc) async {
    final data = await _post(
      '$layuiBasePath/score/verifySecondMajor',
      <String, dynamic>{'userId': enc},
    );
    if (data['status'] != true) {
      throw TranscriptApiException(
        '报表类型获取失败：${_message(data, '服务端返回失败')}',
      );
    }
    return transcriptReportTypes(data['message']?.toString());
  }

  /// 发送成绩单到邮箱；成功返回服务端提示语。
  Future<String> sendTranscript({
    required String enc,
    required String email,
    required String courseId,
  }) async {
    final data = await _post('$layuiBasePath/score/bkscj', <String, dynamic>{
      'userId': enc,
      'email': email,
      'courseId': courseId,
    });
    final message = _message(data, data['status'] == true ? '已提交发送' : '发送失败');
    if (data['status'] != true) {
      throw TranscriptApiException(message);
    }
    return message;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> form,
  ) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.post<dynamic>(
        path,
        data: form,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      throw TranscriptApiException('请求失败：${_dioText(e)}');
    }
    return _body(resp);
  }

  /// Dio 异常 → 可读文案（解码失败一律报「格式异常」）。
  String _dioText(DioException e) {
    if (e.error is FormatException) return '服务响应格式异常';
    final status = e.response?.statusCode;
    if (status != null) return 'HTTP $status';
    return e.message ?? '网络请求失败';
  }

  Map<String, dynamic> _body(Response<dynamic> resp) {
    final data = resp.data;
    if (data is Map) return data.map((k, v) => MapEntry('$k', v));
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', v));
      } catch (_) {
        // 落到下面统一报错。
      }
    }
    throw const TranscriptApiException('服务响应格式异常');
  }

  String _message(Map<String, dynamic> data, String fallback) {
    final raw = data['message'];
    final text = raw == null ? '' : '$raw'.trim();
    return text.isEmpty ? fallback : text;
  }
}
