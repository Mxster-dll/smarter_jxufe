import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';
import 'package:smarter_jxufe/utils/Log.dart';

/// MFA 登录远程数据源
/// 负责 MFA 检测与 QR 码验证的 HTTP 请求
class MfaLoginRemoteDataSource {
  static const baseUrl = 'https://ssl.jxufe.edu.cn';

  final Dio _dio;

  MfaLoginRemoteDataSource(this._dio);

  /// 第一步：检测是否需要 MFA（多因素认证）
  /// 返回 (是否MFA需要, mfaState)
  Future<(bool, String)> detectMfa(String account, String password) async {
    try {
      final response = await _dio.post(
        '$baseUrl/cas/mfa/detect',
        data: {'username': account, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final result = response.data as Map<String, dynamic>;
      final data = result['data'] as Map<String, dynamic>;

      final mfaState = data['state'] as String;
      final need = data['need'] as bool;

      return (need, mfaState);
    } catch (e) {
      throw Exception('MFA检测失败: $e');
    }
  }

  /// 第二步：初始化 QR 码（获取 attestServerUrl 和 gid）
  /// 返回 (attestServerUrl, gid)
  Future<(String, String)> initQrCode(String mfaState) async {
    try {
      final response = await _dio.get(
        '$baseUrl/cas/mfa/initByType/qrcode',
        queryParameters: {'state': mfaState},
      );

      final result = response.data as Map<String, dynamic>;
      final data = result['data'] as Map<String, dynamic>;

      final attestServer = data['attestServerUrl'] as String;
      final gid = data['gid'] as String;

      return (attestServer, gid);
    } catch (e) {
      throw Exception('二维码信息初始化失败: $e');
    }
  }

  /// 第三步：获取二维码信息（verifyCode 和 imgUrl）
  /// 返回 (verifyCode, imgUrl)
  Future<(String, String)> fetchQrCode(String attestServer, String gid) async {
    try {
      final response = await _dio.post(
        '$attestServer/api/guard/qrcode/send',
        data: {'gid': gid},
      );

      final result = response.data as Map<String, dynamic>;
      final data = result['data'] as Map<String, dynamic>;

      final verifyCode = data['callbackCode'] as String;
      final imgUrl = data['scanQrcode'] as String;

      return (verifyCode, imgUrl);
    } catch (e) {
      throw Exception('获取二维码信息失败: $e');
    }
  }

  /// 第四步：下载二维码图片
  Future<Uint8List> downloadQrCode(String imgUrl) async {
    try {
      final response = await _dio.get(
        imgUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode != 200) {
        throw Exception('连接错误${response.statusCode}: $imgUrl');
      }

      return response.data as Uint8List;
    } catch (e) {
      throw Exception('下载二维码失败: $e');
    }
  }

  static const _statusCodeMap = {
    0: 'INIT',
    1: 'SENT',
    2: 'VALID',
    5: 'CANCEL',
    8: 'SCANED',
    9: 'EXPIRED',
  };

  static const _statusMap = {
    0: QrCodeStatus.loading,
    // 1: 待扫描
    2: QrCodeStatus.authorized,
    5: QrCodeStatus.cancelled,
    8: QrCodeStatus.scanned,
    9: QrCodeStatus.expired,
  };

  /// 第五步：轮询二维码状态
  Future<QrCodeStatus?> pollStatus(String attestServer, String gid) async {
    try {
      final response = await _dio.post(
        '$attestServer/api/guard/qrcode/status',
        data: {'gid': gid},
      );

      if (response.statusCode != 200) {
        throw Exception('连接错误${response.statusCode}');
      }

      return _extractStatus(response.data);
    } catch (e) {
      logError('轮询异常: $e');
      return QrCodeStatus.error;
    }
  }

  QrCodeStatus? _extractStatus(Map<String, dynamic> responseBody) {
    if (responseBody['code'] as int == -1) return QrCodeStatus.expired;

    final data = responseBody['data'] as Map<String, dynamic>;
    final status = data['status'] as int;
    final statusCode = data['statusCode'] as String;

    if (_statusCodeMap[status] != statusCode) {
      throw Exception(
        '意外的 status: $status, statusCode: $statusCode '
        '(应为 ${_statusCodeMap[status]})\n$responseBody',
      );
    }

    return _statusMap[status];
  }
}
