import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';

/// 网费接口异常（message 面向 UI 直显）。
class NetFeeApiException implements Exception {
  final String message;

  const NetFeeApiException(this.message);

  @override
  String toString() => message;
}

/// 智慧江财「网费充值」H5 数据源（wfcz 模块）。
///
/// 认证链与校历同款：平台 GUID → checkAppAuth 换「加密 userId（enc）」 →
/// 计费业务接口（纯学号一律 E99，必须 enc）。充值走微信支付，不做。
class NetFeeRemoteDataSource {
  NetFeeRemoteDataSource(this._dio);

  final Dio _dio;

  /// 平台应用 id（wfcz 网费充值 H5）。
  static const String appId = '1586481872684';

  /// checkAppAuth 在平台管理域（与业务域不同 host，走绝对 URL）。
  static const String checkAppAuthUrl =
      'https://wxcourse.jxufe.edu.cn/platForm/api/littleProgram/application/checkAppAuth';

  /// 业务域前缀。
  static const String payBasePath = '/1585799510593';

  /// 用平台 GUID 换取加密 userId（enc）。
  Future<String> fetchEncUserId(String guid) async {
    final resp = await _dio.get<dynamic>(
      checkAppAuthUrl,
      queryParameters: <String, dynamic>{
        'appid': appId,
        'platformUsername': guid,
      },
    );
    final data = _body(resp);
    final code = data['code'];
    if (code != 200 && code != '200') {
      throw NetFeeApiException(
        '平台账号换取失败：${_message(data, 'code $code')}',
      );
    }
    final result = data['result'];
    if (result is! Map) {
      throw const NetFeeApiException('平台账号换取失败：响应缺少 result');
    }
    final username = result['username'];
    if (username is! String || username.isEmpty) {
      throw const NetFeeApiException('平台账号换取失败：未返回加密账号');
    }
    return username;
  }

  /// 查询网费余额。E00 成功；E14 账号不支持；其余异常。
  Future<NetFeeAccount> fetchBalance(String enc) async {
    final resp = await _dio.get<dynamic>(
      '$payBasePath/pay/account',
      queryParameters: <String, dynamic>{'username': enc},
    );
    final data = _body(resp);
    final code = data['code'];
    if (code == 'E14') {
      throw NetFeeApiException('该账号不支持网费账户（E14）');
    }
    if (code != 'E00') {
      throw NetFeeApiException('网费余额查询失败：${_message(data, code?.toString() ?? 'E99')}');
    }
    final balance = double.tryParse(data['balance']?.toString() ?? '');
    if (balance == null) {
      throw const NetFeeApiException('网费余额响应缺少数值');
    }
    return NetFeeAccount(
      balance: balance,
      username: data['username']?.toString() ?? '',
    );
  }

  /// 查询充值记录。窗口参数与小程序一致为 yyyy-MM-dd 日期，
  /// 默认近一年（小程序记录页即日窗口，App 采用整年窗口更实用）。
  Future<List<NetFeeRecord>> fetchRecords(
    String enc, {
    DateTime? from,
    DateTime? to,
  }) async {
    final end = to ?? DateTime.now();
    final start = from ?? DateTime(end.year - 1, end.month, end.day);
    final resp = await _dio.get<dynamic>(
      '$payBasePath/pay/detail',
      queryParameters: <String, dynamic>{
        'start_time': _fmtDate(start),
        'end_time': _fmtDate(end),
        'username': enc,
      },
    );
    final data = _body(resp);
    if (data['code'] != 200 && data['code'] != '200') {
      throw NetFeeApiException('充值记录查询失败：${_message(data, 'code ${data['code']}')}');
    }
    final list = data['list'];
    if (list is! List) return const [];
    final records = <NetFeeRecord>[];
    for (final item in list) {
      if (item is Map) {
        records.add(
          NetFeeRecord.fromJson(
            item.map((k, v) => MapEntry(k.toString(), v)),
          ),
        );
      }
    }
    records.sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return records;
  }

  Map<String, dynamic> _body(Response<dynamic> resp) {
    final data = resp.data;
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = _jsonDecode(data);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        // fallthrough
      }
    }
    throw const NetFeeApiException('服务响应格式异常');
  }

  String _message(Map<String, dynamic> data, String fallback) {
    final msg = data['message']?.toString() ?? '';
    return msg.isEmpty ? fallback : msg;
  }

  String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

dynamic _jsonDecode(String raw) => jsonDecode(raw);
