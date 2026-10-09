import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/core/web/external_url.dart';
import 'package:smarter_jxufe/core/web/in_app_web_screen.dart';
import 'package:smarter_jxufe/core/web/web_session.dart';
import 'package:smarter_jxufe/features/net_fee/data/datasources/net_fee_recharge_remote_datasource.dart';
import 'package:smarter_jxufe/features/net_fee/data/datasources/net_fee_remote_datasource.dart';
import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/net_fee/data/qr_pay_url.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_recharge.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_pay_screen.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_recharge_sheet.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_screen.dart';
import 'package:smarter_jxufe/features/network_service/data/datasources/network_service_remote_datasource.dart';
import 'package:smarter_jxufe/features/network_service/data/providers/network_service_providers.dart';
import 'package:smarter_jxufe/features/platform_guid/data/providers/guid_providers.dart';

/// 1×1 的透明 PNG —— 收银台要 `Image.memory` 一张真图，假数据源给它。
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// 一张**能被解码**的合成二维码，内容是 `weixin://wxpay/bizpayurl?pr=TESTONLYTOKEN`。
///
/// 由 cv2 现生成（1-bit PNG，334 字节 → base64 448 字符）；**不是**真机那张 ——
/// 真机二维码里装的是一次性支付 token，不该进仓库（§34 隐私纪律）。
///
/// ⚠ 这张 1-bit PNG 顺带钉住一条实测口径：`image` 解 1-bit / 调色板 PNG 时
/// `getPixel()` 给的是**未缩放的通道值**（0/1 而不是 0/255），少了
/// `decodeWeChatPayUrl` 里那次 `convert(numChannels: 3)` 就会解不出来。
final Uint8List _weChatQrPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAKQAAACkAQAAAAAxzrjsAAABFUlEQVR42u2XsZHsMAxDH3cuhzrY'
  '/styB2AFuMDe6H6I7C+dSAwwmicKGE/4W/viX/Xt/h/dmTkcYO9lS1cJA4OOks55fwBGyGQEoy6d'
  'iznaPvVzxMpd3RjBlYW4ozuBAX2cAeSGP5C7RPCzjju6OMTi/jq6L8DCA0arS6c2vzqs4H0hhlR0'
  'SYJsQ4QS9fgaK8TkucbWvSWxY6NnU5ozGxFZ99FrHEKMhWOVOEyA0Yo1aEHU3huKIiSTEocXcMzs'
  'bJbjlp9xm4Mj2S77g4ySO4LocYgVlj1SUI8D8DxhCfc4PK6gSKHkD5883jfGM3I3N98XuxPtlHP+'
  'jcgxJV//8JUAPyFXmrOdgbUijenl/Pc/4Nv91C9F2PqLdBaxlwAAAABJRU5ErkJggg==',
);

/// 按 URL 子串路由的假适配器（服务校园卡那几个接口，不碰真网络）。
class _FakeApiAdapter implements HttpClientAdapter {
  _FakeApiAdapter(this.routes);

  final Map<String, String> routes;
  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final url = options.uri.toString();
    String? body;
    for (final key in routes.keys) {
      if (url.contains(key)) {
        body = routes[key];
        break;
      }
    }
    return ResponseBody.fromString(
      body ?? '{}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  RequestOptions? callFor(String key) {
    for (final call in calls) {
      if (call.uri.toString().contains(key)) return call;
    }
    return null;
  }

  @override
  void close({bool force = false}) {}
}

NetFeeRemoteDataSource _sourceWithAdapter(HttpClientAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://wxcourse.jxufe.cn',
      validateStatus: (int? _) => true,
    ),
  );
  dio.httpClientAdapter = adapter;
  return NetFeeRemoteDataSource(dio);
}

NetFeeRemoteDataSource _sourceWith(Map<String, String> routes) =>
    _sourceWithAdapter(_FakeApiAdapter(routes));

/// 校方 `getWfczPayType` 的真实形状（三层嵌套 `result.result.result`）。
const String _wfczPayTypes =
    '{"code":1,"result":{"result":{"result":['
    '{"dict_key":"weixin","dict_value":"https://wxcourse.jxufe.cn/1585799510593/pay/h5",'
    '"desc":"微信支付"},'
    '{"dict_key":"card","dict_value":"https://wxcourse.jxufe.cn/1585799510593/pay/cardPay",'
    '"desc":"校园卡支付"}]}}}';

const String _checkAppAuthBody =
    '{"code":200,"result":{"username":"ENC==",'
    '"pageUrl":"/pages/modules/developer/wfcz/view?cardinfo=abc&sno=0000001&openId=OID+AB="}}';

/// 假收银台数据源：不碰网络，但保留真实接口形状（下单 / 取图 / 轮询）。
class _FakeRechargeSource extends NetFeeRechargeRemoteDataSource {
  _FakeRechargeSource({
    this.failWith,
    this.payStates = const <String>[''],
    this.failQr = false,
    Uint8List? qrBytes,
  }) : _qrBytes = qrBytes ?? _tinyPng,
       super(Dio());

  /// 合成订单号（**不要用真机实测拿到的那几个**：测试文件是入库文件，§34 纪律）。
  static const String orderNo = '20261009000000000042';

  /// 非 null → `createOrder` 抛这个（验「下单失败 → 给网页兜底」）。
  final Object? failWith;

  /// 每次 `fetchPayState` 依次返回的状态；用完后一直返回最后一个。
  final List<String> payStates;

  final bool failQr;

  /// 假二维码图：默认是解不出 `weixin://` 的 1×1 空白图，
  /// 手机端唤起微信的用例传 [_weChatQrPng]。
  final Uint8List _qrBytes;

  int created = 0;
  int qrFetches = 0;
  int payChecks = 0;

  @override
  Future<NetFeeOrder> createOrder({
    required String account,
    required double amount,
  }) async {
    created++;
    if (failWith != null) throw failWith!;
    return NetFeeOrder(orderNo: orderNo, amount: amount, account: account);
  }

  @override
  Future<Uint8List> fetchQrImage(String orderNo) async {
    qrFetches++;
    if (failQr) throw const NetFeeRechargeException('二维码图片是空的');
    return _qrBytes;
  }

  @override
  Future<String> fetchPayState(String orderNo) async {
    payChecks++;
    if (payStates.isEmpty) return '';
    final index = payChecks - 1;
    return payStates[index < payStates.length ? index : payStates.length - 1];
  }
}

const NetFeeSummary _summary = NetFeeSummary(
  source: NetFeeSource.wxLive,
  hasGuid: true,
  balance: 12.5,
  username: '2000000000',
);

/// 面板返回值的**句柄**。
///
/// ⚠ 不能让 `_openSheet` 直接返回 `NetFeeRechargeRequest?`：那是**调用时刻的快照**，
/// 而面板是「先打开、后提交」——返回值只会在用户点「去支付」之后才出现，
/// 快照永远是 null（第一版就这么写错了）。
class _SheetHandle {
  NetFeeRechargeRequest? result;
  bool closed = false;
}

/// 点开充值面板（弹层宿主是一个按钮）。
Future<_SheetHandle> _openSheet(
  WidgetTester tester, {
  String? account = '2000000000',
  double? balance,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final handle = _SheetHandle();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              handle.result = await showNetFeeRechargeSheet(
                context,
                account: account,
                balance: balance,
              );
              handle.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return handle;
}

/// 校园网页：第一段余额卡 + 第二段网络服务（第二段统一给「未配置 GUID」错误态，
/// 这样它不会去碰 Hive / 网络）。
Future<void> _pumpScreen(
  WidgetTester tester, {
  NetFeeSummary summary = _summary,
  bool inAppWebView = true,
  List<Uri>? openedExternal,
  List<EmbeddedWebRequest>? embedded,
  void Function()? onLoad,
  GlobalKey<NavigatorState>? navKey,
  NetFeeRechargeRemoteDataSource? rechargeSource,
  NetFeeRemoteDataSource? netFeeSource,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        netFeeSummaryProvider.overrideWith((ref) async {
          onLoad?.call();
          return summary;
        }),
        networkAccountProvider.overrideWith(
          (ref) async => throw const NetworkServiceException(
            '未配置微信平台标识（GUID）',
            needGuid: true,
          ),
        ),
        // 收银台**默认就给假数据源**：真数据源会去 self.jxufe.cn 下单（真下单！）。
        netFeeRechargeRemoteDataSourceProvider.overrideWithValue(
          rechargeSource ?? _FakeRechargeSource(),
        ),
        // 校园卡那条路用小程序侧的数据源（同样必须给假的：真调就是真扣款）。
        if (netFeeSource != null)
          netFeeRemoteDataSourceProvider.overrideWithValue(netFeeSource),
        platformGuidProvider.overrideWith((ref) async => 'guid-test'),
        inAppWebViewSupportedProvider.overrideWithValue(inAppWebView),
        webViewScreenBuilderProvider.overrideWithValue((request) {
          embedded?.add(request);
          return Scaffold(
            appBar: AppBar(title: Text(request.title)),
            body: const Center(child: Text('FAKE_WEBVIEW')),
          );
        }),
        externalUrlOpenerProvider.overrideWithValue((uri) async {
          openedExternal?.add(uri);
          return true;
        }),
      ],
      child: MaterialApp(
        navigatorKey: navKey,
        // 页面靠 `PageAutoRefresher.didPopNext` 在「从支付页返回」时重取余额
        // —— 观察者不注册，这条链路在测试里根本不会触发。
        navigatorObservers: [appRouteObserver],
        home: const NetFeeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 走完「点充值 → 选金额 → 去支付」。
Future<void> _tapRechargeAndPay(WidgetTester tester, {int? amount}) async {
  await tester.tap(find.byKey(const Key('netfee_recharge')));
  await tester.pumpAndSettle();
  if (amount != null) {
    await tester.tap(find.byKey(Key('netfeeRechargeAmount$amount')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
  await tester.pumpAndSettle();
}

/// 打开收银台 —— 它是被 **push** 的二级页（与真实路径一致：home 上的按钮 push 它）。
///
/// ⚠ 每个用例末尾要 `await tester.pumpWidget(const SizedBox())` 卸载页面：
/// 收银台挂着 3 秒轮询计时器，不卸载测试框架会报 "A Timer is still pending"。
Future<_FakeRechargeSource> _pumpPayScreen(
  WidgetTester tester, {
  _FakeRechargeSource? source,
  NetFeeRechargeRequest request = const NetFeeRechargeRequest(
    account: '2000000000',
    amount: 50,
  ),
  List<EmbeddedWebRequest>? embedded,
  bool inAppWebView = true,
  bool weChatApp = true,
  List<Uri>? openedExternal,
  bool openFails = false,
  void Function(bool? paid)? onResult,
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final src = source ?? _FakeRechargeSource();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        netFeeRechargeRemoteDataSourceProvider.overrideWithValue(src),
        inAppWebViewSupportedProvider.overrideWithValue(inAppWebView),
        // 手机端才会走「唤起微信」那条路；测试环境的 defaultTargetPlatform 是
        // android，所以这里显式 override 才能分别覆盖两端。
        inAppWeChatPaySupportedProvider.overrideWithValue(weChatApp),
        webViewScreenBuilderProvider.overrideWithValue((r) {
          embedded?.add(r);
          return Scaffold(
            appBar: AppBar(title: Text(r.title)),
            body: const Center(child: Text('FAKE_WEBVIEW')),
          );
        }),
        externalUrlOpenerProvider.overrideWithValue((uri) async {
          openedExternal?.add(uri);
          return !openFails;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final paid = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => NetFeePayScreen(request: request),
                  ),
                );
                onResult?.call(paid);
              },
              child: const Text('openPay'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('openPay'));
  await tester.pumpAndSettle();
  return src;
}

void main() {
  group('校园网充值口径（校方 WebPay 支付页）', () {
    test('账号与金额都预填，且直接开 toRecharge', () {
      final url = netFeeRechargeUrl(account: '2000000000', amount: 50);
      expect(
        url,
        'https://self.jxufe.cn/WebPay/toRecharge'
        '?paytype=3&account=2000000000&amount=50',
      );
    });

    test('★ 不走 /WebPay/recharge 入口 —— 那条 302 会把 amount 丢掉', () {
      // 实测：`…/WebPay/recharge?…&amount=50` 302 之后的 Location 只剩
      // `paytype` 与 `account`，金额预填静默失效。
      final url = netFeeRechargeUrl(account: '2000000000', amount: 20);
      expect(url.contains('/WebPay/recharge'), isFalse);
      expect(url.contains('/WebPay/toRecharge'), isTrue);
      // 校方支付页唯一开通的支付方式 = 微信（3）。
      expect(url.contains('paytype=3'), isTrue);
    });

    test('金额规整到分，整数不带小数点', () {
      expect(
        netFeeRechargeUrl(account: '1', amount: 12.345),
        contains('amount=12.35'),
      );
      expect(
        netFeeRechargeUrl(account: '1', amount: 50.0),
        contains('amount=50'),
      );
      expect(netFeeNormalizeAmount(0.1 + 0.2), 0.3);
      expect(netFeeNormalizeAmount(9.999), 10.0);
    });

    test('账号里的特殊字符会被编码', () {
      expect(
        netFeeRechargeUrl(account: 'a@b.com', amount: 10),
        contains('account=a%40b.com'),
      );
    });

    test('金额校验：只挡「明显不是金额」，不复刻校方上下限', () {
      expect(netFeeRechargeAmountError(''), isNotNull);
      expect(netFeeRechargeAmountError('  '), isNotNull);
      expect(netFeeRechargeAmountError('abc'), isNotNull);
      expect(netFeeRechargeAmountError('0'), isNotNull);
      expect(netFeeRechargeAmountError('-5'), isNotNull);
      expect(netFeeRechargeAmountError('12.5'), isNull);
      expect(netFeeRechargeAmountError('50'), isNull);
      // 校方页面自己按 `getExtraInfo` 校验上下限 —— App 侧照抄一份只会过期。
      expect(netFeeRechargeAmountError('500'), isNull);
    });

    test('账号校验照校方 recharge.js 的判据', () {
      expect(netFeeRechargeAccountError(''), isNotNull);
      expect(netFeeRechargeAccountError('   '), isNotNull);
      expect(netFeeRechargeAccountError('a' * 31), isNotNull);
      expect(netFeeRechargeAccountError('2000000000'), isNull);
      expect(netFeeRechargeAccountError('a@b.com'), isNull);
    });

    test('请求对象的 toString 不带账号', () {
      const request = NetFeeRechargeRequest(
        account: '2000000000',
        amount: 50,
      );
      expect(request.toString(), isNot(contains('2000000000')));
      expect(request.toString(), contains('50'));
    });

    test('快速档 = 校方五档 + App 自己加的 12.5（套餐月费）', () {
      expect(
        kNetFeeRechargeQuickAmounts,
        <double>[10, 12.5, 20, 50, 100, 200],
      );
    });
  });

  // 这一组守两件事：
  // ① **花了钱的功能不能默认错** —— 校方 `recharge.js` 的 `initAmount` 分支把 `flag`
  //    写反了：URL 预填的**档位**金额会被 `$("#moneybut1").click()` 打回 10 元
  //    （实测 50 / 100 都变 10；非档位的 30 反而正确）；
  // ② **「选完金额直接出二维码」** —— 二维码在校方流程里本来就有（POST → `wxPaySaoma`
  //    扫码页），只差替用户点掉一次「立即支付」，且不能重复下单。
  group('页面脚本：修金额 + 自动提交到二维码页', () {
    test('★ 借校方自己的 changeMoney 修档位金额', () {
      final script = netFeeRechargePageScript(amount: 50, submitToken: 'tok1');

      // 按「值」找档位，不写死 `moneybut3` —— 校方增删档位也不会错位。
      expect(script, contains("querySelectorAll('.moneyBut')"));
      expect(script, contains('var v=50;'));
      expect(script, contains('parseFloat(bs[i].value)===v'));
      expect(script, contains('changeMoney(id)'));
    });

    test('★ 自动提交，且用一次性 token 防重复下单', () {
      final script = netFeeRechargePageScript(amount: 50, submitToken: 'tok1');

      expect(script, contains('fm.querySelector("input[type=submit]")'));
      expect(script, contains('sb.click()'));
      expect(script, contains('sessionStorage.getItem(key)'));
      expect(script, contains("var key='dshSubmit:tok1';"));
      // 用户点「上一页」退回表单时，同一个 token 会拦住第二次提交（不再下一单）；
      // 而换一次「去支付」就是新 token → 仍能正常下单。
      expect(
        netFeeRechargePageScript(amount: 50, submitToken: 'tok2'),
        contains('dshSubmit:tok2'),
      );
      expect(
        newNetFeeRechargeSubmitToken(DateTime(2026, 10, 9)),
        startsWith('r'),
      );
    });

    test('脚本无害：不是那个页面就空转（幂等、不误伤）', () {
      final script = netFeeRechargePageScript(amount: 30, submitToken: 'tok1');

      // 修金额：`changeMoney` 不在（移动版 / 结果页）→ 直接退出。
      expect(script, contains("typeof changeMoney!=='function'"));
      // 自动提交：没有表单 / 没有提交按钮（扫码页 / 成功页）→ 什么都不做。
      expect(script, contains('if(!fm||!sb)return;'));
      expect(script, contains('catch(e){}'));
      // 脚本会留在 WebView 的 JS 上下文里 → 一个凭据字都不许有。
      expect(script, isNot(contains('account')));
      // 非档位金额（0.01 / 12.5）按原样交给页面「其他」分支。
      expect(script, contains('var v=30;'));
      expect(
        netFeeRechargePageScript(amount: 12.5, submitToken: 't'),
        contains('var v=12.5;'),
      );
    });

    test('★ 内嵌件必须真的执行 pageScript（否则这一切只是空话）', () {
      // WebView 在 widget 测试里建不出来（没有平台实现），所以这条契约
      // 只能按源码守：加载结束的钩子里必须把脚本交给 evaluateJavascript。
      final source = File(
        'lib/core/web/in_app_web_screen.dart',
      ).readAsStringSync();
      expect(source, contains('request.pageScript'));
      expect(source, contains('evaluateJavascript('));
    });
  });

  group('充值面板', () {
    testWidgets('预填账号 + 默认第一档 + 余额预估', (tester) async {
      await _openSheet(tester, balance: 12.5);

      expect(find.text('校园网充值'), findsOneWidget);
      final accountField = tester.widget<TextField>(
        find.byKey(const Key('netfeeRechargeAccount')),
      );
      expect(accountField.controller?.text, '2000000000');
      // 默认选中第一档，按钮把金额写出来
      expect(find.text('扫码支付 ¥10'), findsOneWidget);
      expect(find.text('当前余额 12.5 元 → 充值后预计 22.5 元'), findsOneWidget);
      // 打开后直接是校方扫码页（口径见 domain 的 netFeeRechargePageScript）
      expect(find.textContaining('微信收款二维码'), findsOneWidget);
    });

    testWidgets('换档位与自填金额都反映到按钮上', (tester) async {
      await _openSheet(tester, balance: 12.5);

      await tester.tap(find.byKey(const Key('netfeeRechargeAmount50')));
      await tester.pumpAndSettle();
      expect(find.text('扫码支付 ¥50'), findsOneWidget);
      expect(find.text('当前余额 12.5 元 → 充值后预计 62.5 元'), findsOneWidget);

      // 自填金额 → 快速档取消选中
      await tester.enterText(
        find.byKey(const Key('netfeeRechargeCustom')),
        '30',
      );
      await tester.pumpAndSettle();
      expect(find.text('扫码支付 ¥30'), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(
        find.byKey(const Key('netfeeRechargeAmount50')),
      );
      expect(chip.selected, isFalse);

      // 反过来点档位 → 自填框被清空
      await tester.tap(find.byKey(const Key('netfeeRechargeAmount20')));
      await tester.pumpAndSettle();
      final custom = tester.widget<TextField>(
        find.byKey(const Key('netfeeRechargeCustom')),
      );
      expect(custom.controller?.text, isEmpty);
      expect(find.text('扫码支付 ¥20'), findsOneWidget);
    });

    testWidgets('★ 12.5 元档（套餐月费）：不显示成 10.0，金额一路传到请求里', (tester) async {
      final handle = await _openSheet(tester, balance: 12.5);

      // 档位标签与 key 都走 fmtYuan → 「12.5 元」，不是「12.5 元」以外的怪样子
      expect(find.byKey(const Key('netfeeRechargeAmount12.5')), findsOneWidget);
      expect(find.text('12.5 元'), findsOneWidget);

      await tester.tap(find.byKey(const Key('netfeeRechargeAmount12.5')));
      await tester.pumpAndSettle();
      expect(find.text('扫码支付 ¥12.5'), findsOneWidget);
      expect(find.text('当前余额 12.5 元 → 充值后预计 25 元'), findsOneWidget);

      await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
      await tester.pumpAndSettle();

      expect(handle.result, isNotNull);
      expect(handle.result!.amount, 12.5);
      expect(handle.result!.url, contains('amount=12.5'));
    });

    testWidgets('金额非法 → 就地报错，不关面板也不跳支付页', (tester) async {
      final handle = await _openSheet(tester);

      await tester.enterText(
        find.byKey(const Key('netfeeRechargeCustom')),
        'abc',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('netfeeRechargeError')), findsOneWidget);
      expect(find.text('金额只能是数字'), findsOneWidget);
      expect(handle.closed, isFalse);
      // 面板还在
      expect(find.byKey(const Key('netfeeRechargeGo')), findsOneWidget);
    });

    testWidgets('账号为空 → 就地报错', (tester) async {
      final handle = await _openSheet(tester, account: null);

      await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
      await tester.pumpAndSettle();

      expect(find.text('请填写上网账号'), findsOneWidget);
      expect(handle.closed, isFalse);
      expect(find.byKey(const Key('netfeeRechargeGo')), findsOneWidget);
    });

    testWidgets('提交返回账号与金额（规整到分）', (tester) async {
      final handle = await _openSheet(tester);

      await tester.enterText(
        find.byKey(const Key('netfeeRechargeCustom')),
        '12.345',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
      await tester.pumpAndSettle();

      final result = handle.result;
      expect(result, isNotNull);
      expect(result!.account, '2000000000');
      expect(result.amount, 12.35);
      expect(result.url, contains('account=2000000000&amount=12.35'));
    });

    testWidgets('取消返回 null', (tester) async {
      final handle = await _openSheet(tester);

      await tester.tap(find.byKey(const Key('netfeeRechargeCancel')));
      await tester.pumpAndSettle();

      expect(handle.closed, isTrue);
      expect(handle.result, isNull);
      expect(find.byKey(const Key('netfeeRechargeGo')), findsNothing);
    });
  });

  group('收银台（二维码在 App 自己的 UI 里）', () {
    testWidgets('进页即下单：显示金额 / 账号 / 二维码图 / 订单号', (tester) async {
      final source = await _pumpPayScreen(tester);

      expect(source.created, 1, reason: '进页就该下好单');
      expect(source.qrFetches, 1, reason: '二维码要取回来');
      expect(find.byKey(const Key('netfeePayQr')), findsOneWidget);
      expect(find.text('¥ 50'), findsOneWidget);
      expect(find.text('账号 2000000000'), findsOneWidget);
      expect(find.textContaining(_FakeRechargeSource.orderNo), findsOneWidget);
      // 我们自己的界面 —— 一条网页都不嵌。
      expect(find.text('FAKE_WEBVIEW'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('★ 轮询到 paystate=3 → 支付成功，点「完成」返回 true', (tester) async {
      bool? result;
      await _pumpPayScreen(
        tester,
        source: _FakeRechargeSource(payStates: const ['9', '3']),
        onResult: (v) => result = v,
      );

      // 第一次轮询：还是没付
      await tester.pump(kNetFeePayPollInterval);
      await tester.pump();
      expect(find.byKey(const Key('netfeePayPaid')), findsNothing);

      // 第二次轮询：付了
      await tester.pump(kNetFeePayPollInterval);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('netfeePayPaid')), findsOneWidget);
      expect(find.text('支付成功'), findsOneWidget);

      await tester.tap(find.byKey(const Key('netfeePayDone')));
      await tester.pumpAndSettle();
      expect(result, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('「我已完成支付」手动查一次', (tester) async {
      final source = await _pumpPayScreen(
        tester,
        source: _FakeRechargeSource(payStates: const ['3']),
      );

      await tester.tap(find.byKey(const Key('netfeePayCheck')));
      await tester.pumpAndSettle();

      expect(source.payChecks, greaterThanOrEqualTo(1));
      expect(find.byKey(const Key('netfeePayPaid')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('下单失败 → 错误态 + 「改用校方网页支付」（带自动提交脚本）', (tester) async {
      final embedded = <EmbeddedWebRequest>[];
      await _pumpPayScreen(
        tester,
        source: _FakeRechargeSource(
          failWith: const NetFeeRechargeException('校方没有返回订单号'),
        ),
        embedded: embedded,
      );

      expect(find.textContaining('校方没有返回订单号'), findsOneWidget);
      expect(find.byKey(const Key('netfeePayQr')), findsNothing);

      await tester.tap(find.byKey(const Key('netfeePayFallbackWeb')));
      await tester.pumpAndSettle();

      expect(embedded, hasLength(1));
      expect(embedded.single.url, contains('/WebPay/toRecharge'));
      expect(embedded.single.pageScript, contains('sb.click()'));
      expect(embedded.single.pageScript, contains('var v=50;'));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('二维码取不回来 → 也是错误态，可重试', (tester) async {
      final source = await _pumpPayScreen(
        tester,
        source: _FakeRechargeSource(failQr: true),
      );

      expect(find.byKey(const Key('netfeePayRetry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('netfeePayRetry')));
      await tester.pumpAndSettle();
      expect(source.created, 2, reason: '重试要重新下单');

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('手机端唤起微信支付', () {
    test('★ 解码器能把校方二维码解成 weixin:// 支付链接', () {
      expect(
        decodeWeChatPayUrl(_weChatQrPng),
        'weixin://wxpay/bizpayurl?pr=TESTONLYTOKEN',
      );
    });

    test('解不出来一律返回 null，不抛异常（不能让充值走不下去）', () {
      expect(decodeWeChatPayUrl(_tinyPng), isNull, reason: '1×1 空白图');
      expect(
        decodeWeChatPayUrl(Uint8List.fromList(<int>[1, 2, 3])),
        isNull,
        reason: '垃圾字节',
      );
      expect(decodeWeChatPayUrl(Uint8List(0)), isNull, reason: '空字节');
    });

    testWidgets('★ 手机端：进页就唤起微信，二维码降为兜底', (tester) async {
      final opened = <Uri>[];
      await _pumpPayScreen(
        tester,
        source: _FakeRechargeSource(qrBytes: _weChatQrPng),
        openedExternal: opened,
      );

      expect(opened, hasLength(1));
      expect(
        opened.single.toString(),
        'weixin://wxpay/bizpayurl?pr=TESTONLYTOKEN',
      );
      expect(find.byKey(const Key('netfeePayOpenWeChat')), findsOneWidget);
      expect(find.textContaining('已打开微信'), findsOneWidget);
      // 兜底二维码还在（换台设备也能付）
      expect(find.byKey(const Key('netfeePayQr')), findsOneWidget);
      expect(find.textContaining('另一台设备'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('桌面端：不唤起，仍是「打开手机微信扫一扫付款」', (tester) async {
      final opened = <Uri>[];
      await _pumpPayScreen(
        tester,
        source: _FakeRechargeSource(qrBytes: _weChatQrPng),
        weChatApp: false,
        openedExternal: opened,
      );

      expect(opened, isEmpty);
      expect(find.byKey(const Key('netfeePayOpenWeChat')), findsNothing);
      expect(find.textContaining('打开手机微信扫一扫付款'), findsOneWidget);
      expect(find.byKey(const Key('netfeePayQr')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('唤起失败（没装微信）→ 提示改用二维码，付款路径不断', (tester) async {
      await _pumpPayScreen(
        tester,
        source: _FakeRechargeSource(qrBytes: _weChatQrPng),
        openFails: true,
      );

      expect(find.textContaining('没能唤起微信'), findsOneWidget);
      expect(find.byKey(const Key('netfeePayQr')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('二维码解不出 weixin:// → 按钮禁用，但二维码照样能付', (tester) async {
      await _pumpPayScreen(tester); // 默认那张 1×1 图解不出来

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('netfeePayOpenWeChat')),
      );
      expect(button.onPressed, isNull);
      expect(find.byKey(const Key('netfeePayQr')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('充到目标余额（自动算差额 · 2026-10-09 五轮）', () {
    testWidgets('★ 目标 50、余额 12.5 → 自动算出还要充 37.5', (tester) async {
      final handle = await _openSheet(tester, balance: 12.5);

      await tester.tap(find.byKey(const Key('netfeeModeTarget')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('netfeeTarget50')), findsOneWidget);

      await tester.tap(find.byKey(const Key('netfeeTarget50')));
      await tester.pumpAndSettle();

      expect(find.textContaining('还需充值 37.5 元'), findsOneWidget);
      expect(find.text('扫码支付 ¥37.5'), findsOneWidget);

      await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
      await tester.pumpAndSettle();
      expect(handle.result?.amount, 37.5);
      expect(handle.result?.account, '2000000000');
    });

    testWidgets('目标不高于当前余额 → 说清「不需要充值」，且不提交', (tester) async {
      final handle = await _openSheet(tester, balance: 50);

      await tester.tap(find.byKey(const Key('netfeeModeTarget')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('netfeeTarget50')));
      await tester.pumpAndSettle();
      expect(find.textContaining('不需要充值'), findsOneWidget);

      await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
      await tester.pumpAndSettle();
      expect(handle.closed, isFalse);
      expect(find.textContaining('目标余额要高于当前余额'), findsOneWidget);
    });

    testWidgets('拿不到余额 → 目标模式直接不可选（算了也不准）', (tester) async {
      await _openSheet(tester, balance: null);

      final chip = tester.widget<ChoiceChip>(
        find.byKey(const Key('netfeeModeTarget')),
      );
      expect(chip.onSelected, isNull);
    });

    testWidgets('目标余额可自定义：输入 60、余额 12.5 → 充 47.5', (tester) async {
      final handle = await _openSheet(tester, balance: 12.5);

      await tester.tap(find.byKey(const Key('netfeeModeTarget')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('netfeeTargetCustom')),
        '60',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('还需充值 47.5 元'), findsOneWidget);

      await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
      await tester.pumpAndSettle();
      expect(handle.result?.amount, 47.5);
    });
  });

  group('校园卡充值（第二种充值方式 · 2026-10-09 四轮）', () {
    test('★ fetchChargeTypes 解析三层嵌套，拿到微信与校园卡各自的地址', () async {
      final source = _sourceWith(<String, String>{
        'getWfczPayType': _wfczPayTypes,
      });
      final types = await source.fetchChargeTypes();

      expect(types.map((t) => t.key), <String>['weixin', 'card']);
      expect(types[1].url, contains('/pay/cardPay'));
      expect(types[1].kind, NetFeeChargeKind.campusCard);
      expect(types[1].label, '校园卡支付');
      expect(types[0].kind, NetFeeChargeKind.weixin);
    });

    test('★ fetchWfczIdentity 从 pageUrl 取 openId，toString 不吐凭据', () async {
      final source = _sourceWith(<String, String>{
        'checkAppAuth': _checkAppAuthBody,
      });
      final id = await source.fetchWfczIdentity('guid-1234');

      expect(id.enc, 'ENC==');
      expect(id.openId, 'OID+AB=');
      expect(id.toString(), isNot(contains('ENC')));
      expect(id.toString(), isNot(contains('OID')));
    });

    test('★ payByCampusCard：code=0 成功；请求体是 enc / openId / total_fee', () async {
      final adapter = _FakeApiAdapter(<String, String>{
        '/pay/cardPay': '{"code":0}',
      });
      final source = _sourceWithAdapter(adapter);

      final error = await source.payByCampusCard(
        identity: const WfczIdentity(enc: 'ENC==', openId: 'OID+AB='),
        amount: 12.5,
        payUrl: 'https://wxcourse.jxufe.cn/1585799510593/pay/cardPay',
      );

      expect(error, isNull);
      final call = adapter.callFor('/pay/cardPay');
      expect(call, isNotNull);
      final data = call!.data as Map;
      expect(data['username'], 'ENC==', reason: '校园卡传的是 enc，不是学号');
      expect(data['openId'], 'OID+AB=');
      expect(data['total_fee'], '12.5');
    });

    test('payByCampusCard：非 0 把校方文案带回来', () async {
      final source = _sourceWith(<String, String>{
        '/pay/cardPay': '{"code":1,"message":"校园卡余额不足"}',
      });
      final error = await source.payByCampusCard(
        identity: const WfczIdentity(enc: 'E', openId: 'O'),
        amount: 50,
        payUrl: 'https://wxcourse.jxufe.cn/1585799510593/pay/cardPay',
      );
      expect(error, '校园卡余额不足');
    });

    testWidgets('面板：默认微信；切到校园卡后按钮与返回值都跟着变', (tester) async {
      final handle = await _openSheet(tester);

      expect(find.text('扫码支付 ¥10'), findsOneWidget);
      expect(find.byKey(const Key('netfeeChargeKindweixin')), findsOneWidget);

      await tester.tap(find.byKey(const Key('netfeeChargeKindcard')));
      await tester.pumpAndSettle();

      expect(find.text('校园卡支付 ¥10'), findsOneWidget);
      // 警告条与说明卡里都写了这句（一处是「提交即扣」的警告，一处是方式说明）
      expect(find.textContaining('直接从校园卡余额扣款'), findsWidgets);
      // 校方写死「校园卡扣费只能给自己充值」→ 账号框锁住
      final accountField = tester.widget<TextField>(
        find.byKey(const Key('netfeeRechargeAccount')),
      );
      expect(accountField.enabled, isFalse);

      await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
      await tester.pumpAndSettle();
      expect(handle.result?.kind, NetFeeChargeKind.campusCard);
    });

    testWidgets('★ 校园卡支付：二次确认后才真的调 cardPay，成功给提示', (tester) async {
      final adapter = _FakeApiAdapter(<String, String>{
        'checkAppAuth': _checkAppAuthBody,
        'getWfczPayType': _wfczPayTypes,
        '/pay/cardPay': '{"code":0}',
      });
      await _pumpScreen(tester, netFeeSource: _sourceWithAdapter(adapter));

      await tester.tap(find.byKey(const Key('netfee_recharge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('netfeeChargeKindcard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
      await tester.pumpAndSettle();

      // 还没确认 → 一个接口都不该发
      expect(adapter.callFor('/pay/cardPay'), isNull);
      expect(find.byKey(const Key('netfeeCampusPayConfirm')), findsOneWidget);

      await tester.tap(find.byKey(const Key('netfeeCampusPayConfirm')));
      await tester.pumpAndSettle();

      expect(adapter.callFor('/pay/cardPay'), isNotNull);
      expect(find.textContaining('校园卡扣款成功'), findsOneWidget);
    });
  });

  group('不是给自己充（2026-10-09 六轮）', () {
    testWidgets('★ 面板：切到校园卡会把账号还原成自己（校方只能给自己充）', (tester) async {
      await _openSheet(tester, account: '2000000000');

      // 先改成别人的账号，再切校园卡
      await tester.enterText(
        find.byKey(const Key('netfeeRechargeAccount')),
        '2000000002',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('netfeeChargeKindcard')));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const Key('netfeeRechargeAccount')),
      );
      expect(field.controller?.text, '2000000000', reason: '账号要还原成自己');
      expect(field.enabled, isFalse);
    });

    testWidgets('★ 微信给别人充：先弹确认，取消就不下单', (tester) async {
      final source = _FakeRechargeSource();
      await _pumpScreen(tester, rechargeSource: source);

      await tester.tap(find.byKey(const Key('netfee_recharge')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('netfeeRechargeAccount')),
        '2000000002',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
      await tester.pumpAndSettle();

      expect(find.text('给别人充值？'), findsOneWidget);
      expect(find.textContaining('2000000002'), findsWidgets);
      expect(find.textContaining('退不回来'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(source.created, 0, reason: '取消后一个接口都不该发');
      expect(find.byKey(const Key('netfeePayQr')), findsNothing);
    });

    testWidgets('★ 确认给别人充 → 才真的下单进收银台', (tester) async {
      final source = _FakeRechargeSource();
      await _pumpScreen(tester, rechargeSource: source);

      await tester.tap(find.byKey(const Key('netfee_recharge')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('netfeeRechargeAccount')),
        '2000000002',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('netfeeRechargeGo')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('netfeeOtherAccountConfirm')));
      await tester.pumpAndSettle();

      expect(source.created, 1);
      expect(find.byKey(const Key('netfeePayQr')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('给自己充（账号没改）→ 不弹确认，直接进收银台', (tester) async {
      final source = _FakeRechargeSource();
      await _pumpScreen(tester, rechargeSource: source);

      await _tapRechargeAndPay(tester, amount: 50);

      expect(find.text('给别人充值？'), findsNothing);
      expect(source.created, 1);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('校园网页接入', () {
    testWidgets('余额卡上有「充值」入口，点开是充值面板', (tester) async {
      await _pumpScreen(tester);

      expect(find.byKey(const Key('netfee_recharge')), findsOneWidget);
      expect(find.text('充值'), findsOneWidget);

      await tester.tap(find.byKey(const Key('netfee_recharge')));
      await tester.pumpAndSettle();
      expect(find.text('校园网充值'), findsOneWidget);
      expect(find.byKey(const Key('netfeeRechargeGo')), findsOneWidget);
    });

    testWidgets('★ 去支付进入 App 自己的收银台：下单 + 取二维码，不内嵌网页', (tester) async {
      final embedded = <EmbeddedWebRequest>[];
      final source = _FakeRechargeSource();
      await _pumpScreen(tester, embedded: embedded, rechargeSource: source);

      await _tapRechargeAndPay(tester, amount: 50);

      expect(source.created, 1, reason: '面板确认后就该下单');
      expect(source.qrFetches, 1);
      expect(embedded, isEmpty, reason: '主路径不该再打开校方网页');
      expect(find.text('FAKE_WEBVIEW'), findsNothing);
      expect(find.byKey(const Key('netfeePayQr')), findsOneWidget);
      expect(find.text('¥ 50'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('★ 从收银台返回 → 余额与记录自动重取', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      var loads = 0;
      await _pumpScreen(tester, onLoad: () => loads++, navKey: navKey);
      expect(loads, greaterThan(0));

      await _tapRechargeAndPay(tester, amount: 50);
      // ⚠ 实测：点「扫码支付」这一步**本身就会多取一次数** —— 关掉充值面板
      // 也是一次 pop，而 `appRouteObserver` 对 `ModalBottomSheetRoute` 同样发
      // `didPopNext`（loads 1 → 2）。这一次数可接受（用户刚离开余额卡），
      // 所以记成基线，只守真正要守的那条：**从收银台返回必须再刷一次**。
      final afterSheet = loads;

      // 从收银台返回（付了 / 放弃都一样）
      navKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(loads, greaterThan(afterSheet), reason: '返回校园网页必须重取余额');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('账号缺失 → 充值按钮禁用（不给出必然失败的入口）', (tester) async {
      await _pumpScreen(
        tester,
        summary: const NetFeeSummary(
          source: NetFeeSource.portal,
          hasGuid: false,
          balance: null,
          username: null,
        ),
      );

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('netfee_recharge')),
      );
      expect(button.onPressed, isNull);
    });
  });
}
