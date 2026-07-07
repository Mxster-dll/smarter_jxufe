import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';

/// 扫码登录远程数据源
/// 负责与校方 CAS 系统通信：下载二维码、轮询扫码状态
class ScanLoginRemoteDataSource {
  static const baseUrl = 'https://ssl.jxufe.edu.cn';

  final Dio _dio;

  ScanLoginRemoteDataSource(this._dio);

  String generateQrCodeId() {
    return (DateTime.now().millisecondsSinceEpoch + (Random().nextInt(24)))
        .toString();
  }

  String getQrCodeUrl(String id) => '$baseUrl/qr/qrcode?r=$id';

  /// 下载二维码图片，返回 (图片字节, session cookie)
  Future<(Uint8List, String)> downloadQrCode(
    String id, {
    String referer = '',
    String sessionCookie = '',
  }) async {
    final headers = <String, String>{
      'Host': 'ssl.jxufe.edu.cn',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
          ' (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36 Edg/150.0.0.0',
      'Accept':
          'image/avif,image/webp,image/apng,image/svg+xml,image/*,'
          '*/*;q=0.8',
      'sec-ch-ua':
          '"Not;A=Brand";v="8", "Chromium";v="150", "Microsoft Edge";v="150"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Fetch-Mode': 'no-cors',
      'Sec-Fetch-Dest': 'image',
      'Accept-Encoding': 'gzip, deflate, br, zstd',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
    };
    if (referer.isNotEmpty) headers['Referer'] = referer;
    if (sessionCookie.isNotEmpty) headers['Cookie'] = sessionCookie;

    final response = await _dio.get(
      '$baseUrl/cas/qr/qrcode',
      queryParameters: {'r': id},
      options: Options(headers: headers, responseType: ResponseType.bytes),
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
    // '1': 待扫描
    '2': QrCodeStatus.scanned,
    '3': QrCodeStatus.authorized,
    '4': QrCodeStatus.cancelled,
  };

  /// 轮询扫码状态
  /// 返回 null 表示仍为待扫描状态
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
