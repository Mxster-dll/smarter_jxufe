import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/my_mail/domain/student_mailbox.dart';

/// 我的邮箱接口异常（message 面向 UI 直显）。
class MyMailApiException implements Exception {
  final String message;

  const MyMailApiException(this.message);

  @override
  String toString() => message;
}

/// 智慧江财「我的邮箱」数据源（门户 `platForm` 域的邮箱接口）。
///
/// 认证链比网费更短：**平台 GUID 直接当 `username`**（无需 `checkAppAuth` 换 enc）。
/// 服务器按来源放行，必须带 servicewechat 页面 Referer 与浏览器 UA（见 provider）。
class MyMailRemoteDataSource {
  MyMailRemoteDataSource(this._dio);

  final Dio _dio;

  /// 邮箱账号 + 初始密码。
  static const String getPwdPath = '/platForm/api/wx/email/getPwd';

  Future<StudentMailbox> fetchMailbox(String guid) async {
    final Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        getPwdPath,
        queryParameters: <String, dynamic>{'username': guid},
      );
    } on DioException catch (e) {
      // 网络 / 解码异常（响应不是 JSON 时 Dio 会抛 FormatException）统一转成
      // 面向 UI 的异常，避免把 DioException 直接漏到页面。
      throw MyMailApiException('邮箱账号读取失败：${_dioText(e)}');
    }
    final data = _body(resp);
    final code = data['code'];
    final ok =
        data['success'] == true ||
        code == 1 ||
        code == '1' ||
        code == 200 ||
        code == '200';
    if (!ok) {
      throw MyMailApiException('邮箱账号读取失败：${_message(data, 'code $code')}');
    }
    final result = data['result'];
    if (result is! Map) {
      throw const MyMailApiException('邮箱账号响应缺少 result');
    }
    final mailbox = StudentMailbox.fromJson(result);
    if (mailbox.email.isEmpty) {
      throw const MyMailApiException('邮箱账号响应缺少邮箱地址');
    }
    return mailbox;
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
    throw const MyMailApiException('邮箱账号响应格式异常');
  }

  String _message(Map<String, dynamic> data, String fallback) {
    final raw = data['message'];
    final text = raw == null ? '' : '$raw'.trim();
    return text.isEmpty ? fallback : text;
  }

  /// Dio 异常 → 可读文案（解码失败一律报「格式异常」）。
  String _dioText(DioException e) {
    if (e.error is FormatException) return '服务响应格式异常';
    final status = e.response?.statusCode;
    if (status != null) return 'HTTP $status';
    return e.message ?? '网络请求失败';
  }
}
