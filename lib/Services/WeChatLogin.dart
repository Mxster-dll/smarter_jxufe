import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:smarter_jxufe/Log.dart';
import 'package:smarter_jxufe/qrCode/QrCode.dart';
import 'package:smarter_jxufe/qrCode/QrCodeCard.dart';
import 'package:smarter_jxufe/qrCode/QrCodeStatus.dart';

/// 长轮询模式
/// 超时返回 408
/// 已扫描返回 404
/// 失效返回 402
/// 取消返回 403
/// 由于如果查询到状态为 403 或 404 会立即返回，但此时仍需轮询下一步状态，则需带上last字段，给出上一次查询到的状态码
class WeChatLogin extends QrCodeNetworkService {
  static const String appid = 'wx0c8ba76c633d28f2'; // 江西财经大学认证系统在微信开放平台的 id
  static const String redirectUrl =
      'https://ssl.jxufe.edu.cn/cas/federation/federatedCallback/openweixin';

  final Dio _dio;
  WeChatLogin([Dio? dio])
    : _dio = dio ?? Dio(BaseOptions(receiveTimeout: Duration(seconds: 20)));

  late QrCode qrCode;

  @override
  Future<void> process(BuildContext context) async {
    qrCode = QrCode(this, 17 * 1000);

    await _initQrCode();

    qrCode.startPolling();
    QrCodeCard.showQrCodeDialog(context, qrCode, title: '微信登录');

    await _downloadQrCode();
  }

  @override
  Future<void> refreshQrCode() {
    // TODO: implement refreshQrCode
    throw UnimplementedError();
  }

  Map<String, dynamic> httpHeaders = {
    // ":authority": "open.weixin.qq.com",
    // ":method": "GET",
    // ":path":
    //     "/connect/qrconnect?appid=wx0c8ba76c633d28f2&redirect_uri=https%3A%2F%2Fssl.jxufe.edu.cn%2Fcas%2Ffederation%2FfederatedCallback%2Fopenweixin&response_type=code&scope=snsapi_login&state=hEwGB4",
    // ":scheme": "https",
    "accept":
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
    "accept-encoding": "gzip, deflate, br, zstd",
    "accept-language": "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
    "cache-control": "max-age=0",
    "cookie":
        "pgv_pvid=3400091058; fqm_pvqid=2d4958a4-5d83-4aed-ad0e-5f5420d3046a; RK=z+NZVb7OSu; ptcz=0f7ff88f3ac6abedf7d89c90867269c78dc3fc0ebb35c09044b5bcde8a2ab4a8; yyb_muid=158335C201BB63103A3A238000DD6276; _ga=GA1.1.1206149665.1763023947; _ga_PF3XX5J8LE=GS2.1.s1763046505\$o2\$g0\$t1763046505\$j60\$l0\$h0; pac_uid=0_Rm0YEbZ5zGTRi; _qimei_uuid42=19b1b071d3010058cceeaa1963f54942ea33a957cb; _qimei_h38=19c58f14cceeaa1963f5494202000002e19b1b; _qimei_q32=7804312a8a779d64c7a2099994ea8ae2; _qimei_q36=ed4addae17cb01eda7933e39300010619a09; omgid=0_Rm0YEbZ5zGTRi; _qimei_fingerprint=c26e2b5eb17a43cd78e5416435ada646; uin=o1443872776; skey=@6sFzjV5K1",
    "priority": "u=0, i",
    "referer": "https://ssl.jxufe.edu.cn/",
    "sec-ch-ua":
        "\"Not(A:Brand\";v=\"8\", \"Chromium\";v=\"144\", \"Microsoft Edge\";v=\"144\"",
    "sec-ch-ua-mobile": "?0",
    "sec-ch-ua-platform": "\"Windows\"",
    "sec-fetch-dest": "document",
    "sec-fetch-mode": "navigate",
    "sec-fetch-site": "cross-site",
    "sec-fetch-user": "?1",
    "upgrade-insecure-requests": "1",
    "user-agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0",
  };
  Future<void> _initQrCode() async {
    try {
      final response = await _dio.get(
        'https://ssl.jxufe.edu.cn/cas/federatedRedirect?service=http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess?sessionToken%3D8838d54c26fb44ac98d0599cb1f49769&federatedName=openweixin',
        data: {
          'service': 'http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess',
          // 'sessionToken': redirectUrl,
          'federatedName': 'openweixin',
        },
      );
      // final response = await _dio.get(
      //   'https://open.weixin.qq.com/connect/qrconnect',
      //   data: {
      //     'appid': appid,
      //     'redirect_uri': redirectUrl,
      //     'response_type': 'code',
      //     'scope': 'snsapi_login',
      //     'state': 'zDcs0g',
      //   },
      //   options: Options(headers: httpHeaders),
      // );

      qrCode.id = _extractUuid(response.data);
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

  Future<void> _downloadQrCode() async {
    try {
      final response = await _dio.get(
        'https://open.weixin.qq.com/connect/qrcode/${qrCode.id}',
        options: Options(responseType: ResponseType.bytes),
      );

      qrCode.img = response.data as Uint8List;
      qrCode.status = QrCodeStatus.pending;
    } catch (e) {
      throw Exception('二维码下载失败: $e');
    }
  }

  static const _statusMap = {
    '402': QrCodeStatus.expired,
    '403': QrCodeStatus.cancelled,
    '404': QrCodeStatus.scanned,
    '405': QrCodeStatus.authorized,
    // '408': 待扫描
  };

  @override
  Future<QrCodeStatus?> pollStatus() async {
    try {
      final response = await _dio.get(
        'https://lp.open.weixin.qq.com/connect/l/qrconnect',
        data: {'uuid': qrCode.id},
      );

      if (response.statusCode != 200) {
        throw Exception('连接错误${response.statusCode}');
      }

      final regex = RegExp(r'window\.wx_errcode\s*=\s*([^;]+)');
      final match = regex.firstMatch(response.data as String);

      if (match == null || match.groupCount == 0) {
        throw Exception('无法匹配到wx_errcode: $response.data');
      }

      String status = match.group(1)?.trim() ?? '';

      return _statusMap[status];
    } catch (e) {
      throw Exception('轮询失败: $e');
    }
  }
}
