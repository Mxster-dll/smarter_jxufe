import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:smarter_jxufe/QrCode/QrCode.dart';
import 'package:smarter_jxufe/QrCode/QrCodeCard.dart';
import 'package:smarter_jxufe/QrCode/QrCodeStatus.dart';
import 'package:smarter_jxufe/Log.dart';

class MfaService {
  static const baseUrl = 'https://ssl.jxufe.edu.cn';
  final Dio _dio = Dio();

  final String _account;
  final String _password;

  late MfaQrCode qrCode;
  String? _stateParam; // 一次性产物
  late String _attestServer;
  late String _qrCodeImgUrl;

  MfaService(this._account, this._password);

  /// detect: 获取 mfa 状态
  Future<bool> detectMfa() async {
    try {
      final response = await _dio.post(
        '$baseUrl/cas/mfa/detect',
        data: {
          'username': _account,
          'password': _password,
          // 'fpVisitorId': _fpVisitorId!,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final result = response.data as Map<String, dynamic>;
      final data = result['data'] as Map<String, dynamic>;

      _stateParam = data['state'] as String;
      return data['need'] as bool;
    } catch (e) {
      throw Exception('MFA检测失败: $e');
    }
  }

  Future<void> process(BuildContext context) async {
    if (!await detectMfa()) return;

    await _initQrCode();

    // TODO 让关闭 dialog  停止轮询
    QrCodeCard.showQrCodeDialog(
      context,
      qrCode,
      title: '安全验证',
      info: '当前登录环境异常，需通过安全验证确认是本人操作',
    );
    await _fetchQrCode();
    await _downloadQrCode();
    qrCode.startPolling();
  }

  Future<void> refreshQrCode() async {
    await detectMfa();
    await _initQrCode();
    qrCode.startPolling();
    await _fetchQrCode();
    await _downloadQrCode();
  }

  /// qrcode: 获取 attestServerUrl 和 gid
  /// 必须要先调用 detectMfa 获取 _stateParam
  Future<void> _initQrCode() async {
    qrCode = MfaQrCode(this);
    try {
      final response = await _dio.get(
        '$baseUrl/cas/mfa/initByType/qrcode',
        queryParameters: {'state': _stateParam},
      );

      final result = response.data as Map<String, dynamic>;
      final data = result['data'] as Map<String, dynamic>;

      _attestServer = data['attestServerUrl'] as String;
      qrCode.id = data['gid'] as String;
    } catch (e) {
      throw Exception('二维码信息初始化失败: $e');
    }
  }

  /// send: 获取 verifyCode 和 url
  /// 必须要先调用 _initQrCode 获取 attestServerUrl 和 qrCode.id
  Future<void> _fetchQrCode() async {
    try {
      final response = await _dio.post(
        '$_attestServer/api/guard/qrcode/send',
        data: {'gid': qrCode.id},
      );

      final result = response.data as Map<String, dynamic>;
      final data = result['data'] as Map<String, dynamic>;

      qrCode.verifyCode = data['callbackCode'] as String;
      _qrCodeImgUrl = data['scanQrcode'] as String;
    } catch (e) {
      throw Exception('获取二维码信息失败: $e');
    }
  }

  /// ****.png: 下载二维码图片
  /// 必须要先调用 _fetchQrCode 获取 qrCode.verifyCode 和 _qrCodeImgUrl
  Future<void> _downloadQrCode() async {
    try {
      final response = await _dio.get(
        _qrCodeImgUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode != 200) {
        throw Exception('连接错误${response.statusCode}: $_qrCodeImgUrl');
      }

      qrCode.img = response.data as Uint8List;
      qrCode.status = QrCodeStatus.pending;
    } catch (e) {
      throw Exception('下载二维码失败: $e');
    }
  }

  // final Map<String, dynamic> _headers = {
  //   'Accept': 'application/json, text/javascript, */*; q=0.01',
  //   'Accept-Encoding': 'gzip, deflate, br, zstd',
  //   'Accept-Language': 'zh-CN,zh;q=0.9',
  //   'Connection': 'keep-alive',
  //   'Content-Type': 'application/json; charset=UTF-8',
  //   // Cookie根据实际情况可能需要动态设置
  //   // 'Cookie': 'Hm_lvt_d605d8df6bf5ca8a54fe078683196518=1769601206; '
  //   //     'HMACCOUNT=95DD7CFF9EC39F39; '
  //   //     'Hm_lpvt_d605d8df6bf5ca8a54fe078683196518=1769601426',
  //   'Host': 'ssl.jxufe.edu.cn',
  //   'Origin': 'https://ssl.jxufe.edu.cn',
  //   'Referer':
  //       'https://ssl.jxufe.edu.cn/cas/login?service=http%3A%2F%2Fehall.jxufe.edu.cn%2Famp-auth-adapter%2FloginSuccess%3FsessionToken%3D0b0f3d2b6be14bd0b3c1ecc955bdb832',
  //   'Sec-Fetch-Dest': 'empty',
  //   'Sec-Fetch-Mode': 'cors',
  //   'Sec-Fetch-Site': 'same-origin',
  //   'User-Agent':
  //       'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0',
  //   'X-Requested-With': 'XMLHttpRequest',
  //   'sec-ch-ua':
  //       '"Not(A:Brand";v="8", "Chromium";v="144", "Microsoft Edge";v="144"',
  //   'sec-ch-ua-mobile': '?0',
  // };

  /// status: 轮询状态
  /// 必须要先调用 _initQrCode 获取 attestServerUrl 和 qrCode.id
  Future<QrCodeStatus> pollStatus() async {
    try {
      final response = await _dio.post(
        '$_attestServer/api/guard/qrcode/status',
        data: {'gid': qrCode.id},
        // options: Options(headers: _headers),
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

  static const statusCodeMap = {
    1: 'SENT',
    8: 'SCANED',
    5: 'CANCEL',
    2: 'VALID',
  };

  static const _statusMap = {
    1: QrCodeStatus.pending,
    8: QrCodeStatus.scanned,
    5: QrCodeStatus.cancelled,
    2: QrCodeStatus.authorized,
  };

  QrCodeStatus _extractStatus(Map<String, dynamic> responseBody) {
    if (responseBody['code'] as int == -1) return QrCodeStatus.expired;

    final data = responseBody['data'] as Map<String, dynamic>;
    final status = data['status'] as int;
    final statusCode = data['statusCode'] as String;

    if (statusCodeMap[status] != statusCode) {
      throw Exception(
        '意外的 status: $status, statusCode: $statusCode (应为 ${statusCodeMap[status]})',
      );
    }

    return _statusMap[status]!;
  }
}
