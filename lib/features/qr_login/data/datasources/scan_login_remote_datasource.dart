import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';

class ScanLoginRemoteDataSource {
  static const baseUrl = 'https://ssl.jxufe.edu.cn';

  final Dio _dio;

  ScanLoginRemoteDataSource(this._dio);

  String generateQrCodeId() {
    return (DateTime.now().millisecondsSinceEpoch + (Random().nextInt(24)))
        .toString();
  }

  String getQrCodeUrl(String id) => '$baseUrl/qr/qrcode?r=$id';

  Future<(Uint8List, String)> downloadQrCode(String id) async {
    final response = await _dio.get(
      '$baseUrl/cas/qr/qrcode',
      data: {'r': int.parse(id)},
      options: Options(responseType: ResponseType.bytes),
    );

    if (response.statusCode != 200) {
      throw Exception(
        '连接错误${response.statusCode}: $baseUrl/cas/qr/qrcode?r=$id',
      );
    }

    final img = response.data as Uint8List;
    final cookie = _extractSessionCookie(response);

    return (img, cookie);
  }

  String _extractSessionCookie(Response<dynamic> response) {
    final List<String>? cookies = response.headers['set-cookie'];

    if (cookies == null) throw Exception('缺失轮询 Cookie: $response');

    for (final String cookie in cookies) {
      for (final String part in cookie.split(';')) {
        final String trimmedPart = part.trim();

        if (trimmedPart.toUpperCase().startsWith('SESSION')) {
          return trimmedPart;
        }
      }
    }

    throw Exception('缺失轮询 Cookie: $response');
  }

  static const _statusMap = {
    '2': QrCodeStatus.scanned,
    '3': QrCodeStatus.authorized,
    '4': QrCodeStatus.cancelled,
  };

  Future<QrCodeStatus?> pollStatus(String cookie) async {
    final response = await _dio.post(
      '$baseUrl/cas/qr/comet',
      options: Options(headers: {'Cookie': cookie}),
    );

    if (response.statusCode != 200) {
      throw Exception('连接错误${response.statusCode}');
    }

    return _extractStatus(response.data);
  }

  QrCodeStatus? _extractStatus(Map<String, dynamic> responseBody) {
    if (responseBody['message'] == 'expired') return QrCodeStatus.expired;

    final data = responseBody['data'] as Map<String, dynamic>;
    final status = data['qrCode']['status'];

    return _statusMap[status];
  }
}
