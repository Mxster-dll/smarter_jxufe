import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/core/network/cookie_jar.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_recharge.dart';

/// 校方收银台接口异常（message 面向 UI 直显）。
class NetFeeRechargeException extends AppException {
  const NetFeeRechargeException(super.message);
}

/// 校方 WebPay 收银台的**原生实现**：下单 → 取二维码 → 轮询订单状态。
///
/// **为什么要有它**（2026-10-09 · 用户原话「不要内嵌网页，把二维码封装到我们的 UI 里」）：
/// 二维码本来就是**校方服务端生成的一张 jpg**（`resource/qrcode/<订单号>.jpg`），
/// 为了显示它把整张网页嵌进来是多余的。这里用 `dio` 把那条链路复刻出来，
/// UI 只拿 [NetFeeOrder] 与图片字节，其余全是 App 自己的界面。
///
/// **四步链路**（全部真机实测过，缺一步就 403）：
///
/// 1. `GET /WebPay/toRecharge?paytype=3&account=X&amount=Y` —— 拿 `JSESSIONID` 与页面上的
///    `csrftoken` / `validCode`；**这个页面的 URL 就是后面所有请求的 Referer**；
/// 2. `POST /WebPay/submitRecharge`（form）—— **必须带 Referer**，否则
///    `403 Illegal Referer`（实测踩过）；成功回 `302 Location: /WebPay/wxPaySaoma`；
/// 3. `GET /WebPay/wxPaySaoma` —— **订单号只在这个页面里**（`#orderno` 隐藏域）；
///    `Location` 本身不带订单号（订单挂在 `JSESSIONID` 会话上）；
/// 4. `GET /WebPay/checkOrder?orderno=…&ajaxCsrfToken=…` —— 轮询订单状态，
///    `{"result":1,"order":{"orderno":"…","paystate":"3"}}`（`3` = 已支付）。
///    ⚠ `ajaxCsrfToken` **必带**：`pub.js` 的 `$.ajaxSetup` 会给页面上每个 ajax
///    自动加上它，手写请求漏了同样吃 `403 Illegal Referer`（实测踩过）。
///
/// ⚠ 会话是**这一条链自己的**（`self.jxufe.cn` 单域 → [HostCookieJar]），
/// 与 `netFeeDioProvider`（wxcourse 小程序平台，Referer 是 servicewechat）不是同一套，
/// 所以 Dio 也是单独一个（见 `net_fee_providers.dart` 的 `netFeeWebPayDioProvider`）。
class NetFeeRechargeRemoteDataSource {
  NetFeeRechargeRemoteDataSource(this._dio);

  final Dio _dio;

  /// 单域分桶 —— 整条链只认 `self.jxufe.cn` 的 `JSESSIONID`。
  ///
  /// ⚠ **每次下单都换一个新的**（见 [createOrder] 开头）：订单是挂在会话上的，
  /// 复用旧会话会让「换个宽带账号再充」落到上一次的会话里。
  HostCookieJar _jar = HostCookieJar();

  /// 表单页 URL（已去掉 `;jsessionid=`）——**所有请求的 Referer**。
  String? _referer;

  /// `checkOrder` 必带的 ajax token（页面里的 `window.AJAXCSRFTOKEN`）。
  String _ajaxToken = '';

  static final String _host = Uri.parse(kNetFeeWebPayOrigin).host;

  /// 最近一次下单拿到的订单（UI 侧轮询用）。
  NetFeeOrder? get lastOrder => _lastOrder;
  NetFeeOrder? _lastOrder;

  // ---------- 对外三步 ----------

  /// 下单：拿到订单号（二维码由 [fetchQrImage] 取）。
  Future<NetFeeOrder> createOrder({
    required String account,
    required double amount,
  }) async {
    // 每次下单都从**干净会话**开始：订单挂在 JSESSIONID 上，复用旧会话会让
    // 「换个宽带账号再充」落到上一次的会话里。
    _jar = HostCookieJar();
    _referer = null;
    _ajaxToken = '';

    final amountText = fmtYuan(netFeeNormalizeAmount(amount));
    final formUrl =
        '$kNetFeeWebPayOrigin$kNetFeeWebPayPath'
        '?paytype=$kNetFeeWebPayType'
        '&account=${Uri.encodeComponent(account)}'
        '&amount=$amountText';

    // ① 表单页：CSRF / validCode / ajax token / JSESSIONID 都在这一页上。
    final formHtml = await _getText(formUrl);
    final referer = _referer ?? formUrl;
    final csrf = _hiddenValue(formHtml, 'csrftoken');
    final validCode = _hiddenValue(formHtml, 'validCode');
    _ajaxToken = _ajaxCsrfToken(formHtml);
    if (csrf.isEmpty) {
      throw const NetFeeRechargeException('校方充值页没有给出提交令牌，请稍后重试');
    }

    // ② 提交订单（**必须带 Referer**，否则 403）。
    final Response<dynamic> submitted;
    try {
      submitted = await _dio.post<dynamic>(
        '$kNetFeeWebPayOrigin/WebPay/submitRecharge',
        data: <String, String>{
          'csrftoken': csrf,
          'rechargetype': '0',
          'amount': amountText,
          // 「其他」金额走 cardid 为空的分支；档位金额也一样（cardid 只在卡类充值用）。
          'cardid': '',
          'timepacketid': '',
          'timepacketval': '',
          'timepacketcost': '',
          'flowpacketid': '',
          'flowpacketval': '',
          'flowpacketcost': '',
          'validCode': validCode,
          'account': account,
          'paytype': kNetFeeWebPayType,
        },
        options: Options(
          followRedirects: false,
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          headers: _headers(referer),
        ),
      );
    } on DioException catch (e) {
      throw NetFeeRechargeException('提交充值订单失败：${_dioText(e)}');
    }
    _jar.absorbUrl(
      Uri.parse('$kNetFeeWebPayOrigin/WebPay/submitRecharge'),
      submitted.headers['set-cookie'],
    );
    final status = submitted.statusCode ?? 0;
    if (status == 403) {
      throw const NetFeeRechargeException('校方拒绝了这次下单（页面令牌已过期），请重新发起充值');
    }
    if (status >= 400) {
      throw NetFeeRechargeException('提交充值订单失败：HTTP $status');
    }

    // ③ 扫码页：订单号与二维码路径只在这里。
    //    正常是 302 → /WebPay/wxPaySaoma；若服务端直接回了页面（200）就用它自己。
    final location = submitted.headers.value('location');
    final payHtml = (location != null && location.isNotEmpty)
        ? await _getText(_absolutize(location), referer: referer)
        : _asText(submitted.data);
    _ajaxToken = _ajaxCsrfToken(payHtml).isNotEmpty
        ? _ajaxCsrfToken(payHtml)
        : _ajaxToken;

    final orderNo = _idValue(payHtml, 'orderno');
    if (orderNo.isEmpty) {
      throw const NetFeeRechargeException(
        '校方没有返回订单号 —— 通常是金额或账号不被接受（金额需在校方允许范围内）',
      );
    }
    final order = NetFeeOrder(
      orderNo: orderNo,
      amount: netFeeNormalizeAmount(amount),
      account: account,
    );
    _lastOrder = order;
    return order;
  }

  /// 问一次订单状态（返回 `paystate`；[kNetFeePayStatePaid] = 已支付）。
  Future<String> fetchPayState(String orderNo) async {
    final query =
        '?orderno=${Uri.encodeComponent(orderNo)}'
        '&ajaxCsrfToken=${Uri.encodeComponent(_ajaxToken)}'
        '&t=${DateTime.now().millisecondsSinceEpoch}';
    final text = await _getText(
      '$kNetFeeWebPayOrigin/WebPay/checkOrder$query',
      referer: _referer,
    );
    final decoded = _jsonOf(text);
    final order = decoded is Map ? decoded['order'] : null;
    if (order is! Map) return '';
    return order['paystate']?.toString() ?? '';
  }

  /// 取二维码图片（服务端生成的那张 jpg）。
  Future<Uint8List> fetchQrImage(String orderNo) async {
    try {
      final resp = await _dio.get<List<int>>(
        netFeeQrCodeUrl(orderNo),
        options: Options(
          responseType: ResponseType.bytes,
          headers: _headers(_referer),
        ),
      );
      final bytes = resp.data;
      if (bytes == null || bytes.isEmpty) {
        throw const NetFeeRechargeException('二维码图片是空的，请点「刷新二维码」重试');
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (e) {
      throw NetFeeRechargeException('二维码图片取不回来：${_dioText(e)}');
    }
  }

  // ---------- 请求 ----------

  Map<String, dynamic> _headers(String? referer) {
    final cookie = _jar.headerFor(_host);
    return <String, dynamic>{
      if (cookie.isNotEmpty) 'Cookie': cookie,
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
    };
  }

  /// 取文本（HTML / JSON 都走它）——**统一 plain**，免得被 content-type 坑。
  Future<String> _getText(String url, {String? referer}) async {
    try {
      final resp = await _dio.get<dynamic>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: _headers(referer ?? _referer),
        ),
      );
      _jar.absorbUrl(Uri.parse(url), resp.headers['set-cookie']);
      // 第一次成功拿到页面时记下「最终地址」当 Referer（可能带 ;jsessionid=）。
      final finalUrl = resp.realUri.toString();
      _referer ??= finalUrl.split(';').first;
      final status = resp.statusCode ?? 0;
      if (status >= 400) {
        throw NetFeeRechargeException(
          status == 403
              ? '校方拒绝了这次请求（页面令牌或会话已过期），请重新发起充值'
              : '校方返回 HTTP $status',
        );
      }
      return _asText(resp.data);
    } on DioException catch (e) {
      throw NetFeeRechargeException('连不上校方充值页：${_dioText(e)}');
    }
  }

  static String _asText(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    if (data is List<int>) return utf8.decode(data, allowMalformed: true);
    return data.toString();
  }

  /// 把 `Location`（可能是 `/WebPay/wxPaySaoma` 或相对路径）补成绝对地址。
  static String _absolutize(String location) {
    if (location.startsWith('http')) return location;
    final path = location.startsWith('/') ? location : '/$location';
    return '$kNetFeeWebPayOrigin$path';
  }

  static dynamic _jsonOf(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  static String _hiddenValue(String html, String name) =>
      RegExp('name="$name"\\s+value="([^"]*)"').firstMatch(html)?.group(1) ??
      '';

  static String _idValue(String html, String id) =>
      RegExp('id="$id"\\s+value="([^"]*)"').firstMatch(html)?.group(1) ?? '';

  static String _ajaxCsrfToken(String html) =>
      RegExp('''AJAXCSRFTOKEN\\s*=\\s*['"]([^'"]+)['"]''').firstMatch(html)?.group(1) ??
      '';

  String _dioText(DioException e) {
    if (e.error is FormatException) return '服务响应格式异常';
    final status = e.response?.statusCode;
    if (status != null) return 'HTTP $status';
    return e.message ?? '网络请求失败';
  }
}
