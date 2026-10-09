import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_recharge.dart';

/// 网费接口异常（message 面向 UI 直显）。
class NetFeeApiException extends AppException {

  const NetFeeApiException(super.message);
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
      throw NetFeeApiException('平台账号换取失败：${_message(data, 'code $code')}');
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
      throw NetFeeApiException('该账号不支持校园网账户（E14）');
    }
    if (code != 'E00') {
      throw NetFeeApiException(
        '校园网余额查询失败：${_message(data, code?.toString() ?? 'E99')}',
      );
    }
    final balance = double.tryParse(data['balance']?.toString() ?? '');
    if (balance == null) {
      throw const NetFeeApiException('校园网余额响应缺少数值');
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
      throw NetFeeApiException(
        '充值记录查询失败：${_message(data, 'code ${data['code']}')}',
      );
    }
    final list = data['list'];
    if (list is! List) return const [];
    final records = <NetFeeRecord>[];
    for (final item in list) {
      if (item is Map) {
        records.add(
          NetFeeRecord.fromJson(item.map((k, v) => MapEntry(k.toString(), v))),
        );
      }
    }
    records.sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return records;
  }

  /// 「网络服务」平台应用 id（H5「用户自助服务系统」：上网记录 / 历史账单 /
  /// 充值明细 / 业务办理记录）。
  ///
  /// 完整的网络服务实现（登录、会话、全部读写接口）在
  /// `features/network_service/data/datasources/network_service_remote_datasource.dart`，
  /// 本常量只作为该 appId 的登记处（网费与网络服务同属 wxcourse 平台域）。
  static const String networkServiceAppId = '1575336885141';

  // ---------- 充值方式（微信 / 校园卡）· 2026-10-09 四轮 ----------
  //
  // 口径来源 = **智慧江财小程序「网费充值」页**（`pages/modules/developer/wfcz/recharge/view.js`，
  // 从 PC 微信的 wxapkg 解包读出来的，版本 145）：
  //
  // ```js
  // getPayTypeList() → POST /interface/api/interface/getWfczPayType {pageNum,pageSize,accept}
  //    → {code:1, result:{result:{result:[{dict_key,dict_value,desc}]}}}
  //      dict_key = 'weixin' | 'card'，**dict_value 就是该方式的充值接口地址**
  // recharge(amount) → POST <dict_value> {username, openId, total_fee}
  //    weixin → 回微信支付参数（小程序走 wx.requestPayment）
  //    card   → 回 {code:0} 即「网费充值成功！」（直接从校园卡余额扣）
  // chargeTypeChange: 非 weixin 时锁死账号 → '校园卡扣费只能给自己充值'
  // ```
  //
  // ⚠ **校园卡这条路 App 侧用的是「小程序那套接口」（wxcourse 域）**，与微信那条
  // （走 Dr.COM `self.jxufe.cn` 的二维码）不是同一套 —— 因为 Dr.COM 的 WebPay
  // **不提供校园卡**（它的 paytype 只有 微信/支付宝/PayPal/银联，实测只渲染微信）。

  /// 充值方式列表（只读；`dict_value` 是充值接口地址，别写死）。
  Future<List<WfczChargeType>> fetchChargeTypes() async {
    final resp = await _dio.post<dynamic>(
      '/interface/api/interface/getWfczPayType',
      data: <String, dynamic>{'pageNum': 1, 'pageSize': 20, 'accept': 'accept'},
    );
    final data = _body(resp);
    // 三层嵌套是服务端原样（`result.result.result`），别「优化」掉。
    final result = data['result'];
    final inner = result is Map ? result['result'] : null;
    final list = inner is Map ? inner['result'] : null;
    if (list is! List) return const <WfczChargeType>[];
    return <WfczChargeType>[
      for (final item in list)
        if (item is Map)
          WfczChargeType(
            key: item['dict_key']?.toString() ?? '',
            url: item['dict_value']?.toString() ?? '',
            desc: item['desc']?.toString() ?? '',
          ),
    ]..removeWhere((t) => t.key.isEmpty || t.url.isEmpty);
  }

  /// 小程序侧的网费身份：`enc`（= 加密 userId）+ `openId`（都在 `checkAppAuth` 里）。
  ///
  /// ⚠ `openId` **只能在 `pageUrl` 的 query 里拿**（它是 44 字符的加密串，含 `+` / `=`，
  /// 交给 form 编码时别自己拼字符串）。小程序侧会对它做 `@`→`=`、`!`→`+` 的还原，
  /// 但 `checkAppAuth` 直接给的就是原始值，这里**不需要**再做那一步。
  Future<WfczIdentity> fetchWfczIdentity(String guid) async {
    final trimmed = guid.trim();
    if (trimmed.isEmpty) {
      throw const NetFeeApiException('未配置微信平台标识（GUID）');
    }
    final resp = await _dio.get<dynamic>(
      checkAppAuthUrl,
      queryParameters: <String, dynamic>{
        'appid': appId,
        'platformUsername': trimmed,
      },
    );
    final data = _body(resp);
    final result = data['result'];
    if (result is! Map) {
      throw const NetFeeApiException('平台账号换取失败：响应缺少 result');
    }
    final enc = result['username']?.toString() ?? '';
    final pageUrl = result['pageUrl']?.toString() ?? '';
    if (enc.isEmpty) {
      throw const NetFeeApiException('平台账号换取失败：未返回加密账号');
    }
    // ⚠ **必须从 rawQuery 手动取**：`Uri.queryParameters` 是 form 语义，会把
    // openId 里合法的 `+` 解成空格（实测 `OID+AB=` → `OID AB=`）。那是 base64 串，
    // `+` 是**真实字符** —— 解错了校方直接拒（而且报错未必说清是参数问题）。
    final rawQuery = Uri.tryParse(pageUrl)?.query ?? '';
    final match = RegExp(r'(?:^|&)openId=([^&]*)').firstMatch(rawQuery);
    final openId = match == null ? '' : Uri.decodeComponent(match.group(1)!);
    return WfczIdentity(enc: enc, openId: openId);
  }

  /// **校园卡支付**网费：直接从校园卡余额扣款。
  ///
  /// ⚠⚠ 这是**真扣款**：校方接口一提交就扣，没有密码、没有二次确认、也没有「未支付」
  /// 这种中间态。所以 UI 上必须自己给足二次确认（见 `net_fee_recharge_sheet.dart`）。
  ///
  /// 返回 `null` = 成功；非 null = 服务端给的原因（直接上屏）。
  Future<String?> payByCampusCard({
    required WfczIdentity identity,
    required double amount,
    required String payUrl,
  }) async {
    final resp = await _dio.post<dynamic>(
      payUrl,
      data: <String, dynamic>{
        'username': identity.enc,
        'openId': identity.openId,
        'total_fee': fmtYuan(netFeeNormalizeAmount(amount)),
      },
    );
    final data = _body(resp);
    final code = data['code'];
    if (code == 0 || code == '0') return null;
    return _message(data, '校园卡支付失败（code $code）');
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
