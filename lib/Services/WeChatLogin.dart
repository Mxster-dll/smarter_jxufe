import 'package:dio/dio.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:smarter_jxufe/QrCode/QrCode.dart';
import 'package:smarter_jxufe/QrCode/QrCodeStatus.dart';

/// 长轮询模式
/// 超时返回 408
/// 已扫描返回 404
/// 失效返回 402
/// 取消返回 403
/// 由于如果查询到状态为 403 或 404 会立即返回，但此时仍需轮询下一步状态，则需带上last字段，给出上一次查询到的状态码
class WeChatLogin extends QrCodeNetworkService {
  static const String appid = 'wx0c8ba76c633d28f2'; // 江西财经大学认证系统在微信开放平台的 id

  late QrCode qrCode;

  final Dio _dio;
  WeChatLogin([Dio? dio]) : _dio = dio ?? Dio();

  @override
  Future<void> process(BuildContext context) {
    // TODO: implement process
    throw UnimplementedError();
  }

  @override
  Future<void> refreshQrCode() {
    // TODO: implement refreshQrCode
    throw UnimplementedError();
  }

  Future<QrCodeStatus?> pollStatus() async {
    try {
      final response = await _dio.get(
        'https://lp.open.weixin.qq.com/connect/l/qrconnect',
        data: {'uuid': qrCode.id},
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
    402: QrCodeStatus.expired,
    403: QrCodeStatus.cancelled,
    404: QrCodeStatus.scanned,
    405: QrCodeStatus.authorized,
    // 408: 待扫描
  };

  QrCodeStatus? _extractStatus(Map<String, dynamic> responseBody) {
    if (responseBody['message'] == 'expired') return QrCodeStatus.expired;

    final data = responseBody['data'] as Map<String, dynamic>;
    final status = int.parse(data['qrCode']['status']);

    return _statusMap[status];
  }
}
