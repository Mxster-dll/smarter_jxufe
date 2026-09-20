// 守卫：CAS 把请求 302 打回登录页 ≠ 成功（TGC 已失效）。
//
// 背景（2026-09-19 用户报「主页课表卡片提示「课表获取失败」」）：`getRedirectImsUrl`
// 从前对**任何** Location 都当成功返回，而 CAS 在 TGC 过期时正是回
// `…/cas/login?service=…`（302 + Location）。后果链：
//   ① `AuthRepository.getImsRedirectInfo()` 收不到 `TgcExpiredException`
//      → 静默重登 `_relogin()` 永不触发；
//   ② `fetchAndActivateJsessionId` 拿到的只是**匿名** JSESSIONID（`/jxcjcaslogin`
//      自己也被 302 打回登录页），却在日志里打印 `[ImsSession] 换票成功`；
//   ③ 所有教务业务请求回 547 字节的「凭证已失效」alert 页 → 首页课表卡片红字。
// 实测（python + 真实会话）：TGC 有效时 CAS 回
// `https://jwxt.jxufe.edu.cn//jxcjcaslogin?ticket=ST-…`；无效时回 `/cas/login`。
//
// 本文件锁住三件事：判定函数语义、两个 CAS 入口的行为、以及别再退回旧写法。
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/core/network/cas_redirect.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';

/// 只回一个预置响应（含 Location 头）的适配器，不打网络。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.statusCode, this.location, this.body = ''});

  final int statusCode;
  final String? location;
  final String body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        if (location != null) 'location': [location!],
      },
    );
  }
}

Dio _dioWith(HttpClientAdapter adapter) =>
    Dio(BaseOptions(validateStatus: (status) => true, followRedirects: false))
      ..httpClientAdapter = adapter;

void main() {
  group('isCasLoginRedirect：打回登录页的判定', () {
    test('真实登录页 URL（带 service）判定为登录页', () {
      expect(
        isCasLoginRedirect(
          'https://ssl.jxufe.edu.cn/cas/login'
          '?service=https%3A%2F%2Fjwxt.jxufe.edu.cn%2F%2Fjxcjcaslogin',
        ),
        isTrue,
      );
    });

    test('裸登录页与相对路径同样判定为登录页', () {
      expect(isCasLoginRedirect('https://ssl.jxufe.edu.cn/cas/login'), isTrue);
      expect(isCasLoginRedirect('/cas/login?service=x'), isTrue);
    });

    test('带路径参数的登录页（真实形态 ;jsessionid=）也判定为登录页', () {
      expect(
        isCasLoginRedirect(
          'https://ssl.jxufe.edu.cn/cas/login;jsessionid=ABC123',
        ),
        isTrue,
      );
    });

    test('真实回调地址（带 ticket）不是登录页', () {
      expect(
        isCasLoginRedirect(
          'https://jwxt.jxufe.edu.cn//jxcjcaslogin'
          '?ticket=<REDACTED>',
        ),
        isFalse,
      );
    });

    test('同域但非登录页的路径（/cas/loginfo）不能被误判', () {
      expect(isCasLoginRedirect('https://ssl.jxufe.edu.cn/cas/loginfo'), isFalse);
      expect(isCasLoginRedirect('https://ssl.jxufe.edu.cn/login'), isFalse);
    });

    test('null / 空串不算登录页', () {
      expect(isCasLoginRedirect(null), isFalse);
      expect(isCasLoginRedirect(''), isFalse);
    });
  });

  group('getRedirectImsUrl：302 的两种去向', () {
    test('TGC 失效（打回登录页）→ 抛 TgcExpiredException，而不是当成功', () async {
      final dataSource = AuthRemoteDataSource(
        _dioWith(
          _FakeAdapter(
            statusCode: 302,
            location:
                'https://ssl.jxufe.edu.cn/cas/login'
                '?service=https%3A%2F%2Fjwxt.jxufe.edu.cn%2F%2Fjxcjcaslogin',
          ),
        ),
      );
      await expectLater(
        dataSource.getRedirectImsUrl('dead-tgc'),
        throwsA(isA<TgcExpiredException>()),
      );
    });

    test('TGC 有效（带 ticket 的回跳）→ 正常返回 URL 与 gid_', () async {
      final dataSource = AuthRemoteDataSource(
        _dioWith(
          _FakeAdapter(
            statusCode: 302,
            location:
                'https://jwxt.jxufe.edu.cn//jxcjcaslogin'
                '?ticket=<REDACTED>&gid_=GID123',
          ),
        ),
      );
      final (url, gid) = await dataSource.getRedirectImsUrl('alive-tgc');
      expect(url, contains('ticket=<REDACTED>'));
      expect(gid, 'GID123');
    });

    test('200 + 登录页 HTML 仍然照旧抛 TgcExpiredException（老路径不许丢）', () async {
      final dataSource = AuthRemoteDataSource(
        _dioWith(
          _FakeAdapter(statusCode: 200, body: '<!DOCTYPE html><html>登录</html>'),
        ),
      );
      await expectLater(
        dataSource.getRedirectImsUrl('dead-tgc'),
        throwsA(isA<TgcExpiredException>()),
      );
    });
  });

  group('源码守卫：口径唯一、不许退回旧写法', () {
    String read(String path) {
      final file = File(path);
      return file.existsSync() ? file.readAsStringSync() : '';
    }

    test('两个 CAS 入口都用共用的 isCasLoginRedirect', () {
      final source = read(
        'lib/features/auth/data/datasources/auth_remote_datasource.dart',
      );
      expect(
        source.contains(
          'if (isCasLoginRedirect(location)) throw TgcExpiredException(location);',
        ),
        isTrue,
        reason: 'getRedirectImsUrl 必须把「打回登录页」判为 TGC 过期',
      );
      expect(
        source.contains(
          'if (isCasLoginRedirect(resolved)) throw TgcExpiredException(resolved);',
        ),
        isTrue,
        reason: 'getCasRedirectUrl 不许在 CAS 域内白转 5 圈',
      );
      // 判据本体在 core（2026-09-20 收敛，ssp / read_credit 也共用它）；
      // 本文件只保证 auth 侧仍在用它，且没有内联回旧写法。
      expect(
        File('lib/core/network/cas_redirect.dart')
            .readAsStringSync()
            .contains('bool isCasLoginRedirect(String? url)'),
        isTrue,
      );
      expect(
        source.contains(
          "import 'package:smarter_jxufe/core/network/cas_redirect.dart';",
        ),
        isTrue,
      );
    });

    test('isTgcAlive 复用同一判定，且旧的内联 path 判断已删除', () {
      final source = read('lib/features/auth/data/auth_repository.dart');
      expect(source.contains('if (isCasLoginRedirect(url))'), isTrue);
      expect(
        source.contains("final path = Uri.tryParse(url)?.path ?? '';"),
        isFalse,
        reason: '内联判定已收口到 isCasLoginRedirect，别再抄一份',
      );
    });

    test('首页课表卡走缓存仓库（失败降级），不再直接打在线仓库', () {
      // 2026-09-20：provider 已下沉到 data 层（panel 只留 refreshDashboard 编排）。
      final source = read(
        'lib/features/home/data/providers/dashboard_providers.dart',
      );
      // provider 是 data 文件里的最后一件（2026-09-20 从 panel 下沉）。
      final provider = source.substring(
        source.indexOf('final dashboardTodayCoursesProvider'),
      );
      expect(provider.contains('scheduleCacheRepositoryProvider.future'), isTrue);
      expect(provider.contains('refresh: true'), isTrue);
      expect(provider.contains('cached.entries'), isTrue);
      expect(
        provider.contains('scheduleRepositoryProvider'),
        isFalse,
        reason: '在线仓库一次失败就会把红字摊在首页，改走缓存仓库的降级路径',
      );
    });
  });
}
