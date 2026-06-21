import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';
    // TODO: implement process
import 'package:smarter_jxufe/utils/Log.dart';

class WechatLoginRemoteDataSource {
  static const String appid = 'wx0c8ba76c633d28f2';
  static const String redirectUrl =
      'https://ssl.jxufe.edu.cn/cas/federation/federatedCallback/openweixin';

  final Dio _dio;

  WechatLoginRemoteDataSource(this._dio);

  Future<String> initAndGetUuid() async {
    try {
      final response = await _dio.get(
        'https://ssl.jxufe.edu.cn/cas/federatedRedirect?service=http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess?sessionToken%3D8838d54c26fb44ac98d0599cb1f49769&federatedName=openweixin',
        data: {
          'service': 'http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess',
          'federatedName': 'openweixin',
        },
      );

      return _extractUuid(response.data);
    } catch (e) {
      logError('$e');
      throw Exception('二维码信息初始化失败: $e');
    }
  }

  String _extractUuid(String responseBody) {
    final regex1 = RegExp(r'''qrconnect\?uuid=([^\'\"&]+)''');
    final match1 = regex1.firstMatch(responseBody);

    if (match1 != null && match1.groupCount >= 1) {
      return match1.group(1)?.trim() ?? '';
    }

    final regex2 = RegExp(r'<!\[CDATA\[(.*?)\]\]>');
    final match2 = regex2.firstMatch(responseBody);

    if (match2 != null && match2.groupCount >= 1) {
      return match2.group(1)?.trim() ?? '';
    }

    throw Exception('无法匹配到 uuid: $responseBody');
  }

  Future<Uint8List> downloadQrCode(String uuid) async {
    try {
      final response = await _dio.get(
        'https://open.weixin.qq.com/connect/qrcode/$uuid',
        options: Options(responseType: ResponseType.bytes),
      );

      return response.data as Uint8List;
    } catch (e) {
      throw Exception('二维码下载失败: $e');
    }
  }

  static const _statusMap = {
    '402': QrCodeStatus.expired,
    '403': QrCodeStatus.cancelled,
    '404': QrCodeStatus.scanned,
    '405': QrCodeStatus.authorized,
  };

  Future<QrCodeStatus?> pollStatus(String uuid) async {
    try {
      final response = await _dio.get(
        'https://lp.open.weixin.qq.com/connect/l/qrconnect',
        data: {'uuid': uuid},
      );

      if (response.statusCode != 200) {
        throw Exception('连接错误${response.statusCode}');
      }

      final regex = RegExp(r'window\.wx_errcode\s*=\s*([^;]+)');
      final match = regex.firstMatch(response.data as String);

      if (match == null || match.groupCount == 0) {
        throw Exception('无法匹配到wx_errcode: ${response.data}');
      }

      final String status = match.group(1)?.trim() ?? '';

      return _statusMap[status];
    } catch (e) {
      throw Exception('轮询失败: $e');
    }
  }

  Future<void> refreshQrCode() {
    // TODO: implement refreshQrCode
    throw UnimplementedError('微信二维码刷新暂未实现');
  }
}
