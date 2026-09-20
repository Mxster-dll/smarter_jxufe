/// 统一认证换证循环（`lib/core/network/cas_walk.dart`）行为守卫 —— 2026-09-20 立（架构审查 ②）。
///
/// 三件事：① **循环机制本身**（跟跳 / Cookie 归属 / trace / 跳数上限 / 提前收工）；
/// ② 阅读学分链**此前零守卫**，这里补上（它是最简单的那族：跟完跳判 Cookie）；
/// ③ 畅想之星链的三种取 token 姿势（回跳地址 / Set-Cookie / 正文）迁到钩子后行为不变。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/core/network/cas_walk.dart';
import 'package:smarter_jxufe/core/network/cookie_jar.dart';
import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/read_credit/data/datasources/read_credit_auth_remote_datasource.dart';

/// 合法形态的个人 JWT 假值（三段 base64url，`eyJ` 开头）。
const String _jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcdefghij';

Dio _dioWith(_Adapter adapter) => Dio()..httpClientAdapter = adapter;

void main() {
  group('换证循环机制', () {
    test('跟 3xx Location 逐跳，Cookie 按 host 归属（谁下发的只发给谁）', () async {
      final adapter = _Adapter([
        _Route(
          (u) => u.startsWith('https://a.example.com/start'),
          status: 302,
          location: 'https://a.example.com/next',
          setCookie: ['uid=202502513; Path=/'],
        ),
        _Route(
          (u) => u.startsWith('https://a.example.com/next'),
          status: 302,
          location: 'https://b.example.com/final',
          setCookie: ['aonly=2; Path=/'],
        ),
        _Route((u) => u.startsWith('https://b.example.com/'), body: 'done'),
      ]);
      final jar = HostCookieJar();
      final outcome = await walkCasRedirects<String>(
        startUrl: 'https://a.example.com/start',
        jar: jar,
        send: casDioSender(_dioWith(adapter)),
        afterResponse: (step) =>
            step.hasLocation ? null : CasHopFinish('ok'),
      );

      expect(outcome.result, 'ok');
      expect(outcome.hops, 3);
      expect(outcome.exhausted, isFalse);
      expect(outcome.finalUrl, 'https://b.example.com/final');
      // 第 2 跳仍在 a 域：必须把 a 域自己下发的 uid 带回去。
      expect(adapter.cookieOf('a.example.com'), contains('uid=202502513'));
      // 第 3 跳到 b 域：a 域的 Cookie **不许**跨域外泄。
      expect(
        adapter.cookieOf('b.example.com'),
        isNot(contains('uid=202502513')),
      );
      expect(adapter.cookieOf('b.example.com'), isNot(contains('aonly')));
      // 会话罐里三个域各自独立记账。
      expect(jar.headerFor('a.example.com'), contains('aonly=2'));
    });

    test('没有 Location = 自然收工：result 为 null，但最后一跳的状态码还在', () async {
      final adapter = _Adapter([
        _Route((u) => u.startsWith('https://x.example.com/'), body: '没登进去'),
      ]);
      final outcome = await walkCasRedirects<String>(
        startUrl: 'https://x.example.com/',
        jar: HostCookieJar(),
        send: casDioSender(_dioWith(adapter)),
        afterResponse: (step) => null,
      );

      expect(outcome.result, isNull);
      expect(outcome.exhausted, isFalse);
      expect(outcome.lastStatusCode, 200, reason: '错误文案要用它（`（得到 […] HTTP 200）`）');
      expect(outcome.last?.bodyText, '没登进去');
    });

    test('beforeRequest 命中 = 这一跳的请求根本不发', () async {
      final adapter = _Adapter([]);
      final outcome = await walkCasRedirects<String>(
        startUrl: 'https://x.example.com/?token=$_jwt',
        jar: HostCookieJar(),
        send: casDioSender(_dioWith(adapter)),
        beforeRequest: (step) =>
            step.url.contains('token=') ? CasHopFinish(_jwt) : null,
      );

      expect(outcome.result, _jwt);
      expect(adapter.calls, isEmpty);
      expect(outcome.hops, 0);
    });

    test('afterResponse 命中 = 立刻收工，不再跟 Location', () async {
      final adapter = _Adapter([
        _Route(
          (u) => u.startsWith('https://x.example.com/'),
          status: 302,
          location: 'https://y.example.com/next',
        ),
      ]);
      final outcome = await walkCasRedirects<String>(
        startUrl: 'https://x.example.com/',
        jar: HostCookieJar(),
        send: casDioSender(_dioWith(adapter)),
        afterResponse: (step) => CasHopFinish('early'),
      );

      expect(outcome.result, 'early');
      expect(outcome.hops, 1);
      expect(adapter.calls.length, 1, reason: '拿到东西就不该再跳');
    });

    test('撞上跳数上限 = exhausted（与「链路自然结束」分开报）', () async {
      // 自己 302 到自己：成环。
      final adapter = _Adapter([
        _Route(
          (u) => u.startsWith('https://loop.example.com/'),
          status: 302,
          location: 'https://loop.example.com/again',
        ),
      ]);
      final outcome = await walkCasRedirects<String>(
        startUrl: 'https://loop.example.com/',
        jar: HostCookieJar(),
        send: casDioSender(_dioWith(adapter)),
        spec: const CasWalkSpec(maxHops: 4),
        afterResponse: (step) => null,
      );

      expect(outcome.result, isNull);
      expect(outcome.exhausted, isTrue);
      expect(outcome.hops, 4);
      expect(adapter.calls.length, 4);
    });

    test('trace 逐跳追加，且**只打 Set-Cookie 的名字**（值就是凭据）', () async {
      final adapter = _Adapter([
        _Route(
          (u) => u.startsWith('https://x.example.com/'),
          status: 302,
          location: 'https://y.example.com/final',
          setCookie: ['uid=202502513; Path=/', 'token=SECRETTOKEN; Path=/'],
        ),
        _Route((u) => u.startsWith('https://y.example.com/'), body: 'ok'),
      ]);
      final trace = <String>[];
      await walkCasRedirects<String>(
        startUrl: 'https://x.example.com/',
        jar: HostCookieJar(),
        send: casDioSender(_dioWith(adapter)),
        trace: trace,
        afterResponse: (step) =>
            step.hasLocation ? null : CasHopFinish('ok'),
      );

      expect(trace.length, 2);
      expect(trace.first, startsWith('跳[0] 302 https://x.example.com/'));
      expect(trace.first, contains('-> https://y.example.com/final'));
      expect(trace.first, contains('Set-Cookie(x.example.com): uid,token'));
      expect(
        trace.join('\n'),
        isNot(contains('SECRETTOKEN')),
        reason: 'trace 进日志/工单，Cookie 值绝不能出现',
      );
    });

    test('casDioSender：默认 Referer 是 `https://<host>/`，可切成当前完整 URL', () async {
      final adapter = _Adapter([
        _Route((u) => u.startsWith('https://x.example.com/'), body: 'ok'),
      ]);
      final dio = _dioWith(adapter);
      await casDioSender(dio)('https://x.example.com/a?b=1', 'k=v');
      expect(adapter.calls.last.headers['Referer'], 'https://x.example.com/');
      expect(adapter.calls.last.headers['Cookie'], 'k=v');
      expect(adapter.calls.last.followRedirects, isFalse);
      expect(adapter.calls.last.validateStatus(500), isTrue);

      await casDioSender(dio, refererIsCurrentUrl: true)(
        'https://x.example.com/a?b=1',
        '',
      );
      expect(
        adapter.calls.last.headers['Referer'],
        'https://x.example.com/a?b=1',
        reason: '入馆教育平台实测要求 Referer 是当前 URL',
      );
      expect(adapter.calls.last.headers.containsKey('Cookie'), isFalse);
    });
  });

  group('阅读学分链（迁移到 walker 后的行为守卫）', () {
    test('走完换证链 → 返回平台域 Cookie 串（uid + token 都在）', () async {
      final adapter = _Adapter([
        _Route(
          (u) => u.contains('ssl.jxufe.edu.cn/cas/login'),
          status: 302,
          location: 'http://jhread.zhixinst.com/Web/CASLogin/Login?ticket=ST-1',
        ),
        _Route(
          (u) => u.contains('/Web/CASLogin/Login'),
          status: 302,
          location: 'https://jhread.zhixinst.com:443/Web/ReadMain/Index',
          setCookie: [
            'ASP.NET_SessionId=abc; path=/',
            'uid=202502513; path=/',
            'token=tok123; path=/',
          ],
        ),
        _Route((u) => u.contains('/Web/ReadMain/Index'), body: '<html>ok</html>'),
      ]);
      final ds = ReadCreditAuthRemoteDataSource(_dioWith(adapter));
      final session = await ds.establishSession(
        'https://ssl.jxufe.edu.cn/cas/login?ticket=ST-1',
      );

      expect(session, contains('uid=202502513'));
      expect(session, contains('token=tok123'));
      expect(adapter.calls.length, 3);
      expect(
        adapter.cookieOf('jhread.zhixinst.com'),
        contains('uid=202502513'),
        reason: '第 3 跳必须把平台域自己下发的 Cookie 带回去',
      );
    });

    test('链路走完却没有 uid/token → 抛会话失效，文案带最后状态码', () async {
      final adapter = _Adapter([
        _Route(
          (u) => u.contains('ssl.jxufe.edu.cn/cas/login'),
          status: 302,
          location: 'http://jhread.zhixinst.com/Web/CASLogin/Login?ticket=ST-1',
        ),
        _Route(
          (u) => u.contains('/Web/CASLogin/Login'),
          status: 302,
          location: 'https://jhread.zhixinst.com/Web/ReadMain/Index',
        ),
        _Route((u) => u.contains('/Web/ReadMain/Index'), body: '请登录'),
      ]);
      final ds = ReadCreditAuthRemoteDataSource(_dioWith(adapter));

      await expectLater(
        ds.establishSession('https://ssl.jxufe.edu.cn/cas/login?ticket=ST-1'),
        throwsA(
          isA<ReadCreditSessionExpiredException>().having(
            (e) => e.message,
            'message',
            allOf(contains('未取得平台会话 Cookie'), contains('HTTP 200')),
          ),
        ),
      );
    });

    test('成环（一直 302）→ 「重定向次数过多」，且恰好请求 12 次', () async {
      final adapter = _Adapter([
        _Route(
          (u) => u.contains('ssl.jxufe.edu.cn'),
          status: 302,
          location: 'https://ssl.jxufe.edu.cn/cas/login?ticket=ST-1',
        ),
      ]);
      final ds = ReadCreditAuthRemoteDataSource(_dioWith(adapter));

      await expectLater(
        ds.establishSession('https://ssl.jxufe.edu.cn/cas/login?ticket=ST-1'),
        throwsA(
          isA<ReadCreditSessionExpiredException>().having(
            (e) => e.message,
            'message',
            contains('重定向次数过多'),
          ),
        ),
      );
      expect(adapter.calls.length, 12, reason: '跳数上限 = 12（迁移前口径）');
    });
  });

  group('畅想之星链（三种取 token 姿势迁到钩子后行为不变）', () {
    test('① 回跳地址本身带 JWT → 一个请求都不发', () async {
      final adapter = _Adapter([]);
      final ds = CxstarAuthRemoteDataSource(_dioWith(adapter));
      final token = await ds.establishSession(
        'https://ua.cxstar.com/uniauth/outLogin/login517?token=$_jwt',
      );

      expect(token, _jwt);
      expect(adapter.calls, isEmpty);
    });

    test('② Set-Cookie 里带 mtoken → 该跳之后就收工', () async {
      final adapter = _Adapter([
        _Route(
          (u) => u.startsWith('https://ua.cxstar.com/'),
          status: 302,
          location: 'https://m.cxstar.com/',
          setCookie: ['mtoken=$_jwt; Path=/'],
        ),
      ]);
      final ds = CxstarAuthRemoteDataSource(_dioWith(adapter));
      final token = await ds.establishSession(
        'https://ua.cxstar.com/uniauth/outLogin/login517',
      );

      expect(token, _jwt);
      expect(adapter.calls.length, 1);
    });

    test('③ 正文里带 JWT（非 SPA 壳）→ 也能取到', () async {
      final adapter = _Adapter([
        _Route(
          (u) => u.startsWith('https://ua.cxstar.com/'),
          status: 302,
          location: 'https://m.cxstar.com/home',
        ),
        _Route(
          (u) => u.startsWith('https://m.cxstar.com/'),
          body: '{"code":0,"data":{"token":"$_jwt"}}',
          contentType: 'application/json; charset=utf-8',
        ),
      ]);
      final ds = CxstarAuthRemoteDataSource(_dioWith(adapter));
      final trace = <String>[];
      final token = await ds.establishSession(
        'https://ua.cxstar.com/uniauth/outLogin/login517',
        trace: trace,
      );

      expect(token, _jwt);
      expect(trace.join('\n'), contains('取得个人 token（正文'));
      expect(
        trace.join('\n'),
        isNot(contains(_jwt)),
        reason: 'trace 里 token 必须打码',
      );
    });

    test('三种姿势都没命中 → 抛会话建立失败，文案含最后 host / 状态码 / Cookie 名', () async {
      final adapter = _Adapter([
        _Route(
          (u) => u.startsWith('https://ua.cxstar.com/'),
          body: '请登录',
          setCookie: ['JSESSIONID=abc; Path=/'],
        ),
      ]);
      final ds = CxstarAuthRemoteDataSource(_dioWith(adapter));

      await expectLater(
        ds.establishSession('https://ua.cxstar.com/uniauth/outLogin/login517'),
        throwsA(
          isA<CxstarSessionException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('未取得个人 token'),
              contains('最后停在 ua.cxstar.com'),
              contains('HTTP 200'),
              contains('JSESSIONID'),
            ),
          ),
        ),
      );
    });
  });
}

/// 一条假路由（URL 含它就命中）。
class _Route {
  const _Route(
    this.match, {
    this.body = '',
    this.status = 200,
    this.contentType = 'text/html; charset=utf-8',
    this.setCookie,
    this.location,
  });

  final bool Function(String url) match;
  final String body;
  final int status;
  final String contentType;
  final List<String>? setCookie;
  final String? location;
}

/// 记录请求并按 URL 分发的假适配器（仓库既有口径：每个测试文件内私有）。
class _Adapter implements HttpClientAdapter {
  _Adapter(this.routes);

  final List<_Route> routes;
  final List<RequestOptions> calls = <RequestOptions>[];

  /// 某个 host 最近一次请求实际带上的 Cookie 头（断言 Cookie 归属用）。
  String cookieOf(String host) {
    for (final call in calls.reversed) {
      if (call.uri.host == host) {
        return call.headers['Cookie']?.toString() ?? '';
      }
    }
    return '';
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    final url = options.uri.toString();
    for (final route in routes) {
      if (!route.match(url)) continue;
      return ResponseBody.fromString(
        route.status >= 300 && route.status < 400 ? '' : route.body,
        route.status,
        headers: {
          Headers.contentTypeHeader: [route.contentType],
          if (route.setCookie != null) 'set-cookie': route.setCookie!,
          if (route.location != null) 'location': [route.location!],
        },
      );
    }
    return ResponseBody.fromString('not routed: $url', 404, headers: {
      Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
    });
  }

  @override
  void close({bool force = false}) {}
}
