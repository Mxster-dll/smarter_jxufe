import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

enum QrCodeStatus {
  loading,
  pendingScan,
  waitingVerify,
  confirmed,
  canceled,
  expired;

  // 是否为最终状态（不再需要轮询）
  bool get isFinal => this == confirmed || this == canceled;
}

typedef QrCodeData = Map<String, dynamic>;

abstract class QrCode {
  final String requestUrl;

  final Dio _dio = Dio();
  QrCodeStatus status = QrCodeStatus.loading;

  late String id;
  late Uint8List img;

  Container card = Container();

  QrCode(this.requestUrl);

  bool get isLoading => status == QrCodeStatus.loading;

  Future<void> init();
  Future<void> refresh();

  // Future<QrCodeStatus> _pollStatus();
}

class MfaQrCode extends QrCode {
  String state;
  String? verifyCode;

  MfaQrCode(super.requestUrl, this.state);

  @override
  Future<void> init() async => _showQrCode();

  @override
  Future<void> refresh() async => _showQrCode();

  Future<void> _showQrCode() async {
    status = QrCodeStatus.loading;
    final url = await _getQrCodeUrl(state);
    final qrCodeImg = await _downloadQrCode(url);
    img = qrCodeImg;
    status = QrCodeStatus.pendingScan;
    // 轮询
    // 展示二维码
  }

  /// 会同时获取 id 和 verifyCode
  Future<String> _getQrCodeUrl(String state) async {
    try {
      // 获取 attestServerUrl 和 gid
      var response = await _dio.get(
        requestUrl,
        queryParameters: {'state': state},
      );

      var result = response.data as Map<String, dynamic>;
      var data = result['data'] as Map<String, dynamic>;

      final attestServer = data['attestServerUrl'] as String;
      id = data['gid'] as String;

      // 获取 verifyCode 和 url
      response = await _dio.post(
        '$attestServer/api/guard/qrcode/send',
        data: {'gid': id},
      );

      result = response.data as Map<String, dynamic>;
      data = result['data'] as Map<String, dynamic>;

      verifyCode = data['callbackCode'] as String;
      return data['scanQrcode'] as String;
    } catch (e) {
      throw Exception('获取二维码信息失败: $e');
    }
  }

  Future<Uint8List> _downloadQrCode(String url) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode != 200) {
        throw Exception('连接错误${response.statusCode}: $url');
      }

      return response.data as Uint8List;
    } catch (e) {
      throw Exception('下载二维码失败: $e');
    }
  }
}
