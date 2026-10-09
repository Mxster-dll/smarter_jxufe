import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/core/network/cas_browser_session.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository.dart';
import 'package:smarter_jxufe/core/web/external_url.dart';
import 'package:smarter_jxufe/core/web/in_app_web_screen.dart';
import 'package:smarter_jxufe/core/web/web_session.dart';
import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/ehall/data/ehall_endpoints.dart';
import 'package:smarter_jxufe/features/ehall/data/providers/ehall_session_provider.dart';
import 'package:smarter_jxufe/features/ehall/presentation/ehall_screen.dart';

/// 智慧江财（ehall）· 复用统一认证登录态的内嵌页守卫。
///
/// 用户诉求（原话）：「我希望内置一个 webview，用于加载原生网页：
/// http://ehall.jxufe.edu.cn/，但是支持直接复用当前项目里的登录 cookie」。
///
/// 本文件锁三件事：
/// 1. **凭据怎么进浏览器**（`casTgcCookie` / `WebSessionCookie` 的域、路径、seedUrl）；
/// 2. **凭据绝不上屏**（`toString` 只报名字与域 —— 与 `cookie_jar.dart` 的
///    `namesOf` 同一口径，§34 隐私纪律）；
/// 3. **TGC 必须先换成「当下可用」的那一枚**（`ensureTgcFor`：过期就静默重登），
///    否则用户看到的是统一认证登录页而不是门户（2026-10-08 实测：杀掉 App 后
///    `auth` box 里的旧票会被 CAS 用 `Max-Age=0` 删掉）。
class _FakeAuthRemote extends AuthRemoteDataSource {
  _FakeAuthRemote() : super(Dio());

  /// 还要再「过期」几次；0 = TGC 有效。
  int expireCalls = 0;

  /// [getCasRedirectUrl] 被调用次数。
  int redirectCalls = 0;

  /// 每次收到的 CAS 入口地址（断言调用方传的是 ehall 那个 service）。
  final List<String> casUrls = <String>[];

  /// 重登时服务端下发的新票。
  String freshTgc = 'tgc-fresh';

  @override
  Future<String> getCasRedirectUrl(String tgc, String casLoginUrl) async {
    redirectCalls++;
    casUrls.add(casLoginUrl);
    if (expireCalls > 0) {
      expireCalls--;
      throw TgcExpiredException('expired');
    }
    return 'https://ehall.example/amp-auth-adapter/loginSuccess?ticket=ST-$tgc';
  }

  @override
  Future<CasLoginPageInfo> fetchCasLoginPage() async => const CasLoginPageInfo(
    loginUrl: 'https://ssl.jxufe.edu.cn/cas/login?token=t1',
    execution: 'exec-1',
    sessionCookie: 'SESSION=abc',
  );

  @override
  Future<Response<dynamic>> detectMfa({
    required String username,
    required String password,
    required String fpVisitorId,
    required String referer,
    required String sessionCookie,
  }) async => Response<dynamic>(
    requestOptions: RequestOptions(path: '/cas/mfa/detect'),
    statusCode: 200,
    data: {
      'code': 0,
      'data': {'need': false, 'state': 'mfa-state-1'},
    },
  );

  @override
  Future<Response<dynamic>> login({
    required String username,
    required String password,
    required String fpVisitorId,
    required String mfaState,
    required String execution,
    required String loginUrl,
    required String sessionCookie,
    String trustAgent = '',
  }) async => Response<dynamic>(
    requestOptions: RequestOptions(path: '/cas/login'),
    statusCode: 302,
    headers: Headers.fromMap({
      'set-cookie': ['TGC=$freshTgc; Path=/cas/; Secure; HttpOnly'],
    }),
  );
}

void main() {
  group('凭据口径（casTgcCookie / WebSessionCookie）', () {
    test('TGC 包成 host-only Cookie：域 = ssl.jxufe.edu.cn、路径 = /', () {
      final cookie = casTgcCookie('TGT-abc');
      expect(cookie.name, 'TGC');
      expect(cookie.value, 'TGT-abc');
      expect(cookie.domain, 'ssl.jxufe.edu.cn');
      // ⚠ 刻意写 `/` 而不是照抄 CAS 下发的 `/cas/`：Cookie 的 path 只决定发送范围，
      // `/` 完整覆盖 `/cas/`，照抄反而漏掉同主机其它路径。
      expect(cookie.path, '/');
      expect(cookie.isSecure, isTrue);
      expect(cookie.seedUrl, 'https://ssl.jxufe.edu.cn/');
    });

    test('非 secure 的 Cookie 用 http seedUrl', () {
      const cookie = WebSessionCookie(
        name: 'a',
        value: 'b',
        domain: 'example.com',
        path: '/x/',
        isSecure: false,
      );
      expect(cookie.seedUrl, 'http://example.com/x/');
    });

    test('★ toString 只报名字与域，绝不带值（凭据不许进日志）', () {
      final cookie = casTgcCookie('TGT-super-secret');
      expect(cookie.toString(), isNot(contains('super-secret')));
      expect(cookie.toString(), isNot(contains('TGT-')));
      expect(cookie.toString(), contains('TGC'));
      expect(cookie.toString(), contains('ssl.jxufe.edu.cn'));

      const request = EmbeddedWebRequest(
        title: 'x',
        url: 'https://example.com/',
        cookies: [
          WebSessionCookie(name: 'TGC', value: 'secret-1', domain: 'h'),
        ],
      );
      expect(request.toString(), isNot(contains('secret-1')));
      expect(request.toString(), contains('1 cookies'));
    });
  });

  group('门户地址口径', () {
    test('门户与登录入口都是 http（学校没上 https，照实写）', () {
      expect(ehallPortalUrl, startsWith('http://'));
      expect(ehallLoginEntryUrl, startsWith('http://'));
    });

    test('登录入口把 service 百分号编码，指向门户根', () {
      expect(
        ehallLoginEntryUrl,
        contains('amp-auth-adapter/login?service=http%3A%2F%2Fehall.jxufe.edu.cn%2F'),
      );
    });

    test('CAS 入口的 service 与登录入口同源（都指向 ehall 的回调）', () {
      final service = Uri.parse(ehallCasLoginUrl).queryParameters['service'];
      expect(service, 'http://ehall.jxufe.edu.cn/amp-auth-adapter/loginSuccess');
      // 换票用它的 callback 与浏览器那一跳同 host，CAS 才认同一套白名单。
      expect(Uri.parse(service!).host, Uri.parse(ehallLoginEntryUrl).host);
    });
  });

  group('AuthRepository.ensureTgcFor（保证 TGC 当下可用）', () {
    late Directory tempDir;
    late Box<String> box;
    late AuthLocalDataSource local;
    late _FakeAuthRemote remote;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('ehall_session_test');
      Hive.init(tempDir.path);
      box = await Hive.openBox<String>('ehallSessionTest');
      local = AuthLocalDataSource(box);
      remote = _FakeAuthRemote();
    });

    tearDown(() async {
      await box.close();
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    AuthRepository buildRepo({String account = 'A'}) => AuthRepository(
      localDataSource: local,
      remoteDataSource: remote,
      deviceProfileRepo: const DeviceProfileRepository(),
      account: account,
    );

    test('TGC 有效 → 直接返回它，且只探一次 CAS', () async {
      await local.saveTgc('A', 'tgc-alive');
      final repo = buildRepo();

      final result = await repo.ensureTgcFor(ehallCasLoginUrl);

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => ''), 'tgc-alive');
      expect(remote.redirectCalls, 1);
      expect(remote.casUrls.single, ehallCasLoginUrl);
    });

    test('TGC 过期 → 静默重登一次，返回**新**票（不是旧票）', () async {
      await local.saveTgc('A', 'tgc-dead');
      await local.saveCachedCredentials('A', 'pw-A');
      final repo = buildRepo();
      await repo.prepareLogin();
      remote.expireCalls = 1;

      final result = await repo.ensureTgcFor(ehallCasLoginUrl);

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => ''), 'tgc-fresh', reason: '必须是重登后的新票');
      expect(remote.redirectCalls, 2, reason: '过期一次 → 重登 → 重试一次');
      expect(local.getTgc('A'), 'tgc-fresh', reason: '新票要按账号落盘');
    });

    test('本来就没 TGC → Left（不抛异常）', () async {
      final repo = buildRepo();
      final result = await repo.ensureTgcFor(ehallCasLoginUrl);
      expect(result.isLeft(), isTrue);
      expect(remote.redirectCalls, 0, reason: '没票就不该发请求');
    });

    test('TGC 一直过期 → Left，不把异常抛给页面', () async {
      await local.saveTgc('A', 'tgc-dead');
      await local.saveCachedCredentials('A', 'pw-A');
      final repo = buildRepo();
      await repo.prepareLogin();
      remote.expireCalls = 99;

      final result = await repo.ensureTgcFor(ehallCasLoginUrl);

      expect(result.isLeft(), isTrue);
      expect(result.fold((f) => f.message, (_) => ''), contains('统一登录已失效'));
    });

    test('返回的是 TGC 本身，不是换回来的回调地址', () async {
      await local.saveTgc('A', 'tgc-alive');
      final repo = buildRepo();
      final tgc = (await repo.ensureTgcFor(ehallCasLoginUrl)).getOrElse(
        () => '',
      );
      expect(tgc, 'tgc-alive');
      expect(tgc, isNot(contains('loginSuccess')));
      expect(tgc, isNot(contains('ticket')));
    });
  });

  group('EhallScreen 三态', () {
    /// ⚠ **每个用例都必须把内嵌页替掉**：`InAppWebView` 在 widget 测试里建不出来
    /// —— `InAppWebViewPlatform.instance` 从未被设置过，一 build 就断言失败
    /// （`A platform implementation for flutter_inappwebview has not been set`）。
    /// 这正是 `webViewScreenBuilderProvider` 这个缝存在的理由。
    List<Override> stubs({
      required List<EmbeddedWebRequest> seen,
      List<Uri>? opened,
    }) => <Override>[
      webViewScreenBuilderProvider.overrideWithValue((request) {
        seen.add(request);
        return const Scaffold(body: Text('内嵌页占位'));
      }),
      if (opened != null)
        externalUrlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
    ];

    Future<void> pump(WidgetTester tester, List<Override> overrides) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(home: EhallScreen()),
        ),
      );
    }

    testWidgets('加载态说清在等什么，拿到请求后交给内嵌页', (tester) async {
      final completer = Completer<EmbeddedWebRequest>();
      final seen = <EmbeddedWebRequest>[];
      await pump(tester, [
        ...stubs(seen: seen),
        ehallWebSessionProvider.overrideWith((ref) => completer.future),
      ]);
      await tester.pump();

      expect(find.text('智慧江财'), findsOneWidget);
      expect(find.text('正在把统一认证登录态交给内嵌浏览器…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(seen, isEmpty, reason: '还没解析出请求就不该建内嵌页');

      completer.complete(
        const EmbeddedWebRequest(title: '智慧江财', url: ehallLoginEntryUrl),
      );
      await tester.pumpAndSettle();

      expect(find.text('内嵌页占位'), findsOneWidget);
      expect(seen.single.url, ehallLoginEntryUrl);
    });

    testWidgets('错误态：给人话 + 重试 + 用系统浏览器打开的出路', (tester) async {
      final opened = <Uri>[];
      await pump(tester, [
        ...stubs(seen: <EmbeddedWebRequest>[], opened: opened),
        ehallWebSessionProvider.overrideWith(
          (ref) => throw const EhallSessionException('统一认证登录态不可用：TGC 已过期'),
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('智慧江财打不开'), findsOneWidget);
      // 文案来自 `AppErrorState` → `friendlyErrorText`：不带 `Exception: ` 前缀。
      expect(find.text('统一认证登录态不可用：TGC 已过期'), findsOneWidget);
      expect(find.byKey(const Key('ehallSessionRetry')), findsOneWidget);

      await tester.tap(find.byTooltip('用系统浏览器打开'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), ehallPortalUrl);
    });

    testWidgets('数据态：把带 TGC 的请求交给内嵌页（不跳系统浏览器）', (tester) async {
      final seen = <EmbeddedWebRequest>[];
      final opened = <Uri>[];
      await pump(tester, [
        // 真 WebView 在 widget 测试里建不出来（需要平台实现）→ 用缝替换掉，
        // 顺便断言「交给内嵌页的到底是哪个 URL、带了哪些 Cookie」。
        ...stubs(seen: seen, opened: opened),
        ehallWebSessionProvider.overrideWith(
          (ref) async => EmbeddedWebRequest(
            title: '智慧江财',
            url: ehallLoginEntryUrl,
            cookies: [casTgcCookie('TGT-probe')],
          ),
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('内嵌页占位'), findsOneWidget);
      expect(opened, isEmpty, reason: '有登录态就该内嵌，不该跳浏览器');
      expect(seen.single.url, ehallLoginEntryUrl);
      expect(seen.single.cookies.single.name, 'TGC');
      expect(seen.single.cookies.single.domain, kCasHost);
      expect(seen.single.cookies.single.value, 'TGT-probe');
    });
  });

  group('源码守卫', () {
    test('智慧江财走内嵌（不是跳系统浏览器）', () {
      final source = File(
        'lib/features/ehall/presentation/ehall_screen.dart',
      ).readAsStringSync();
      expect(source.contains('webViewScreenBuilderProvider'), isTrue);
      expect(
        source.contains('launchUrl('),
        isFalse,
        reason: '跳系统浏览器就没有登录态了 —— 那正是这个功能要解决的问题',
      );
    });

    test('解析登录态的 provider 不打印任何凭据', () {
      final source = File(
        'lib/features/ehall/data/providers/ehall_session_provider.dart',
      ).readAsStringSync();
      expect(source.contains('ensureTgcFor'), isTrue);
      expect(source.contains('debugPrint'), isFalse);
      expect(source.contains('print('), isFalse);
    });

    test('内嵌页只打 Cookie 的**名字**，不打值', () {
      final source = File(
        'lib/core/web/in_app_web_screen.dart',
      ).readAsStringSync();
      // `$cookies` 走的是 WebSessionCookie.toString()（只报名字与域）；
      // 直接打 value 的写法必须为零。
      expect(source.contains(r'$c.value'), isFalse);
      expect(source.contains(r'${c.value}'), isFalse);
    });
  });
}
