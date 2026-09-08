/// 智慧江财小程序校历实时数据源（需平台 GUID）。
///
/// 接口：POST https://wxcourse.jxufe.cn/interface/api/interface/getSchoolCalendar
/// 服务端强鉴权：请求须带平台用户 GUID（username 参数）+ bn 三参数签名
/// （timestamp/nonce/sign，见 [bnSignedBody]），GUID 仅微信授权可得，故
/// App 仅当用户在设置中填入自己的 GUID 时启用本数据源。
///
/// 签名算法逆向自
/// `wxcourse.jxufe.cn/dir/usr/local/wisdomPlatform/file/jssdk/V1.8/h5_jssdk_V1.8.js`
/// （appSecret 硬编码 `bainian!@#`）：参数（含注入 bn_accessKey=GUID）按键名
/// 排序拼 `k=v&…&bn_secretKey=bainian!@#`，整体 MD5 转大写；请求体剔除
/// bn_accessKey。归档见 reverse_engineering/校历接口.md。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/school_calendar/data/anti_corruption/wxcal_remark_parser.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// base24 字符（JS `Math.random().toString(24)` 同字符集：0-9 + a-n）。
const _base24 = '0123456789abcdefghijklmn';

/// 平台硬编码 appSecret（逆向所得，用于 bn 签名）。
const _bnSecret = 'bainian!@#';

/// 构造带 bn 签名的请求体（不含 bn_accessKey）。
Map<String, dynamic> bnSignedBody({
  required String guid,
  required String appid,
  required Map<String, dynamic> params,
}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rnd = Random();
  final nonce = List.generate(
      14, (_) => _base24[rnd.nextInt(_base24.length)]).join();
  // 参与签名排序与拼接的参数（bn_accessKey 仅用于签名，不入请求体）。
  final signed = <String, dynamic>{
    ...params,
    'appid': appid,
    'username': guid,
    'bn_accessKey': guid,
    'bn_timestamp': ts,
    'bn_nonce': nonce,
  };
  final keys = signed.keys.toList()..sort();
  final joined = [
    for (final k in keys) '$k=${signed[k]}',
    'bn_secretKey=$_bnSecret',
  ].join('&');
  final sign = md5.convert(utf8.encode(joined)).toString().toUpperCase();
  return {
    ...params,
    'appid': appid,
    'username': guid,
    'bn_timestamp': ts,
    'bn_nonce': nonce,
    'bn_sign': sign,
  };
}

/// 小程序校历实时数据源。
class WxcalRemoteDataSource {
  final Dio _dio;

  const WxcalRemoteDataSource(this._dio);

  static const _appid = '1576047674410';
  static const _endpoint = '/interface/api/interface/getSchoolCalendar';

  /// 拉取全部学期官方安排（每学期含 remark HTML，近两年解析为事件）。
  Future<List<WxSemesterArrangement>> fetchAll({required String guid}) async {
    final body = bnSignedBody(
      guid: guid,
      appid: _appid,
      params: const {'pageNum': 1, 'pageSize': 20},
    );
    final resp = await _dio.post<dynamic>(_endpoint, data: body);
    final data = resp.data;
    if (data is! Map) {
      throw StateError('校历接口响应格式异常');
    }
    final code = data['code'];
    if (code != 1) {
      throw StateError('校历接口返回 code=$code：${data['message']}');
    }
    final rows = (data['result']?['result']?['result'] as List?) ?? const [];
    final out = <WxSemesterArrangement>[];
    for (final r in rows.cast<Map>()) {
      out.add(parseWxRemark(
        id: (r['id'] as num).toInt(),
        term: r['term'] as String? ?? '',
        startDate: (r['start_date'] as String).substring(0, 10),
        endDate: (r['end_date'] as String).substring(0, 10),
        remark: r['remark'] as String? ?? '',
      ));
    }
    return out;
  }
}
