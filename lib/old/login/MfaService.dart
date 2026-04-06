import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:smarter_jxufe/qrCode/QrCodeService.dart';
import 'package:smarter_jxufe/utils/Log.dart';

final class MfaService implements QrCodeNetworkService {
  static const baseUrl = 'https://ssl.jxufe.edu.cn';

  final Dio _dio;
  MfaService([Dio? dio]) : _dio = dio ?? Dio();

  late String _account;
  late String _password;

  late QrCode qrCode;
  String? mfaState;
  late String _attestServer;

  void set(String account, String password) {
    _account = account;
    _password = password;
  }

  @override
  Future<void> process(BuildContext context) async {
    if (!await detectMfa()) return;

    qrCode = QrCode(this);
    await _initQrCode();

    qrCode.startPolling();
    QrCodeCard.showQrCodeDialog(
      context,
      qrCode,
      title: '安全验证',
      info: '当前登录环境异常，需通过安全验证确认是本人操作',
    );

    await _fetchQrCode();
    await _downloadQrCode();
  }

  @override
  Future<void> refreshQrCode() async {
    qrCode.status = QrCodeStatus.loading;
    qrCode.stopPolling();

    final t1 = DateTime.now();

    await detectMfa();
    final t2 = DateTime.now();

    await _initQrCode();
    qrCode.startPolling();
    final t3 = DateTime.now();

    await _fetchQrCode();
    final t4 = DateTime.now();

    await _downloadQrCode();
    final t5 = DateTime.now();

    logInfo("""${t5.difference(t1).inMilliseconds}ms

    detectMfa:\t ${t2.difference(t1).inMilliseconds}ms
    initQrCode:\t ${t3.difference(t2).inMilliseconds}ms
    fetchQrCode:\t ${t4.difference(t3).inMilliseconds}ms
    downloadQrCode:\t ${t5.difference(t4).inMilliseconds}ms
      """);
  }

  /// detect: 获取 mfa 状态
  Future<bool> detectMfa() async {
    try {
      final response = await _dio.post(
        '$baseUrl/cas/mfa/detect',
        data: {
          'username': _account,
          'password': _password,
          // 'fpVisitorId': _fpVisitorId!,
          // 'fpVisitorId': d1692c113a6579952b0270a150073e0b,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final result = response.data as Map<String, dynamic>;
      final data = result['data'] as Map<String, dynamic>;

      mfaState = data['state'] as String;
      return data['need'] as bool;
    } catch (e) {
      throw Exception('MFA检测失败: $e');
    }
  }

  /// qrcode: 获取 attestServerUrl 和 gid
  /// 必须要先调用 detectMfa 获取 _stateParam
  Future<void> _initQrCode() async {
    try {
      final response = await _dio.get(
        '$baseUrl/cas/mfa/initByType/qrcode',
        queryParameters: {'state': mfaState},
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
      qrCode.imgUrl = data['scanQrcode'] as String;
    } catch (e) {
      throw Exception('获取二维码信息失败: $e');
    }
  }

  /// ****.png: 下载二维码图片
  /// 必须要先调用 _fetchQrCode 获取 qrCode.verifyCode 和 _qrCodeImgUrl
  Future<void> _downloadQrCode() async {
    try {
      final response = await _dio.get(
        qrCode.imgUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode != 200) {
        throw Exception('连接错误${response.statusCode}: ${qrCode.imgUrl}');
      }

      qrCode.img = response.data as Uint8List;
      qrCode.status = QrCodeStatus.pending;
    } catch (e) {
      throw Exception('下载二维码失败: $e');
    }
  }

  final Map<String, dynamic> _headers = {
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Accept-Encoding': 'gzip, deflate, br, zstd',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Connection': 'keep-alive',
    'Content-Type': 'application/json; charset=UTF-8',
    // Cookie根据实际情况可能需要动态设置
    // 'Cookie': 'Hm_lvt_d605d8df6bf5ca8a54fe078683196518=1769601206; '
    //     'HMACCOUNT=95DD7CFF9EC39F39; '
    //     'Hm_lpvt_d605d8df6bf5ca8a54fe078683196518=1769601426',
    'Host': 'ssl.jxufe.edu.cn',
    'Origin': 'https://ssl.jxufe.edu.cn',
    'Referer':
        'https://ssl.jxufe.edu.cn/cas/login?service=http%3A%2F%2Fehall.jxufe.edu.cn%2Famp-auth-adapter%2FloginSuccess%3FsessionToken%3D0b0f3d2b6be14bd0b3c1ecc955bdb832',
    'Sec-Fetch-Dest': 'empty',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Site': 'same-origin',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0',
    'X-Requested-With': 'XMLHttpRequest',
    'sec-ch-ua':
        '"Not(A:Brand";v="8", "Chromium";v="144", "Microsoft Edge";v="144"',
    'sec-ch-ua-mobile': '?0',
  };

  /// status: 轮询状态
  /// 必须要先调用 _initQrCode 获取 attestServerUrl 和 qrCode.id
  @override
  Future<QrCodeStatus?> pollStatus() async {
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

  QrCodeStatus? _extractStatus(Map<String, dynamic> responseBody) {
    if (responseBody['code'] as int == -1) return QrCodeStatus.expired;

    final data = responseBody['data'] as Map<String, dynamic>;
    final status = data['status'] as int;
    final statusCode = data['statusCode'] as String;

    if (statusCodeMap[status] != statusCode) {
      throw Exception(
        '意外的 status: $status, statusCode: $statusCode (应为 ${statusCodeMap[status]})\n$responseBody',
      );
    }

    return _statusMap[status];
  }
}
