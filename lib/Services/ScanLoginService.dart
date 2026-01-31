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

  Future<void> process(BuildContext context) async {
    qrCode = LoginQrCode(this);
    qrCode.id =
        (DateTime.now().millisecondsSinceEpoch + (Random().nextInt(24)))
            as String;

    QrCodeCard.showQrCodeDialog(context, qrCode, title: '扫描二维码登录');

    await _downloadQrCode();
    qrCode.startPolling();
  }

  Future<void> refreshQrCode() async {}

  Future<void> _downloadQrCode() async {
    try {
      final response = await _dio.get(
        '$baseUrl/cas/qr/qrcode',
        data: {'r': qrCode.id as int},
      );

      if (response.statusCode != 200) {
        throw Exception('连接错误${response.statusCode}: $baseUrl/cas/qr/qrcode');
      }

      qrCode.img = response.data as Uint8List;
      qrCode.status = QrCodeStatus.pending;
    } catch (e) {
      throw Exception('下载二维码失败: $e');
    }
  }

  Future<QrCodeStatus> pollStatus() async {
    try {
      final response = await _dio.post(
        '$baseUrl/cas/qr/comet',
        data: {'r': qrCode.id as int},
      );

      if (response.statusCode != 200) {
        throw Exception('连接错误${response.statusCode}');
      }

      return _extractStatus(response.data);
    } catch (e) {
      throw Exception('下载二维码失败: $e');
    }
  }

  static const _statusMap = {
    1: QrCodeStatus.pending,
    2: QrCodeStatus.scanned,
    3: QrCodeStatus.authorized,
    4: QrCodeStatus.cancelled,
  };

  QrCodeStatus _extractStatus(Map<String, dynamic> responseBody) {
    if (responseBody['code'] as int == 1) return QrCodeStatus.expired;

    final data = responseBody['data'] as Map<String, dynamic>;
    final status = data['qrCode']['status'] as int;

    return _statusMap[status]!;
  }
}
