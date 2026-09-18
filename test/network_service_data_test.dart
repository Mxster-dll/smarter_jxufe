import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/network_service/data/datasources/network_service_remote_datasource.dart';
import 'package:smarter_jxufe/features/network_service/domain/network_service_format.dart';
import 'package:smarter_jxufe/features/network_service/domain/network_service_models.dart';

/// 按「URL 包含的子串」路由响应的假适配器：一个适配器覆盖整条链路
/// （checkAppAuth → 登录 302 带 Set-Cookie → 业务接口 → 写操作）。
class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(
    this.routes, {
    this.loginCookie = 'JSESSIONID=TESTJSID; Path=/; HttpOnly',
  });

  /// 子串 → 响应体；匹配顺序按 Map 插入顺序（先写更具体的子串）。
  final Map<String, String> routes;
  final String loginCookie;

  final List<RequestOptions> calls = <RequestOptions>[];
  final List<String> bodies = <String>[];

  /// 命中次数（用于断言「会话失效 → 重登一次」）。
  final Map<String, int> hits = <String, int>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    calls.add(options);
    bodies.add(await _readStream(requestStream));

    String? matched;
    for (final key in routes.keys) {
      if (url.contains(key)) {
        matched = key;
        break;
      }
    }
    hits[matched ?? '<none>'] = (hits[matched ?? '<none>'] ?? 0) + 1;

    final body = routes[matched] ?? '';
    // 真实服务端对 JSON 与 HTML 给的 content-type 不同：HTML 页面必须按文本返回，
    // 否则 Dio 的 JSON 转换器会对页面源码抛 FormatException。
    final trimmed = body.trimLeft();
    final isJson = trimmed.startsWith('{') || trimmed.startsWith('[');
    final headers = <String, List<String>>{
      Headers.contentTypeHeader: <String>[
        isJson ? Headers.jsonContentType : 'text/html; charset=utf-8',
      ],
    };
    var status = 200;
    if (url.contains('verifyByWeChat')) {
      status = 302;
      headers['set-cookie'] = <String>[loginCookie];
    }
    return ResponseBody.fromString(
      routes[matched] ?? '',
      status,
      headers: headers,
    );
  }

  static Future<String> _readStream(Stream<Uint8List>? stream) async {
    if (stream == null) return '';
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 找第一个「URL 包含 [key]」的调用。
  RequestOptions callFor(String key) =>
      calls.firstWhere((c) => c.uri.toString().contains(key));

  int hitCount(String key) => hits[key] ?? 0;

  @override
  void close({bool force = false}) {}
}

Dio _dio(_RouteAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://wxcourse.jxufe.cn'))
      ..httpClientAdapter = adapter;

const String _encUserId = 'AAAAAAAAAAAAAAAAAAAAAA==';

const String _checkAppAuthBody =
    '{"code":200,"success":true,"result":{"appid":"1575336885141","name":"网络服务",'
    '"type":"3","typeC":"H5","username":"$_encUserId",'
    '"pageUrl":"https://wxcourse.jxufe.cn/1575336885141//login/verifyByWeChat'
    '?cardinfo=KLodvO2sVPmxunBn2Q3fFvPniUt%2FdA8G6XkOnncgs%2F4%3D&sno=0000000'
    '&openId=W0yHUmN7O4fP5%2F0qA7AFMPSj%2BDaZC5%2FZF0wcbGKRjmc%3D&cname=%E9%99%88"}}';

const String _dashboardHtml = '''
<html><body>
<script>(function (user) {
  window.user = user || {};
})({"accessGrant":"11111111","useFlag":1,"leftMoney":12.5,"useFlow":31777.239,
"useTime":13009,"leftFlow":0,"leftTime":0,"macAddress":"F2AD73A213CD;24B2B9A1B1C5",
"ipCount":1,"multiLogin":1,"userName":"2000000000","userRealName":"某同学",
"userPassword":"Nm'C`%a","userIdNumber":"360421200701240018","userId":999272722,
"startDate":1757764820000,"stopDate":1772121600000,
"serviceDefault":{"defaultName":"GPON学生12.5元/月","extend":"蛟7,9;麦北5、6"},
"userGroup":{"payStyle":3,"ipMaxCount":3,"userGroupName":"GPON学生12.5/月",
"userGroupDescription":"12.5/月"}});</script>
<script>csrftoken: 'aaa-bbb'</script>
</body></html>''';

const String _loginPageHtml =
    '<html><head><title>用户自助服务系统</title></head>'
    '<body><form><input type="password" name="password"></form></body></html>';

const String _onlineBody =
    '[{"brasid":"1","downFlow":"13033","hostName":"","ip":"10.16.80.77",'
    '"loginTime":"2026-09-16 17:10:45","mac":"A24A4082511F","sessionId":"36035",'
    '"terminalType":"#移动终端","upFlow":"1729","useTime":"864","userId":999272722}]';

const String _historyBody =
    '[[1789032120000,1789189968000,"10.16.26.160","24B2B9A1B1C5",2631,6221.137,2,0,'
    'null,"#PC","PC",1],[1789141051000,null,"10.16.102.235","A24A4082511F",733,'
    '29.385,3,0,null,"#移动终端","移动终端",2]]';

const String _usageBody =
    '{"rows":[{"area":1,"costMoney":0,"costStyleId":2,"flow":6221.137,'
    '"internetDownFlow":4228.652,"internetUpFlow":1992.485,"chinanetDownFlow":0,'
    '"chinanetUpFlow":0,"loginTime":1789032120000,"logoutTime":1789189968000,'
    '"macAddress":"24B2B9A1B1C5","nasIp":"172.31.179.2","nasPort":235671455,'
    '"time":2631,"userIp":"10.16.26.160","userRealName":"某同学"}],'
    '"summary":{"COU":0},"total":1}';

const String _monthPayBody =
    '{"summary":{"USETIME":122619.0,"USEBASEMONEY":100.0,"USEFLOW":1477237.857,'
    '"USEDMONEY":0.0},"total":2,"rows":['
    '[1787760000000,1790438400000,"GPON学生12.5/月|fid=scholar_deny|",12.5,0.0,0.0,0.0,'
    '1787767206000],[1785081600000,1787760000000,"GPON学生12.5/月|fid=scholar_deny|",'
    '0.0,0.0,18069.0,60401.473,1785088806000]]}';

const String _payMentBody =
    '{"rows":[["2026-09-01 10:00:00","微信充值",50.0,"自助服务","备注A"]],"total":1}';

const String _operatorBody =
    '{"rows":[["2026-09-02 09:00:00","账号复通","自助服务",null,"余额不足复通"]],'
    '"total":1}';

const String _devicesBody =
    '{"rows":[["0","F2AD73A213CD","#移动终端","2026-08-11 17:44:03","10.16.108.132"],'
    '["1","24B2B9A1B1C5","#PC","2026-09-12 00:00:00","10.16.26.160"]],"total":2}';

const String _plansBody =
    '{"rows":[{"areaId":1,"code":"6","defaultName":"包月（学生50元）",'
    '"extend":"学生宿舍有线网络适用,账号不可多个在线.","id":2,"userGroupId":2}],"total":1}';

const String _reopenLogBody =
    '{"rows":[{"fldadminid":6002,"fldid":22458804,"fldmemo":"1772193838471 批次: 0",'
    '"fldnewvalue":"1/","fldoldvalue":"0/余额不足，系统停机",'
    '"fldoperatedate":1772193773000,"fldoperateid":9,"fldoperateobject":999272722}],'
    '"total":1}';

const String _packageLogBody =
    '{"rows":[{"fldchangedate":1757771198000,"fldexcutedate":1757771198000,'
    '"flddefaultname1":"GPON学生12.5/月","flddefaultname2":"包月（学生50元）",'
    '"fldstate":"已生效","fldextend":"备注"}],"total":1}';

/// 自助服务系统页面片段（token 与套餐卡片口径与线上一致）。
const String _stopPageHtml =
    "<script>var AJAXCSRFTOKEN = 'tok-stop';</script><form></form>";
const String _reopenPageHtml =
    "<script>var AJAXCSRFTOKEN = 'tok-reopen';</script>";
const String _myMacPageHtml =
    '<script>function unbindmac(mac){location.href = "/service/unbindmac?mac=" + mac '
    '+ "&ajaxCsrfToken=" + \'tok-mac\';}</script>';
const String _packagePageHtml =
    '<script>var AJAXCSRFTOKEN = \'tok-package\';</script>'
    '<form><input type="hidden" name="csrftoken" value="csrf-package"/></form>'
    '<a href="javascript:" class="pick-card" data-package="2"> 套餐： 包月（学生50元） '
    '描述： 学生宿舍有线网络适用,账号不可多个在线. </a>';
const String _passwordPageHtml =
    '<form><input type="hidden" name="csrftoken" value="csrf-password" /></form>';

const String _okAction = '{"state":"success","message":"操作成功"}';

Map<String, String> _routes({String dashboard = _dashboardHtml}) =>
    <String, String>{
      'checkAppAuth': _checkAppAuthBody,
      'verifyByWeChat': '',
      'dashboard/getOnlineList': _onlineBody,
      'dashboard/getLoginHistory': _historyBody,
      'dashboard/tooffline': '',
      'bill/getUserOnlineLog': _usageBody,
      'bill/getMonthPay': _monthPayBody,
      'bill/getPayMent': _payMentBody,
      'bill/getOperatorLog': _operatorBody,
      'service/getMacList': _devicesBody,
      'service/getUserGroups': _plansBody,
      'service/getStopLog': '{"rows":[],"total":0}',
      'service/goReopenLog': _reopenLogBody,
      'service/packageLog': _packageLogBody,
      'service/goStop': _stopPageHtml,
      'service/stop': _okAction,
      'service/undoStop': _okAction,
      'service/goReopen': _reopenPageHtml,
      'service/reOpen': _okAction,
      'service/undoReOpen': _okAction,
      'service/package': _packagePageHtml,
      'service/doPackage': _okAction,
      'service/undoPackage': _okAction,
      'service/myMac': _myMacPageHtml,
      'service/unbindmac': _okAction,
      'setting/changePasswordMethod': _okAction,
      'setting/changePassword': _passwordPageHtml,
      'setting/updateUserSecurity': _okAction,
      'dashboard': dashboard,
    };

void main() {
  group('登录链（checkAppAuth → userId → JSESSIONID）', () {
    test('第二步必须带 userId（enc 原样 urlencode），并复用 Cookie', () async {
      final adapter = _RouteAdapter(_routes());
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      final account = await ds.fetchAccount('GUID-1');

      // 1) checkAppAuth 带 appid + GUID
      final auth = adapter.callFor('checkAppAuth');
      expect(auth.uri.path, contains('checkAppAuth'));
      expect(
        auth.queryParameters['appid'],
        NetworkServiceRemoteDataSource.appId,
      );
      expect(auth.queryParameters['platformUsername'], 'GUID-1');

      // 2) 登录 URL = pageUrl + &userId=<enc>（`==` 必须编码）
      final login = adapter.callFor('verifyByWeChat');
      expect(
        login.uri.toString(),
        contains('userId=AAAAAAAAAAAAAAAAAAAAAA%3D%3D'),
      );
      expect(login.uri.toString(), contains('cardinfo=')); // 原签名参数保留

      // 3) 会话 Cookie 复用到业务请求（取账号那次 GET /dashboard）
      final data = adapter.callFor('1575336885141/dashboard');
      expect(data.headers['Cookie'], 'JSESSIONID=TESTJSID');

      expect(account.userName, '2000000000');
      expect(adapter.hitCount('checkAppAuth'), 1, reason: '同一 GUID 只登录一次');
    });

    test('登录未下发 Set-Cookie → 抛「未取得会话」', () async {
      final adapter = _RouteAdapter(_routes(), loginCookie: '');
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      await expectLater(
        ds.fetchAccount('GUID-1'),
        throwsA(
          isA<NetworkServiceException>().having(
            (e) => e.message,
            'message',
            contains('未取得会话'),
          ),
        ),
      );
    });

    test('GUID 为空 → 抛「未配置」且 needGuid', () async {
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(_routes())));
      await expectLater(
        ds.fetchAccount(''),
        throwsA(
          isA<NetworkServiceException>().having(
            (e) => e.needGuid,
            'needGuid',
            isTrue,
          ),
        ),
      );
    });

    test('业务请求被踢回登录页 → 自动重登一次并重试', () async {
      final adapter = _RouteAdapter(_routes(dashboard: _loginPageHtml));
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      await expectLater(
        ds.fetchAccount('GUID-1'),
        throwsA(
          isA<NetworkServiceException>().having(
            (e) => e.message,
            'message',
            contains('会话已失效'),
          ),
        ),
      );
      // 首次 dashboard 命中登录页 → 重新登录 → 重试仍是登录页（假数据恒为登录页）
      expect(adapter.hitCount('checkAppAuth'), 2);
      expect(adapter.hitCount('dashboard'), 2);
    });
  });

  group('账号概览（dashboard 内嵌 window.user）', () {
    test('字段映射：套餐计费方式取 userGroup.payStyle 而非顶层', () async {
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(_routes())));
      final account = await ds.fetchAccount('GUID-1');

      expect(account.leftMoney, 12.5);
      expect(account.useTime, 13009);
      expect(account.useFlow, closeTo(31777.239, 0.001));
      expect(account.planName, 'GPON学生12.5元/月');
      expect(account.payStyle, 3, reason: '顶层 payStyle=0，套餐口径在 userGroup');
      expect(account.payStyleLabel, '包月');
      expect(account.active, isTrue);
      expect(account.statusLabel, '正常');
      expect(account.macs, ['F2AD73A213CD', '24B2B9A1B1C5']);
      expect(account.ipMaxCount, 3);
      expect(account.password, "Nm'C`%a");
      expect(account.idNumber, '360421200701240018');
      expect(networkFormatDate(account.expireAt), '2026-02-27');
    });

    test('页面里没有 window.user → 抛「未找到账号信息」', () async {
      final ds = NetworkServiceRemoteDataSource(
        _dio(_RouteAdapter(_routes(dashboard: '<html>没有账号</html>'))),
      );
      await expectLater(
        ds.fetchAccount('g'),
        throwsA(
          isA<NetworkServiceException>().having(
            (e) => e.message,
            'message',
            contains('未找到账号信息'),
          ),
        ),
      );
    });
  });

  group('在线设备 / 上网记录', () {
    test('在线会话：终端去掉 # 前缀，时长按秒', () async {
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(_routes())));
      final sessions = await ds.fetchOnlineSessions('g');

      expect(sessions, hasLength(1));
      expect(sessions.single.sessionId, '36035');
      expect(sessions.single.terminalType, '#移动终端');
      expect(sessions.single.terminalLabel, '移动终端');
      expect(sessions.single.useSeconds, 864);
      expect(sessions.single.loginAtText, '2026-09-16 17:10:45');
      expect(sessions.single.downFlow, 13033);
    });

    test('近期上网记录：数组行按 field 0..9 映射，未注销 = 在线中', () async {
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(_routes())));
      final records = await ds.fetchLoginHistory('g');

      expect(records, hasLength(2));
      expect(records[0].ip, '10.16.26.160');
      expect(records[0].minutes, 2631);
      expect(records[0].flowMb, closeTo(6221.137, 0.001));
      expect(records[0].payStyleLabel, '流量');
      expect(records[0].terminalLabel, 'PC');
      expect(records[0].online, isFalse);
      expect(records[1].online, isTrue, reason: '无注销时间 = 仍在线上');
    });

    test('上网记录明细必须带日期范围，且 rows 字段完整解析', () async {
      final adapter = _RouteAdapter(_routes());
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      final rows = await ds.fetchUsageRecords(
        'g',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 12, 31),
      );

      final call = adapter.callFor('bill/getUserOnlineLog');
      expect(call.queryParameters['startTime'], '2026-01-01');
      expect(call.queryParameters['endTime'], '2026-12-31');

      expect(rows.single.minutes, 2631);
      expect(rows.single.userIp, '10.16.26.160');
      expect(rows.single.mac, '24B2B9A1B1C5');
      expect(rows.single.nasIp, '172.31.179.2');
      expect(rows.single.internetDownFlow, closeTo(4228.652, 0.001));
    });
  });

  group('账单 / 充值 / 办理记录', () {
    test('历史账单必须带 year，rows 与 summary 都解析', () async {
      final adapter = _RouteAdapter(_routes());
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      final bills = await ds.fetchMonthBills('g', 2026);

      expect(adapter.callFor('bill/getMonthPay').queryParameters['year'], 2026);
      expect(bills.year, 2026);
      expect(bills.items, hasLength(2));
      expect(bills.items.first.baseMoney, 12.5);
      expect(bills.items.first.total, 12.5);
      expect(networkFormatDate(bills.items.first.startAt), '2026-08-27');
      // 服务端 rows 的结束时间是「下期开始」（开区间），含末日要减一天，
      // 这样与学校页面显示的 2026-08-27 ~ 2026-09-26 一致。
      expect(networkFormatDate(bills.items.first.endAt), '2026-09-27');
      expect(networkFormatDate(bills.items.first.endDay), '2026-09-26');
      expect(bills.summary.baseMoney, 100.0);
      expect(bills.summary.total, 100.0);
      expect(bills.summary.minutes, 122619);
    });

    test('充值明细列序 = 时间/类型/金额/受理终端/备注', () async {
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(_routes())));
      final payments = await ds.fetchPayments('g');

      expect(payments.single.kind, '微信充值');
      expect(payments.single.amount, 50.0);
      expect(payments.single.terminal, '自助服务');
      expect(payments.single.memo, '备注A');
      expect(networkFormatDateTime(payments.single.paidAt), '2026-09-01 10:00');
    });

    test('业务办理记录列序 = 时间/描述/受理终端/备注', () async {
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(_routes())));
      final logs = await ds.fetchOperatorLogs('g');

      expect(logs.single.description, '账号复通');
      expect(logs.single.terminal, '自助服务');
      expect(logs.single.memo, '余额不足复通');
    });

    test('空 rows → 空列表（不抛）', () async {
      final routes = _routes()
        ..['bill/getPayMent'] = '{}'
        ..['bill/getOperatorLog'] = '{}';
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(routes)));

      expect(await ds.fetchPayments('g'), isEmpty);
      expect(await ds.fetchOperatorLogs('g'), isEmpty);
    });
  });

  group('我的设备 / 资费 / 办理记录', () {
    test('设备行 = [在线状态, MAC, 终端, 最近登录时间, 最近登录IP]', () async {
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(_routes())));
      final devices = await ds.fetchDevices('g');

      expect(devices, hasLength(2));
      expect(devices[0].online, isFalse);
      expect(devices[0].mac, 'F2AD73A213CD');
      expect(devices[0].terminalLabel, '移动终端');
      expect(devices[1].online, isTrue);
      expect(devices[1].lastLoginIp, '10.16.26.160');
    });

    test('资费介绍解析 id/名称/描述', () async {
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(_routes())));
      final plans = await ds.fetchPlans('g');

      expect(plans.single.id, '2');
      expect(plans.single.name, '包月（学生50元）');
      expect(plans.single.description, contains('学生宿舍有线网络适用'));
    });

    test('复通记录：旧值里的原因被翻译成可读描述', () async {
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(_routes())));
      final logs = await ds.fetchReopenLogs('g');

      expect(logs.single.description, '余额不足停机后复通');
      expect(
        networkFormatDateTime(logs.single.operatedAt),
        startsWith('2026-02-27'),
      );
    });

    test('预约套餐日志解析原套餐/预约套餐/状态', () async {
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(_routes())));
      final logs = await ds.fetchPackageLogs('g');

      expect(logs.single.fromPlan, 'GPON学生12.5/月');
      expect(logs.single.toPlan, '包月（学生50元）');
      expect(logs.single.state, '已生效');
    });
  });

  group('写操作（token 先取页面，再提交）', () {
    test('立即报停：AJAXCSRFTOKEN + flag=1', () async {
      final adapter = _RouteAdapter(_routes());
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      final result = await ds.stopAccount('g', immediate: true);

      expect(result.success, isTrue);
      expect(
        adapter.callFor('service/stop').uri.path,
        contains('service/stop'),
      );
      final body = adapter
          .bodies[adapter.calls.indexOf(adapter.callFor('service/stop'))];
      expect(body, contains('ajaxCsrfToken=tok-stop'));
      expect(body, contains('flag=1'));
    });

    test('预约报停：flag=2', () async {
      final adapter = _RouteAdapter(_routes());
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      await ds.stopAccount('g', immediate: false);

      final body = adapter
          .bodies[adapter.calls.indexOf(adapter.callFor('service/stop'))];
      expect(body, contains('flag=2'));
    });

    test('预约复通：flag=2 + date=yyyy-MM-dd', () async {
      final adapter = _RouteAdapter(_routes());
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      await ds.reopenAccount(
        'g',
        immediate: false,
        date: DateTime(2026, 10, 1),
      );

      final body = adapter
          .bodies[adapter.calls.indexOf(adapter.callFor('service/reOpen'))];
      expect(body, contains('ajaxCsrfToken=tok-reopen'));
      expect(body, contains('flag=2'));
      expect(body, contains('date=2026-10-01'));
    });

    test('预约套餐：隐藏域 csrftoken + serid（doPackage）', () async {
      final adapter = _RouteAdapter(_routes());
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      final options = await ds.fetchPackageOptions('g');
      expect(options.csrfToken, 'csrf-package');
      expect(options.options.single.id, '2');
      expect(options.options.single.name, '包月（学生50元）');
      expect(options.options.single.description, contains('不可多个在线'));

      await ds.reservePackage('g', options.options.single.id);

      final body = adapter
          .bodies[adapter.calls.indexOf(adapter.callFor('service/doPackage'))];
      expect(body, contains('csrftoken=csrf-package'));
      expect(body, contains('serid=2'));
    });

    test('解绑设备：myMac 页内联 token + mac 参数', () async {
      final adapter = _RouteAdapter(_routes());
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      await ds.unbindDevice('g', 'F2AD73A213CD');

      final call = adapter.callFor('service/unbindmac');
      expect(call.queryParameters['mac'], 'F2AD73A213CD');
      expect(call.queryParameters['ajaxCsrfToken'], 'tok-mac');
    });

    test('强制下线：tooffline?sessionid=', () async {
      final adapter = _RouteAdapter(_routes());
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      await ds.forceOffline('g', '36035');

      expect(
        adapter.callFor('dashboard/tooffline').queryParameters['sessionid'],
        '36035',
      );
    });

    test('修改密码：提交原/新/确认三个字段（确认由客户端补齐）', () async {
      final adapter = _RouteAdapter(_routes());
      final ds = NetworkServiceRemoteDataSource(_dio(adapter));

      await ds.changePassword(
        'g',
        oldPassword: 'old123',
        newPassword: 'new456',
      );

      final body =
          adapter.bodies[adapter.calls.indexOf(
            adapter.callFor('setting/changePasswordMethod'),
          )];
      expect(body, contains('csrftoken=csrf-password'));
      expect(body, contains('oldPassword=old123'));
      expect(body, contains('newPassword=new456'));
      expect(body, contains('confirmPassword=new456'));
    });

    test('服务端 state=error → success=false 且带服务端文案', () async {
      final routes = _routes()
        ..['service/reOpen'] = '{"state":"error","message":"余额不足，复通失败"}';
      final ds = NetworkServiceRemoteDataSource(_dio(_RouteAdapter(routes)));

      final result = await ds.reopenAccount('g', immediate: true);

      expect(result.success, isFalse);
      expect(result.message, contains('余额不足'));
    });
  });

  group('HTML 抽取工具', () {
    test('extractAjaxCsrfToken 三种写法', () {
      expect(
        NetworkServiceRemoteDataSource.extractAjaxCsrfToken(
          "<script>var AJAXCSRFTOKEN = 'aaa';</script>",
        ),
        'aaa',
      );
      expect(
        NetworkServiceRemoteDataSource.extractAjaxCsrfToken(
          '<script>function f(mac){location.href = "x?mac=" + mac '
          '+ "&ajaxCsrfToken=" + \'bbb\';}</script>',
        ),
        'bbb',
      );
      expect(
        NetworkServiceRemoteDataSource.extractAjaxCsrfToken(
          '<input type="hidden" name="ajaxCsrfToken" value="ccc"/>',
        ),
        'ccc',
      );
      expect(
        NetworkServiceRemoteDataSource.extractAjaxCsrfToken('<p>无</p>'),
        '',
      );
    });

    test(r'extractCsrfToken 优先隐藏域，兜底 $.post 参数', () {
      expect(
        NetworkServiceRemoteDataSource.extractCsrfToken(
          '<input type="hidden" name="csrftoken" value="hidden-tok"/>',
        ),
        'hidden-tok',
      );
      expect(
        NetworkServiceRemoteDataSource.extractCsrfToken(
          "<script>\$.get('x', {csrftoken: 'inline-tok', t: Math.random()});</script>",
        ),
        'inline-tok',
      );
    });

    test('extractPackageOptions 解析 pick-card 的 id / 名称 / 描述', () {
      final plans = NetworkServiceRemoteDataSource.extractPackageOptions(
        _packagePageHtml,
      );
      expect(plans, hasLength(1));
      expect(plans.single.id, '2');
      expect(plans.single.name, '包月（学生50元）');
      expect(plans.single.description, '学生宿舍有线网络适用,账号不可多个在线.');
    });

    test('extractUserJson 对残缺 JSON 返回 null（不抛）', () {
      expect(
        NetworkServiceRemoteDataSource.extractUserJson(
          '})({"accessGrant": broken});',
        ),
        isNull,
      );
      expect(
        NetworkServiceRemoteDataSource.extractUserJson('<html></html>'),
        isNull,
      );
    });
  });

  group('模型容错与格式化', () {
    test('数字/字符串/null 都能解析', () {
      expect(networkNum('12.5'), 12.5);
      expect(networkNum(3), 3.0);
      expect(networkNum(null), 0);
      expect(networkNum('abc', fallback: -1), -1);
      expect(networkStr(null), '');
      expect(networkStr(42), '42');
      expect(networkMap('not a map'), isEmpty);
      expect(networkMap({'a': 1})['a'], 1);
      expect(networkList('x'), isEmpty);
    });

    test('毫秒时间戳与文本时间', () {
      expect(networkMillis(0), isNull);
      expect(networkMillis(null), isNull);
      expect(networkMillis('1789032120000'), isNotNull);
      expect(networkParseDateTime('2026-09-16 17:10:45'), isNotNull);
      expect(networkParseDateTime(''), isNull);
      expect(networkParseDateTime('乱码'), isNull);
    });

    test('流量/时长/字节格式化', () {
      expect(networkFormatFlow(0), '0 MB');
      expect(networkFormatFlow(512.5), '512.5 MB');
      expect(networkFormatFlow(2048), '2.00 GB');
      expect(networkFormatMinutes(0), '0 分钟');
      expect(networkFormatMinutes(45), '45 分');
      expect(networkFormatMinutes(180), '3 小时');
      expect(networkFormatMinutes(2631), '1 天 19 小时');
      expect(networkFormatSeconds(864), '14 分');
      expect(networkFormatBytes(13033), '0.01 MB');
    });

    test('MAC 加连字符；密码掩码等长', () {
      expect(networkFormatMac('24B2B9A1B1C5'), '24-B2-B9-A1-B1-C5');
      expect(networkFormatMac('24-B2-B9'), '24-B2-B9');
      expect(networkFormatMac(''), '');
      expect(networkMaskPassword("Nm'C`%a"), '*******');
      expect(networkMaskPassword(''), '');
    });

    test('操作结果 state 语义', () {
      expect(
        NetworkActionResult.fromJson({
          'state': 'success',
          'message': 'ok',
        }).success,
        isTrue,
      );
      expect(
        NetworkActionResult.fromJson({'state': 'fail', 'data': '原因'}).message,
        '原因',
      );
      expect(NetworkActionResult.fromJson({'success': true}).success, isTrue);
    });
  });
}
