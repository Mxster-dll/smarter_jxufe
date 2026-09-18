import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/network_service/domain/network_service_models.dart';

/// 网络服务接口异常（message 面向 UI 直显）。
class NetworkServiceException implements Exception {
  final String message;

  /// 是否需要用户先去设置平台标识（GUID）。
  final bool needGuid;

  const NetworkServiceException(this.message, {this.needGuid = false});

  @override
  String toString() => message;
}

/// 「网络服务」（智慧江财「生活 > 网络服务」）远程数据源。
///
/// 服务本体 = 广州热点 Dr.COM「用户自助服务系统」（H5，挂在
/// `https://wxcourse.jxufe.cn/1575336885141/`，与小程序同一套）。
///
/// **自动登录链（2026-09-16 打通，实测有效）**：
/// 1. `checkAppAuth(appid=1575336885141, platformUsername=<GUID>)` → `result.username`
///    （加密学号 enc）与 `result.pageUrl`（带 cardinfo / openId 的签名登录地址）；
/// 2. `GET <pageUrl>&userId=<urlencode(enc)>` → **302** 且 `Set-Cookie: JSESSIONID=…`；
///    ⚠ 关键就是补上 `userId`：小程序 `pages/modules/app/detail/view` 会追加
///    `userId/jwtToken/accessKey/colleageCode/jssdk_url/appid/v`，其中**只有 `userId`
///    是登录必需的**（实测：少了它一律 302 回 `/login/`）。
/// 3. 之后所有业务请求带 `Cookie: JSESSIONID=…` 即可（服务端也做 `;jsessionid=`
///    路径重写，但只靠 Cookie 就够，Dart 侧无需处理 URL 重写）。
///
/// **会话失效判定**：会话过期时业务请求会 302 到登录页 —— 只要响应里有
/// 「用户自助服务系统」且带 `name="password"` 即视为失效，自动重登一次并重试。
///
/// **CSRF**：写操作要求每页现取的 token（`AJAXCSRFTOKEN = '…'` 或隐藏域
/// `name="csrftoken" value="…"`），故写操作一律**先 GET 页面取 token 再 POST**。
class NetworkServiceRemoteDataSource {
  NetworkServiceRemoteDataSource(this._dio);

  final Dio _dio;

  /// 平台应用 id（「网络服务」H5）。
  static const String appId = '1575336885141';

  /// checkAppAuth 在平台管理域（绝对 URL）。
  static const String checkAppAuthUrl =
      'https://wxcourse.jxufe.cn/platForm/api/littleProgram/application/checkAppAuth';

  /// 自助服务系统根路径。
  static const String serviceRoot = 'https://wxcourse.jxufe.cn/1575336885141';

  /// 登录页特征（用于判定会话失效）。
  static const String _loginPageTitle = '用户自助服务系统';
  static const String _loginPageMarker = 'name="password"';

  /// 当前会话（Cookie）与所属 GUID；登录一次后复用。
  String? _jsessionId;
  String? _sessionGuid;

  /// 是否有可用会话（测试与 UI 调试用）。
  bool get hasSession => _jsessionId != null;

  /// 会话是否属于该 GUID。
  bool sessionMatches(String guid) =>
      _jsessionId != null && _sessionGuid == guid;

  /// 丢弃会话（切换账号 / 手动重登时调用）。
  void resetSession() {
    _jsessionId = null;
    _sessionGuid = null;
  }

  // ---------- 会话 ----------

  /// 确保存在可用会话（已登录则直接返回）。
  Future<void> ensureSession(String guid) async {
    if (sessionMatches(guid)) return;
    await login(guid);
  }

  /// 登录一次：checkAppAuth 换签名地址 → 带 `userId` 换取 JSESSIONID。
  Future<void> login(String guid) async {
    final trimmed = guid.trim();
    if (trimmed.isEmpty) {
      throw const NetworkServiceException('未配置微信平台标识（GUID）', needGuid: true);
    }
    final Map<String, dynamic> result;
    try {
      final resp = await _dio.get<dynamic>(
        checkAppAuthUrl,
        queryParameters: <String, dynamic>{
          'appid': appId,
          'platformUsername': trimmed,
        },
      );
      result = networkMap(_jsonOf(resp)['result']);
    } on DioException catch (e) {
      throw NetworkServiceException('网络服务登录失败：${_dioText(e)}');
    }
    final enc = networkStr(result['username']);
    final pageUrl = networkStr(result['pageUrl']);
    if (enc.isEmpty || pageUrl.isEmpty) {
      throw const NetworkServiceException('网络服务登录失败：平台未返回签名地址');
    }
    final loginUrl =
        '$pageUrl${pageUrl.contains('?') ? '&' : '?'}userId=${Uri.encodeComponent(enc)}';
    final Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        loginUrl,
        options: Options(followRedirects: false, validateStatus: (_) => true),
      );
    } on DioException catch (e) {
      throw NetworkServiceException('网络服务登录失败：${_dioText(e)}');
    }
    final jsid = _readJsessionId(resp.headers);
    if (jsid == null) {
      throw const NetworkServiceException('网络服务登录失败：未取得会话（可能平台标识已失效）');
    }
    _jsessionId = jsid;
    _sessionGuid = trimmed;
  }

  /// 从响应头里取 JSESSIONID（`set-cookie` 可能是多值列表）。
  String? _readJsessionId(Headers headers) {
    final raw = headers['set-cookie'];
    final candidates = <String>[
      if (raw != null) ...raw,
      if (headers.value('Set-Cookie') != null) headers.value('Set-Cookie')!,
    ];
    for (final line in candidates) {
      final match = RegExp(
        r'JSESSIONID=([^;,\s]+)',
        caseSensitive: false,
      ).firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
  }

  // ---------- 通用请求 ----------

  /// 业务 GET（JSON / 数组 / 对象都原样返回）。
  ///
  /// 会话失效（被踢回登录页）时自动重登一次并重试。
  Future<dynamic> _getJson(
    String guid,
    String path, {
    Map<String, dynamic>? query,
  }) async {
    await ensureSession(guid);
    var resp = await _rawGet(path, query);
    if (_isLoginPage(resp)) {
      resetSession();
      await login(guid);
      resp = await _rawGet(path, query);
      if (_isLoginPage(resp)) {
        throw const NetworkServiceException('网络服务会话已失效，请稍后重试');
      }
    }
    return _decodeJson(resp.data);
  }

  /// 业务 GET（要页面 HTML 原文）。
  Future<String> _getHtml(
    String guid,
    String path, {
    Map<String, dynamic>? query,
  }) async {
    await ensureSession(guid);
    var resp = await _rawGet(path, query, acceptJson: false);
    if (_isLoginPage(resp)) {
      resetSession();
      await login(guid);
      resp = await _rawGet(path, query, acceptJson: false);
      if (_isLoginPage(resp)) {
        throw const NetworkServiceException('网络服务会话已失效，请稍后重试');
      }
    }
    return resp.data?.toString() ?? '';
  }

  Future<Response<dynamic>> _rawGet(
    String path,
    Map<String, dynamic>? query, {
    bool acceptJson = true,
  }) async {
    final url = path.startsWith('http') ? path : '$serviceRoot/$path';
    try {
      return await _dio.get<dynamic>(
        url,
        queryParameters: query,
        options: Options(
          followRedirects: false,
          validateStatus: (_) => true,
          // ⚠ 统一按纯文本拿：这套服务端有接口**不回 Content-Type**（见 [_decodeJson]），
          // 交给 Dio 自动判定会漏解析成 String。
          responseType: ResponseType.plain,
          headers: <String, dynamic>{
            if (_jsessionId != null) 'Cookie': 'JSESSIONID=$_jsessionId',
            if (acceptJson) 'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$serviceRoot/dashboard',
          },
        ),
      );
    } on DioException catch (e) {
      throw NetworkServiceException('网络服务请求失败：${_dioText(e)}');
    }
  }

  /// 业务 POST（表单）。
  Future<dynamic> _postForm(
    String guid,
    String path,
    Map<String, dynamic> form,
  ) async {
    await ensureSession(guid);
    var resp = await _rawPost(path, form);
    if (_isLoginPage(resp)) {
      resetSession();
      await login(guid);
      resp = await _rawPost(path, form);
      if (_isLoginPage(resp)) {
        throw const NetworkServiceException('网络服务会话已失效，请稍后重试');
      }
    }
    return _decodeJson(resp.data);
  }

  /// ⚠ **必须自己解码**：这套服务端有一半接口**不回 `Content-Type`**  /// （实测 `dashboard/getLoginHistory`、`bill/getMonthPay`、`bill/getPayMent`、
  /// `bill/getOperatorLog` 都没有），Dio 便不会做 JSON 解码 → 拿到 String，
  /// 于是 `networkList(String)` 静默变成空列表 —— 界面显示「暂无记录」，但服务端其实有数据
  /// （2026-09-16 真机验收时踩到：近期上网记录显示空态，python 直取却有 5 条）。
  /// 所以全链路走 `ResponseType.plain`，这里按正文首字符判 JSON。
  static dynamic _decodeJson(dynamic data) {
    if (data is Map || data is List) return data;
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return jsonDecode(trimmed);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  Future<Response<dynamic>> _rawPost(
    String path,
    Map<String, dynamic> form,
  ) async {
    final url = path.startsWith('http') ? path : '$serviceRoot/$path';
    try {
      return await _dio.post<dynamic>(
        url,
        data: form,
        options: Options(
          followRedirects: false,
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
          contentType: Headers.formUrlEncodedContentType,
          headers: <String, dynamic>{
            if (_jsessionId != null) 'Cookie': 'JSESSIONID=$_jsessionId',
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$serviceRoot/dashboard',
          },
        ),
      );
    } on DioException catch (e) {
      throw NetworkServiceException('网络服务请求失败：${_dioText(e)}');
    }
  }

  bool _isLoginPage(Response<dynamic> resp) {
    final body = resp.data?.toString() ?? '';
    return body.contains(_loginPageTitle) && body.contains(_loginPageMarker);
  }

  // ---------- 读：账号 / 在线 / 记录 ----------

  /// 账号概览（`/dashboard` 页内嵌 `window.user`）+ 该页 csrftoken。
  Future<NetworkAccount> fetchAccount(String guid) async {
    final html = await _getHtml(guid, 'dashboard');
    final json = extractUserJson(html);
    if (json == null) {
      throw const NetworkServiceException('网络服务页面结构异常：未找到账号信息');
    }
    return NetworkAccount.fromUserJson(json);
  }

  /// 当前在线会话（可强制下线）。
  Future<List<NetworkOnlineSession>> fetchOnlineSessions(String guid) async {
    final data = await _getJson(guid, 'dashboard/getOnlineList');
    return [
      for (final item in networkList(data))
        if (item is Map) NetworkOnlineSession.fromJson(networkMap(item)),
    ];
  }

  /// 近期上网记录（首页表，最多 5 条）。
  Future<List<NetworkLoginRecord>> fetchLoginHistory(String guid) async {
    final data = await _getJson(guid, 'dashboard/getLoginHistory');
    return [
      for (final row in networkList(data))
        if (row is List) NetworkLoginRecord.fromRow(row),
    ];
  }

  /// 上网记录明细（**必须带日期范围**，否则服务端返回空）。
  Future<List<NetworkUsageRecord>> fetchUsageRecords(
    String guid, {
    required DateTime from,
    required DateTime to,
  }) async {
    final data = await _getJson(
      guid,
      'bill/getUserOnlineLog',
      query: <String, dynamic>{
        'startTime': formatDate(from),
        'endTime': formatDate(to),
      },
    );
    final map = networkMap(data);
    return [
      for (final item in networkList(map['rows']))
        if (item is Map) NetworkUsageRecord.fromJson(networkMap(item)),
    ];
  }

  /// 历史账单（**必须带年份**，否则返回空对象）。
  Future<NetworkMonthBills> fetchMonthBills(String guid, int year) async {
    final data = networkMap(
      await _getJson(
        guid,
        'bill/getMonthPay',
        query: <String, dynamic>{'year': year},
      ),
    );
    return NetworkMonthBills(
      year: year,
      items: [
        for (final row in networkList(data['rows']))
          if (row is List) NetworkMonthBill.fromRow(row),
      ],
      summary: NetworkMonthBillSummary.fromJson(networkMap(data['summary'])),
    );
  }

  /// 充值明细（`bill/getPayMent`，列 = 时间 / 类型 / 金额 / 受理终端 / 备注）。
  Future<List<NetworkPayment>> fetchPayments(String guid) async {
    final data = networkMap(await _getJson(guid, 'bill/getPayMent'));
    return [
      for (final row in networkList(data['rows']))
        if (row is List) NetworkPayment.fromRow(row),
    ];
  }

  /// 业务办理记录（`bill/getOperatorLog`）。
  Future<List<NetworkOperatorLog>> fetchOperatorLogs(String guid) async {
    final data = networkMap(await _getJson(guid, 'bill/getOperatorLog'));
    return [
      for (final row in networkList(data['rows']))
        if (row is List) NetworkOperatorLog.fromRow(row),
    ];
  }

  /// 我的设备（`service/getMacList`）。
  Future<List<NetworkDevice>> fetchDevices(String guid) async {
    final data = networkMap(
      await _getJson(
        guid,
        'service/getMacList',
        query: <String, dynamic>{'pageSize': 100, 'pageNumber': 1},
      ),
    );
    return [
      for (final row in networkList(data['rows']))
        if (row is List) NetworkDevice.fromRow(row),
    ];
  }

  /// 资费介绍（`service/getUserGroups`）。
  Future<List<NetworkPlan>> fetchPlans(String guid) async {
    final data = networkMap(await _getJson(guid, 'service/getUserGroups'));
    return [
      for (final item in networkList(data['rows']))
        if (item is Map) NetworkPlan.fromJson(networkMap(item)),
    ];
  }

  /// 报停记录。
  Future<List<NetworkOperationLog>> fetchStopLogs(String guid) async =>
      _fetchOperationLogs(guid, 'service/getStopLog');

  /// 复通记录。
  Future<List<NetworkOperationLog>> fetchReopenLogs(String guid) async =>
      _fetchOperationLogs(guid, 'service/goReopenLog');

  Future<List<NetworkOperationLog>> _fetchOperationLogs(
    String guid,
    String path,
  ) async {
    final data = networkMap(
      await _getJson(
        guid,
        path,
        query: <String, dynamic>{'pageSize': 50, 'pageNumber': 1},
      ),
    );
    return [
      for (final item in networkList(data['rows']))
        if (item is Map) NetworkOperationLog.fromJson(networkMap(item)),
    ];
  }

  /// 预约套餐日志。
  Future<List<NetworkPackageLog>> fetchPackageLogs(String guid) async {
    final data = networkMap(
      await _getJson(
        guid,
        'service/packageLog',
        query: <String, dynamic>{'pageSize': 50, 'pageNumber': 1},
      ),
    );
    return [
      for (final item in networkList(data['rows']))
        if (item is Map) NetworkPackageLog.fromJson(networkMap(item)),
    ];
  }

  /// 预约套餐页可选套餐 + 下单 csrftoken（页面卡片是**唯一权威的可选项**）。
  Future<NetworkPackageOptions> fetchPackageOptions(String guid) async {
    final html = await _getHtml(guid, 'service/package');
    return NetworkPackageOptions(
      options: extractPackageOptions(html),
      csrfToken: extractCsrfToken(html),
    );
  }

  // ---------- 写操作 ----------

  /// 强制下线某在线会话（`dashboard/tooffline?sessionid=`）。
  Future<NetworkActionResult> forceOffline(
    String guid,
    String sessionId,
  ) async {
    final data = await _getJson(
      guid,
      'dashboard/tooffline',
      query: <String, dynamic>{'sessionid': sessionId},
    );
    return _actionResult(data, '已强制下线');
  }

  /// 账号报停：`immediate` 立即（flag=1）/ 预约（flag=2，本周期结束后停机）。
  Future<NetworkActionResult> stopAccount(
    String guid, {
    required bool immediate,
  }) async {
    final token = extractAjaxCsrfToken(await _getHtml(guid, 'service/goStop'));
    final data = await _postForm(guid, 'service/stop', <String, dynamic>{
      'ajaxCsrfToken': token,
      'flag': immediate ? '1' : '2',
    });
    return _actionResult(data, immediate ? '已提交立即报停' : '已提交预约报停');
  }

  /// 取消预约报停。
  Future<NetworkActionResult> cancelPendingStop(String guid) async {
    final token = extractAjaxCsrfToken(await _getHtml(guid, 'service/goStop'));
    final data = await _postForm(guid, 'service/undoStop', <String, dynamic>{
      'ajaxCsrfToken': token,
    });
    return _actionResult(data, '已取消预约报停');
  }

  /// 账号复通：`immediate` 立即（flag=1）/ 预约（flag=2 + date，日期须 ≥ 明天）。
  Future<NetworkActionResult> reopenAccount(
    String guid, {
    required bool immediate,
    DateTime? date,
  }) async {
    final token = extractAjaxCsrfToken(
      await _getHtml(guid, 'service/goReopen'),
    );
    final data = await _postForm(guid, 'service/reOpen', <String, dynamic>{
      'flag': immediate ? '1' : '2',
      if (!immediate && date != null) 'date': formatDate(date),
      'ajaxCsrfToken': token,
    });
    return _actionResult(data, immediate ? '已提交立即复通' : '已提交预约复通');
  }

  /// 取消预约复通。
  Future<NetworkActionResult> cancelPendingReopen(String guid) async {
    final token = extractAjaxCsrfToken(
      await _getHtml(guid, 'service/goReopen'),
    );
    final data = await _postForm(guid, 'service/undoReOpen', <String, dynamic>{
      'ajaxCsrfToken': token,
    });
    return _actionResult(data, '已取消预约复通');
  }

  /// 预约套餐（`serid` = 套餐页卡片的 `data-package`）。
  Future<NetworkActionResult> reservePackage(
    String guid,
    String serviceId,
  ) async {
    final token = extractCsrfToken(await _getHtml(guid, 'service/package'));
    final data = await _postForm(guid, 'service/doPackage', <String, dynamic>{
      'csrftoken': token,
      'serid': serviceId,
    });
    return _actionResult(data, '已提交预约套餐');
  }

  /// 取消预约套餐。
  Future<NetworkActionResult> cancelPendingPackage(String guid) async {
    final token = extractAjaxCsrfToken(await _getHtml(guid, 'service/package'));
    final data = await _postForm(guid, 'service/undoPackage', <String, dynamic>{
      'ajaxCsrfToken': token,
    });
    return _actionResult(data, '已取消预约套餐');
  }

  /// 解绑设备（`service/unbindmac?mac=…&ajaxCsrfToken=…`）。
  Future<NetworkActionResult> unbindDevice(String guid, String mac) async {
    final token = extractAjaxCsrfToken(await _getHtml(guid, 'service/myMac'));
    final data = await _getJson(
      guid,
      'service/unbindmac',
      query: <String, dynamic>{'mac': mac, 'ajaxCsrfToken': token},
    );
    return _actionResult(data, '已解绑该设备');
  }

  /// 修改上网密码（`setting/changePasswordMethod`，6–16 位、两次输入一致）。
  Future<NetworkActionResult> changePassword(
    String guid, {
    required String oldPassword,
    required String newPassword,
  }) async {
    final token = extractCsrfToken(
      await _getHtml(guid, 'setting/changePassword'),
    );
    final data =
        await _postForm(guid, 'setting/changePasswordMethod', <String, dynamic>{
          'csrftoken': token,
          'oldPassword': oldPassword,
          'newPassword': newPassword,
          'confirmPassword': newPassword,
        });
    return _actionResult(data, '密码修改成功');
  }

  /// 保存个人资料（`setting/updateUserSecurity`）。
  Future<NetworkActionResult> updateProfile(
    String guid, {
    required String phone,
    required String email,
    required String address,
    required String company,
    String checkCode = '',
  }) async {
    final token = extractCsrfToken(await _getHtml(guid, 'setting/personList'));
    final data =
        await _postForm(guid, 'setting/updateUserSecurity', <String, dynamic>{
          'csrftoken': token,
          'checkCode': checkCode,
          'userCompany': company,
          'userPhone': phone,
          'userEmail': email,
          'userAddress': address,
        });
    return _actionResult(data, '资料已保存');
  }

  NetworkActionResult _actionResult(dynamic data, String okMessage) {
    if (data is Map) {
      final map = networkMap(data);
      final state = networkStr(map['state']).toLowerCase();
      if (state == 'fail' || state == 'error') {
        final message = networkStr(map['message']);
        final detail = networkStr(map['data']);
        return NetworkActionResult(
          success: false,
          message: message.isNotEmpty
              ? message
              : (detail.isNotEmpty ? detail : '操作失败'),
        );
      }
      if (state == 'success') {
        final message = networkStr(map['message']);
        return NetworkActionResult(
          success: true,
          message: message.isNotEmpty ? message : okMessage,
        );
      }
      // 没有 state 字段（如 tooffline / unbindmac 的纯文本或空响应）：按成功处理，
      // 具体成败由调用方「重新拉一次数据」核对（写后对账，与选课写操作同口径）。
      final text = networkStr(data).trim();
      if (text.isNotEmpty && !text.startsWith('{')) {
        return NetworkActionResult(success: true, message: text);
      }
      return NetworkActionResult(success: true, message: okMessage);
    }
    final text = networkStr(data).trim();
    if (text.isEmpty) {
      return NetworkActionResult(success: true, message: okMessage);
    }
    return NetworkActionResult(success: true, message: text);
  }

  // ---------- 工具 ----------

  Map<String, dynamic> _jsonOf(Response<dynamic> resp) {
    final data = resp.data;
    if (data is Map) return networkMap(data);
    if (data is String && data.isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return networkMap(decoded);
    }
    throw const NetworkServiceException('网络服务响应格式异常');
  }

  String _dioText(DioException e) {
    if (e.error is FormatException) return '服务响应格式异常';
    final status = e.response?.statusCode;
    if (status != null) return 'HTTP $status';
    return e.message ?? '网络请求失败';
  }

  /// `yyyy-MM-dd`（服务端日期参数口径）。
  static String formatDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// 从 `/dashboard` HTML 里抽 `window.user = (function (user) {…})({…});` 的账号 JSON。
  static Map<String, dynamic>? extractUserJson(String html) {
    final match = RegExp(
      r'\}\)\((\{"accessGrant".*?\})\)\s*;',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) return null;
    try {
      final decoded = jsonDecode(match.group(1)!);
      if (decoded is Map) return networkMap(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  /// 抽 `var AJAXCSRFTOKEN = '…'`，兜底抽 `"ajaxCsrfToken=" + '…'`。
  static String extractAjaxCsrfToken(String html) {
    final direct = RegExp(r"AJAXCSRFTOKEN\s*=\s*'([^']+)'").firstMatch(html);
    if (direct != null) return direct.group(1)!;
    // 页面里写作 `"&ajaxCsrfToken=" + 'a29f1144-…'`（\x27 即单引号，避免与原始字符串引号冲突）。
    final inline = RegExp(
      r'ajaxCsrfToken="\s*\+\s*[\x27]([^\x27]+)[\x27]',
    ).firstMatch(html);
    if (inline != null) return inline.group(1)!;
    final hidden = RegExp(
      r'name="ajaxCsrfToken"\s+value="([^"]+)"',
    ).firstMatch(html);
    return hidden?.group(1) ?? '';
  }

  /// 抽隐藏域 `name="csrftoken" value="…"`（部分页面把 token 写在 `$.post` 参数里，
  /// 那种走 [extractAjaxCsrfToken]）。
  static String extractCsrfToken(String html) {
    final hidden = RegExp(
      r'name="csrftoken"\s+value="([^"]+)"',
    ).firstMatch(html);
    if (hidden != null) return hidden.group(1)!;
    final inline = RegExp(r"csrftoken:\s*'([^']+)'").firstMatch(html);
    return inline?.group(1) ?? extractAjaxCsrfToken(html);
  }

  /// 抽 `/service/package` 页的可选套餐卡片（`<a class="pick-card" data-package="2">`）。
  static List<NetworkPlan> extractPackageOptions(String html) {
    final plans = <NetworkPlan>[];
    final cardRe = RegExp(
      r'data-package="([^"]*)"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    for (final match in cardRe.allMatches(html)) {
      final id = match.group(1)!.trim();
      if (id.isEmpty) continue;
      final text = match
          .group(2)!
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final name = _pickAfter(text, '套餐：') ?? text;
      final desc = _pickAfter(text, '描述：') ?? '';
      plans.add(
        NetworkPlan(id: id, name: name, description: desc, selectable: true),
      );
    }
    return plans;
  }

  /// 取标记词之后到下一个标记词之前的一段（页面文本形如
  /// `套餐： 包月（学生50元） 描述： 学生宿舍有线网络适用,账号不可多个在线.`）。
  static String? _pickAfter(String text, String label) {
    final index = text.indexOf(label);
    if (index < 0) return null;
    var rest = text.substring(index + label.length).trim();
    for (final other in const ['套餐：', '描述：']) {
      if (other == label) continue;
      final cut = rest.indexOf(other);
      if (cut >= 0) rest = rest.substring(0, cut).trim();
    }
    return rest.isEmpty ? null : rest;
  }
}
