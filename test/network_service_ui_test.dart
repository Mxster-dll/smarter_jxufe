import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/web/external_url.dart';
import 'package:smarter_jxufe/core/web/in_app_web_screen.dart';
import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/network_service/data/datasources/network_service_remote_datasource.dart';
import 'package:smarter_jxufe/features/network_service/data/providers/network_service_providers.dart';
import 'package:smarter_jxufe/features/network_service/domain/network_service_models.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_devices_screen.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_profile_screen.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_records_screen.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_service_section.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_services_screen.dart';

/// 按 URL 子串路由的假适配器（与数据层测试同款，UI 侧只需要「写操作有没有发出去」）。
class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.routes);

  final Map<String, String> routes;
  final List<RequestOptions> calls = <RequestOptions>[];
  final List<String> bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    calls.add(options);
    bodies.add(await _read(requestStream));
    String? matched;
    for (final key in routes.keys) {
      if (url.contains(key)) {
        matched = key;
        break;
      }
    }
    final body = routes[matched] ?? '';
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
      headers['set-cookie'] = <String>['JSESSIONID=UIJSID; Path=/; HttpOnly'];
    }
    return ResponseBody.fromString(body, status, headers: headers);
  }

  static Future<String> _read(Stream<Uint8List>? stream) async {
    if (stream == null) return '';
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  RequestOptions? callFor(String key) {
    for (final call in calls) {
      if (call.uri.toString().contains(key)) return call;
    }
    return null;
  }

  String bodyFor(String key) {
    final index = calls.indexWhere((c) => c.uri.toString().contains(key));
    return index < 0 ? '' : bodies[index];
  }

  @override
  void close({bool force = false}) {}
}

const String _checkAppAuth =
    '{"code":200,"success":true,"result":{"appid":"1575336885141",'
    '"username":"encUser==","pageUrl":"https://wxcourse.jxufe.cn/1575336885141'
    '//login/verifyByWeChat?cardinfo=abc"}}';

/// 真实账号 JSON 的裁剪版（余额 12.5 / 套餐 GPON学生12.5元/月 / 密码明文）。
const String _dashboardHtml = '''
<script>(function (user) { window.user = user || {}; })(
{"useFlag":1,"leftMoney":12.5,"useFlow":31777.239,"useTime":13009,
"macAddress":"F2AD73A213CD;24B2B9A1B1C5","ipCount":1,"multiLogin":1,
"userName":"2000000000","userRealName":"某同学","userPassword":"pw123456",
"userIdNumber":"360421200701240018","stopDate":1772121600000,
"serviceDefault":{"defaultName":"GPON学生12.5元/月","extend":"麦北5、6"},
"userGroup":{"payStyle":3,"ipMaxCount":3,"userGroupDescription":"12.5/月"}});</script>''';

const String _onlineBody =
    '[{"ip":"10.16.80.77","mac":"A24A4082511F","loginTime":"2026-09-16 17:10:45",'
    '"sessionId":"36035","terminalType":"#移动终端","upFlow":"1729",'
    '"downFlow":"13033","useTime":"864"}]';

const String _devicesBody =
    '{"rows":[["1","24B2B9A1B1C5","#PC","2026-09-12 00:00:00","10.16.26.160"]],'
    '"total":1}';

const String _historyBody =
    '[[1789032120000,1789189968000,"10.16.26.160","24B2B9A1B1C5",2631,6221.137,2,0,'
    'null,"#PC","PC",1]]';

const String _monthPayBody =
    '{"summary":{"USETIME":122619.0,"USEBASEMONEY":100.0,"USEFLOW":1477237.857,'
    '"USEDMONEY":0.0},"total":1,"rows":[[1787760000000,1790438400000,'
    '"GPON学生12.5/月|fid=x|",12.5,0.0,0.0,0.0,1787767206000]]}';

Map<String, String> _routes() => <String, String>{
  'checkAppAuth': _checkAppAuth,
  'verifyByWeChat': '',
  'dashboard/getOnlineList': _onlineBody,
  'dashboard/getLoginHistory': _historyBody,
  'dashboard/tooffline': '',
  'bill/getMonthPay': _monthPayBody,
  'bill/getUserOnlineLog': '{"rows":[],"total":0}',
  'bill/getPayMent': '{"rows":[]}',
  'bill/getOperatorLog': '{"rows":[]}',
  'service/getStopLog': '{"rows":[]}',
  'service/goReopenLog': '{"rows":[]}',
  'service/packageLog': '{"rows":[]}',
  'service/getMacList': _devicesBody,
  'service/getUserGroups':
      '{"rows":[{"id":2,"defaultName":"包月（学生50元）",'
      '"extend":"学生宿舍有线网络适用"}]}',
  'service/goStop': "<script>var AJAXCSRFTOKEN = 'tok-stop';</script>",
  'service/stop': '{"state":"success","message":"报停成功"}',
  'service/goReopen': "<script>var AJAXCSRFTOKEN = 'tok-reopen';</script>",
  'service/package':
      "<script>var AJAXCSRFTOKEN = 'tok-pkg';</script>"
      '<input type="hidden" name="csrftoken" value="csrf-pkg">'
      '<a class="pick-card" data-package="2"> 套餐： 包月（学生50元） 描述： 说明 </a>',
  'service/doPackage': '{"state":"success","message":"预约成功"}',
  'setting/changePassword':
      '<input type="hidden" name="csrftoken" value="csrf-pwd">',
  'setting/changePasswordMethod': '{"state":"success","message":"修改成功"}',
  'dashboard': _dashboardHtml,
};

NetworkAccount get _account => NetworkAccount.fromUserJson(
  jsonDecode(
        '{"useFlag":1,"leftMoney":12.5,"useFlow":31777.239,"useTime":13009,'
        '"macAddress":"F2AD73A213CD","ipCount":1,"multiLogin":1,'
        '"userName":"2000000000","userRealName":"某同学","userPassword":"pw123456",'
        '"userIdNumber":"360421200701240018","stopDate":1772121600000,'
        '"serviceDefault":{"defaultName":"GPON学生12.5元/月","extend":"麦北5、6"},'
        '"userGroup":{"payStyle":3,"ipMaxCount":3,"userGroupDescription":"12.5/月"}}',
      )
      as Map<String, dynamic>,
);

/// 网络服务整段（宿主是校园网页第二段，测试里给一个够高的视口）。
Future<void> _pumpSection(
  WidgetTester tester, {
  List<Override> overrides = const [],
  VoidCallback? onConfigureGuid,
  List<Uri>? opened,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        networkAccountProvider.overrideWith((ref) async => _account),
        networkOnlineSessionsProvider.overrideWith(
          (ref) async => [
            NetworkOnlineSession.fromJson({
              'sessionId': '36035',
              'ip': '10.16.80.77',
              'mac': 'A24A4082511F',
              'loginTime': '2026-09-16 17:10:45',
              'useTime': '864',
              'upFlow': '1729',
              'downFlow': '13033',
              'terminalType': '#移动终端',
            }),
          ],
        ),
        networkLoginHistoryProvider.overrideWith(
          (ref) async => [
            NetworkLoginRecord.fromRow([
              1789032120000,
              1789189968000,
              '10.16.26.160',
              '24B2B9A1B1C5',
              2631,
              6221.137,
              2,
              0,
              null,
              '#PC',
              'PC',
              1,
            ]),
          ],
        ),
        if (opened != null)
          externalUrlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        // 测试环境的 defaultTargetPlatform 是 android → 默认会走内嵌 WebView；
        // 桌面端口径（本次要验的）必须显式关掉。
        inAppWebViewSupportedProvider.overrideWithValue(false),
        ...overrides,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NetworkServiceSection(
              onConfigureGuid: onConfigureGuid ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('校园网第二段 · 网络服务（真数据）', () {
    testWidgets('账号概览：余额 / 套餐 / 用量 / 账号 / 密码掩码', (tester) async {
      await _pumpSection(tester);

      expect(find.text('网络服务'), findsOneWidget);
      expect(find.text('正常'), findsOneWidget);
      expect(find.byKey(const Key('netsvc_balance')), findsOneWidget);
      expect(find.text('12.50'), findsOneWidget);
      expect(find.text('GPON学生12.5元/月'), findsOneWidget);
      expect(find.text('包月 · 12.5/月'), findsOneWidget);
      expect(find.text('2000000000'), findsOneWidget);
      // 密码默认掩码，点「显示」才出明文
      expect(find.text('********'), findsOneWidget);
      expect(find.byKey(const Key('netsvc_password_copy')), findsOneWidget);

      await tester.tap(find.byKey(const Key('netsvc_password_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('pw123456'), findsOneWidget);
    });

    testWidgets('在线设备：终端名去掉 # 前缀，带下线按钮', (tester) async {
      await _pumpSection(tester);

      expect(find.text('在线设备'), findsOneWidget);
      expect(find.text('移动终端'), findsOneWidget);
      expect(find.textContaining('10.16.80.77'), findsOneWidget);
      expect(find.byKey(const Key('netsvc_offline_36035')), findsOneWidget);
      expect(find.byKey(const Key('netsvc_devices_all')), findsOneWidget);
    });

    testWidgets('近期上网记录与全部入口', (tester) async {
      await _pumpSection(tester);

      expect(find.text('近期上网记录'), findsOneWidget);
      // 6221.137 MB → GB（汇总与明细行各一处）
      expect(find.text('6.08 GB'), findsWidgets);
      expect(find.byKey(const Key('netsvc_records_all')), findsOneWidget);
    });

    testWidgets('明细与业务入口齐全 + 微信充值走外部打开', (tester) async {
      final opened = <Uri>[];
      await _pumpSection(tester, opened: opened);

      for (final title in [
        '历史账单',
        '充值明细',
        '业务办理记录',
        '资费介绍',
        '账号服务',
        '账号设置',
        '微信充值',
      ]) {
        expect(find.text(title), findsOneWidget, reason: '缺少入口：$title');
      }

      await tester.ensureVisible(
        find.byKey(const Key('netsvc_wechat_recharge')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('netsvc_wechat_recharge')));
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      expect(
        opened.single.toString(),
        'https://self.jxufe.cn/WebPay/recharge?paytype=3&account=2000000000',
      );
    });

    testWidgets('未配置 GUID → 提示去配置（不显示余额）', (tester) async {
      var configured = 0;
      await _pumpSection(
        tester,
        onConfigureGuid: () => configured++,
        overrides: [
          networkAccountProvider.overrideWith(
            (ref) async => throw const NetworkServiceException(
              kNetworkServiceNeedGuid,
              needGuid: true,
            ),
          ),
        ],
      );

      expect(find.textContaining('未配置微信平台标识'), findsOneWidget);
      expect(find.byKey(const Key('netsvc_balance')), findsNothing);

      await tester.tap(find.text('去配置'));
      await tester.pumpAndSettle();
      expect(configured, 1);
    });
  });

  group('强制下线（写操作走真实数据源）', () {
    testWidgets('确认后发 tooffline?sessionid=，并提示已下线', (tester) async {
      final adapter = _RouteAdapter(_routes());
      await _pumpSection(
        tester,
        overrides: [
          netFeeDioProvider.overrideWithValue(
            Dio(BaseOptions(baseUrl: 'https://wxcourse.jxufe.cn'))
              ..httpClientAdapter = adapter,
          ),
          networkServiceGuidProvider.overrideWith((ref) async => 'GUID-1'),
        ],
      );

      await tester.tap(find.byKey(const Key('netsvc_offline_36035')));
      await tester.pumpAndSettle();
      expect(find.text('强制下线'), findsWidgets);

      await tester.tap(find.text('强制下线').last);
      await tester.pumpAndSettle();

      final call = adapter.callFor('dashboard/tooffline');
      expect(call, isNotNull);
      expect(call!.queryParameters['sessionid'], '36035');
      expect(find.text('已强制下线'), findsOneWidget);
    });
  });

  group('账号服务页', () {
    Future<void> pump(WidgetTester tester, _RouteAdapter adapter) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkAccountProvider.overrideWith((ref) async => _account),
            networkPlansProvider.overrideWith(
              (ref) async => const [
                NetworkPlan(
                  id: '2',
                  name: '包月（学生50元）',
                  description: '学生宿舍有线网络适用',
                  selectable: true,
                ),
              ],
            ),
            networkStopLogsProvider.overrideWith((ref) async => const []),
            networkReopenLogsProvider.overrideWith((ref) async => const []),
            networkPackageLogsProvider.overrideWith((ref) async => const []),
            netFeeDioProvider.overrideWithValue(
              Dio(BaseOptions(baseUrl: 'https://wxcourse.jxufe.cn'))
                ..httpClientAdapter = adapter,
            ),
            networkServiceGuidProvider.overrideWith((ref) async => 'GUID-1'),
          ],
          child: const MaterialApp(home: NetworkServicesScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('列出账号状态与三项业务办理', (tester) async {
      await pump(tester, _RouteAdapter(_routes()));

      expect(find.text('账号服务'), findsWidgets);
      expect(find.text('账号报停'), findsOneWidget);
      expect(find.text('账号复通'), findsOneWidget);
      expect(find.text('预约套餐'), findsOneWidget);
      expect(find.text('绑定运营商账号'), findsOneWidget);
      expect(find.textContaining('未启用运营商对接功能'), findsOneWidget);
      expect(find.text('余额 12.50 元'), findsOneWidget);
    });

    testWidgets('立即报停：确认后 POST service/stop（flag=1 + token）', (tester) async {
      final adapter = _RouteAdapter(_routes());
      await pump(tester, adapter);

      await tester.tap(find.text('账号报停'));
      await tester.pumpAndSettle();
      expect(find.textContaining('停机后将无法继续使用网络'), findsOneWidget);

      await tester.tap(find.text('立即报停'));
      await tester.pumpAndSettle();

      expect(adapter.callFor('service/stop'), isNotNull);
      expect(adapter.bodyFor('service/stop'), contains('flag=1'));
      expect(
        adapter.bodyFor('service/stop'),
        contains('ajaxCsrfToken=tok-stop'),
      );
      expect(find.text('报停成功'), findsOneWidget);
    });

    testWidgets('预约套餐：弹层列出来自页面的可选项，POST doPackage(serid)', (tester) async {
      final adapter = _RouteAdapter(_routes());
      await pump(tester, adapter);

      await tester.tap(find.text('预约套餐'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('netsvc_package_2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('netsvc_package_2')));
      await tester.pumpAndSettle();

      expect(adapter.bodyFor('service/doPackage'), contains('serid=2'));
      expect(
        adapter.bodyFor('service/doPackage'),
        contains('csrftoken=csrf-pkg'),
      );
    });
  });

  group('账单与记录页', () {
    testWidgets('上网记录分页：汇总 + 明细（近一年窗口）', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkUsageRecordsProvider.overrideWith(
              (ref, query) async => [
                NetworkUsageRecord.fromJson({
                  'loginTime': 1789032120000,
                  'logoutTime': 1789189968000,
                  'time': 2631,
                  'flow': 6221.137,
                  'costMoney': 0,
                  'internetDownFlow': 4228.652,
                  'internetUpFlow': 1992.485,
                  'chinanetDownFlow': 0,
                  'chinanetUpFlow': 0,
                  'userIp': '10.16.26.160',
                  'macAddress': '24B2B9A1B1C5',
                }),
              ],
            ),
            networkMonthBillsProvider.overrideWith(
              (ref, year) async => const NetworkMonthBills(
                year: 2026,
                items: [],
                summary: NetworkMonthBillSummary.empty,
              ),
            ),
            // 四个分页的 TabBarView 会在 build 时同时构造 → 四个 provider 都要给值，
            // 否则未覆盖的那个会去打开 Hive box（测试里没有 Hive.init）。
            networkPaymentsProvider.overrideWith((ref) async => const []),
            networkOperatorLogsProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(home: NetworkRecordsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('上网记录'), findsWidgets);
      expect(find.text('记录数'), findsOneWidget);
      expect(find.text('总流量'), findsOneWidget);
      expect(find.text('6.08 GB'), findsWidgets);
      expect(find.textContaining('10.16.26.160'), findsOneWidget);
    });

    testWidgets('历史账单分页：按年查询并给年度合计', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkUsageRecordsProvider.overrideWith(
              (ref, query) async => const [],
            ),
            networkPaymentsProvider.overrideWith((ref) async => const []),
            networkOperatorLogsProvider.overrideWith((ref) async => const []),
            networkMonthBillsProvider.overrideWith(
              (ref, year) async => NetworkMonthBills(
                year: year,
                items: [
                  NetworkMonthBill.fromRow([
                    1787760000000,
                    1790438400000,
                    'GPON学生12.5/月|fid=x|',
                    12.5,
                    0.0,
                    0.0,
                    0.0,
                    1787767206000,
                  ]),
                ],
                summary: const NetworkMonthBillSummary(
                  minutes: 122619,
                  baseMoney: 100,
                  flowMb: 1477237.857,
                  usageMoney: 0,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: NetworkRecordsScreen(initialTab: NetworkRecordsTab.bills),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('基本月租'), findsOneWidget);
      // 汇总卡与明细行都会出现 100.00（基本月租合计）
      expect(find.text('100.00'), findsWidgets);
      expect(find.byKey(const Key('netsvc_bill_total')), findsOneWidget);
      // 账期含末日（服务端给的是开区间端点）
      expect(find.textContaining('2026-08-27 ~ 2026-09-26'), findsOneWidget);
      // 套餐名去掉 `|fid=…|` 尾巴
      expect(find.textContaining('GPON学生12.5/月'), findsWidgets);
    });
  });

  group('我的设备页 / 账号设置页', () {
    testWidgets('设备页：在线会话 + 已绑定设备（可解绑）', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkOnlineSessionsProvider.overrideWith(
              (ref) async => [
                NetworkOnlineSession.fromJson({
                  'sessionId': '36035',
                  'ip': '10.16.80.77',
                  'mac': 'A24A4082511F',
                  'loginTime': '2026-09-16 17:10:45',
                  'useTime': '864',
                  'upFlow': '1729',
                  'downFlow': '13033',
                  'terminalType': '#移动终端',
                }),
              ],
            ),
            networkDevicesProvider.overrideWith(
              (ref) async => [
                NetworkDevice.fromRow([
                  '1',
                  '24B2B9A1B1C5',
                  '#PC',
                  '2026-09-12 00:00:00',
                  '10.16.26.160',
                ]),
              ],
            ),
          ],
          child: const MaterialApp(home: NetworkDevicesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('当前在线'), findsOneWidget);
      expect(find.text('已绑定设备'), findsOneWidget);
      expect(find.text('24-B2-B9-A1-B1-C5'), findsOneWidget);
      expect(
        find.byKey(const Key('netsvc_devices_offline_36035')),
        findsOneWidget,
      );
    });

    testWidgets('账号设置页：账号信息只读 + 修改密码校验两次一致', (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkAccountProvider.overrideWith((ref) async => _account),
          ],
          child: const MaterialApp(home: NetworkProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2000000000'), findsOneWidget);
      // 证件号只展示前后各 3 位
      expect(find.text('360****0018'), findsOneWidget);
      expect(find.text('修改上网密码'), findsWidgets);
      expect(find.byKey(const Key('netsvc_profile_save')), findsOneWidget);

      await tester.tap(find.text('修改上网密码').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('netsvc_pwd_old')), 'old123');
      await tester.enterText(find.byKey(const Key('netsvc_pwd_new')), 'abc123');
      await tester.enterText(
        find.byKey(const Key('netsvc_pwd_confirm')),
        'abc999',
      );
      await tester.tap(find.text('确定修改'));
      await tester.pumpAndSettle();

      expect(find.text('两次输入的密码不一样'), findsOneWidget);

      // 新密码过短也要拦
      await tester.enterText(find.byKey(const Key('netsvc_pwd_new')), 'ab');
      await tester.enterText(find.byKey(const Key('netsvc_pwd_confirm')), 'ab');
      await tester.tap(find.text('确定修改'));
      await tester.pumpAndSettle();
      expect(find.text('新密码需 6–16 位'), findsOneWidget);
    });
  });

  group('内嵌 WebView 支持判定（微信充值 / 外部入口共用）', () {
    test('只有 Android / iOS 能内嵌', () {
      expect(inAppWebViewSupported('android'), isTrue);
      expect(inAppWebViewSupported('ios'), isTrue);
      expect(inAppWebViewSupported('windows'), isFalse);
      expect(inAppWebViewSupported('linux'), isFalse);
      expect(inAppWebViewSupported('macos'), isFalse);
    });
  });
}
