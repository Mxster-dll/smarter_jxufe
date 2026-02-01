import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:smarter_jxufe/QrCode/QrCode.dart';
import 'package:smarter_jxufe/QrCode/QrCodeCard.dart';
import 'package:smarter_jxufe/QrCode/QrCodeStatus.dart';

class ScanLoginService {
  static const baseUrl = 'https://ssl.jxufe.edu.cn';
  final Dio _dio = Dio();

  late LoginQrCode qrCode;
  late String _pollingCookie;

  String _getQrCodeId() {
    return (DateTime.now().millisecondsSinceEpoch + (Random().nextInt(24)))
        .toString();
  }

  Future<void> process(BuildContext context) async {
    qrCode = LoginQrCode(this);

    qrCode.id = _getQrCodeId();
    qrCode.imgUrl = '$baseUrl/qr/qrcode?r=${qrCode.id}';

    QrCodeCard.showQrCodeDialog(context, qrCode, title: '扫描二维码登录');

    await _downloadQrCode();
    qrCode.startPolling();
  }

  Future<void> refreshQrCode() async {
    qrCode.id = _getQrCodeId();
    qrCode.imgUrl = '$baseUrl/qr/qrcode?r=${qrCode.id}'; // 调试在后面加 &debug=debug

    await _downloadQrCode();
    qrCode.startPolling();
  }

  Future<void> _downloadQrCode() async {
    try {
      final response = await _dio.get(
        '$baseUrl/cas/qr/qrcode',
        data: {'r': int.parse(qrCode.id)},
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode != 200) {
        throw Exception(
          '连接错误${response.statusCode}: $baseUrl/cas/qr/qrcode?r=${qrCode.id}',
        );
      }

      qrCode.img = response.data as Uint8List;
      qrCode.status = QrCodeStatus.pending;

      _pollingCookie = _getSessionCookie(response);
    } catch (e) {
      throw Exception('下载二维码失败: $e');
    }
  }

  String _getSessionCookie(Response<dynamic> response) {
    List<String>? cookies = response.headers['set-cookie'];

    if (cookies == null) throw Exception('缺失轮询 Cookie: $response');

    for (String cookie in cookies) {
      for (String part in cookie.split(';')) {
        String trimmedPart = part.trim();

        if (trimmedPart.toUpperCase().startsWith('SESSION')) {
          return trimmedPart;
        }
      }
    }

    throw Exception('缺失轮询 Cookie: $response');
  }

  Future<QrCodeStatus?> pollStatus() async {
    try {
      final response = await _dio.post(
        '$baseUrl/cas/qr/comet',
        options: Options(headers: {'Cookie': _pollingCookie}),
      );

      if (response.statusCode != 200) {
        throw Exception('连接错误${response.statusCode}');
      }

      return _extractStatus(response.data);
    } catch (e) {
      throw Exception('轮询失败: $e');
    }
  }

  static const _statusMap = {
    // 1: 待扫描
    2: QrCodeStatus.scanned,
    3: QrCodeStatus.authorized,
    4: QrCodeStatus.cancelled,
  };

  QrCodeStatus? _extractStatus(Map<String, dynamic> responseBody) {
    if (responseBody['message'] == 'expired') return QrCodeStatus.expired;

    final data = responseBody['data'] as Map<String, dynamic>;
    final status = int.parse(data['qrCode']['status']);

    return _statusMap[status];
  }
}
