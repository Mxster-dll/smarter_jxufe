/// 智慧江财小程序校历实时数据源（需平台 GUID）。
///
/// 接口：POST https://wxcourse.jxufe.cn/interface/api/interface/getSchoolCalendar
/// 服务端强鉴权：请求须带平台用户 GUID（username 参数）+ bn 三参数签名
/// （timestamp/nonce/sign，见 [bnSignedBody]），GUID 仅微信授权可得，故
/// App 仅当用户在设置中填入自己的 GUID 时启用本数据源。
///
/// 签名算法逆向自
/// `wxcourse.jxufe.cn/dir/usr/local/wisdomPlatform/file/jssdk/V1.8/h5_jssdk_V1.8.js`：
/// 参数（含注入 bn_accessKey=GUID）按键名排序拼
/// `k=v&…&bn_secretKey=<平台 appSecret>`，整体 MD5 转大写；请求体剔除 bn_accessKey。
///
/// ⚠ **appSecret 不写在本仓库里**（2026-10-10 改）。它原本是硬编码常量，但那等于把
/// 第三方平台的签名密钥随公开仓库一起发出去（[docs/agents/34] 的口径）。
/// 现在两条路注入，都没有时**实时源直接不可用**、由仓库层回退内置离线快照
/// （见 [WxcalRepository.hasLive]）：
///   · 编译期：`--dart-define=BN_APP_SECRET=…`
///     或 `--dart-define-from-file=config.local.json`（该文件已 gitignore）；
///   · 测试/调用方：把密钥当参数传给 [bnSignedBody] 或数据源构造函数。
/// 归档见 reverse_engineering/校历接口.md。
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/school_calendar/data/anti_corruption/wxcal_remark_parser.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// base24 字符（JS `Math.random().toString(24)` 同字符集：0-9 + a-n）。
const _base24 = '0123456789abcdefghijklmn';

/// 平台 appSecret：**只从构建参数来，仓库里不留值**。
///
/// 用法：`flutter run --dart-define=BN_APP_SECRET=<平台 appSecret>`（见文件头注释）。
/// 公开常量是为了让 provider 层能原样透传给 [bnSignedBody] / 数据源构造函数 ——
/// 值本身仍然只存在于**构建参数**里，不落盘、不入库。
const String bnAppSecret = String.fromEnvironment('BN_APP_SECRET');

/// 当前构建是否带了平台 appSecret。
///
/// `false` = 实时校历 / 请假走不通（服务端会拒签），调用方应回退离线快照。
bool get bnSecretConfigured => bnAppSecret.trim().isNotEmpty;

/// 实时源能否真正走通 = **平台 GUID 与 appSecret 都齐**。
///
/// 这是「实时可用性」的唯一判据，仓库层（`WxcalRepository.hasLive`）与界面
/// （校历页的「实时 / 内置」角标）都调它 —— 在此之前界面只看 GUID，
/// 于是**缺密钥时数据其实来自离线快照、界面却写着「实时」**（2026-10-10 修）。
bool canUseLiveSource(String? guid) =>
    guid != null && guid.trim().isNotEmpty && bnSecretConfigured;

/// 构造带 bn 签名的请求体（不含 bn_accessKey，也不含 bn_secretKey）。
///
/// [secret] 为空时直接抛 [StateError]：**宁可当场报错，也不要发一个必然被服务端
/// 判为「签名篡改」的请求**（那样错误会以 `code 10005` 的形式绕一大圈才浮现）。
/// 不传 [secret] 时回落到构建参数 `BN_APP_SECRET`（见文件头注释）。
Map<String, dynamic> bnSignedBody({
  required String guid,
  required String appid,
  required Map<String, dynamic> params,
  String? secret,
}) {
  final key = (secret ?? bnAppSecret).trim();
  if (key.isEmpty) {
    throw StateError(
      '缺少平台 appSecret：bn 签名算不出来。请用 '
      '--dart-define=BN_APP_SECRET=…（或 --dart-define-from-file=config.local.json）'
      '重新构建；仓库里刻意不留该值。',
    );
  }
  final ts = DateTime.now().millisecondsSinceEpoch;
  final rnd = Random();
  final nonce = List.generate(
      14, (_) => _base24[rnd.nextInt(_base24.length)]).join();
  // 参与签名排序与拼接的参数（bn_accessKey 仅用于签名，不入请求体）。
  final sign = bnSignOf(
    secret: key,
    guid: guid,
    appid: appid,
    params: params,
    timestampMs: ts,
    nonce: nonce,
  );
  return {
    ...params,
    'appid': appid,
    'username': guid,
    'bn_timestamp': ts,
    'bn_nonce': nonce,
    'bn_sign': sign,
  };
}

/// 算 bn 签名（**纯函数**：时间戳与 nonce 由调用方给 → 可用固定向量对拍）。
///
/// 口径（逆向自小程序 `h5_jssdk_V1.8.js`）：参与签名的字段 = 业务参数 + `appid`
/// + `username`(=GUID) + `bn_accessKey`(=GUID) + `bn_timestamp` + `bn_nonce`；
/// **按键名升序**拼 `k=v&…`，末尾再拼 `bn_secretKey=<appSecret>`，
/// 整体 MD5 后转**大写** 32 位十六进制。
///
/// ⚠ 两个最容易写错、且错了只会得到服务端一句「参数非法篡改」的点，都被测试钉住：
/// `bn_accessKey` **只进签名、不进请求体**；密钥拼在**末尾**而不是按字母序插进去。
String bnSignOf({
  required String secret,
  required String guid,
  required String appid,
  required Map<String, dynamic> params,
  required int timestampMs,
  required String nonce,
}) {
  final signed = <String, dynamic>{
    ...params,
    'appid': appid,
    'username': guid,
    'bn_accessKey': guid,
    'bn_timestamp': timestampMs,
    'bn_nonce': nonce,
  };
  final keys = signed.keys.toList()..sort();
  final joined = [
    for (final k in keys) '$k=${signed[k]}',
    'bn_secretKey=$secret',
  ].join('&');
  return md5.convert(utf8.encode(joined)).toString().toUpperCase();
}

/// 小程序校历实时数据源。
class WxcalRemoteDataSource {
  final Dio _dio;

  /// 平台 appSecret（不传则用构建参数 `BN_APP_SECRET`）。
  final String? secret;

  const WxcalRemoteDataSource(this._dio, {this.secret});

  static const _appid = '1576047674410';
  static const _endpoint = '/interface/api/interface/getSchoolCalendar';

  /// 拉取全部学期官方安排（每学期含 remark HTML，近两年解析为事件）。
  ///
  /// [secret] 覆盖构造函数里的密钥（仓库层把「本构建的 appSecret」显式传下来，
  /// 免得仓库与实际签名用的密钥各是一份）。
  Future<List<WxSemesterArrangement>> fetchAll({
    required String guid,
    String? secret,
  }) async {
    final body = bnSignedBody(
      guid: guid,
      appid: _appid,
      params: const {'pageNum': 1, 'pageSize': 20},
      secret: secret ?? this.secret,
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
