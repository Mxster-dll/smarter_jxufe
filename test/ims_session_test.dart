import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';
import 'package:smarter_jxufe/features/ims/auth/data/datasource/ims_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_session.dart';

/// **全局唯一 IMS 会话**的守卫测试。
///
/// 背景（用户 2026-09-11 反馈）：培养方案 / 课表 / 成绩 / 毕业学分 / 我的
/// 五个页面以前每次进入都无条件重走一遍完整 CAS 换票，CAS 侧一失败就永远停在
/// 「加载中…」——即「强制重新登录」。本文件锁住新口径：
/// 1. 本地有会话 ⇒ 进页面**零网络请求**；
/// 2. 会话真失效 ⇒ 换票只发生一次（并发去重），成功后落盘；
/// 3. 重启应用 / 切号回来 ⇒ 会话仍在（release 只清内存、不动磁盘）；
/// 4. 会话与个人缓存**按账号隔离**，切号不串号、旧数据只被认领一次。

/// 内存版会话存储（真实实现见 [ImsAuthLocalDataSource]）。
class _FakeStore implements ImsSessionStore {
  _FakeStore([Map<String, String>? initial]) : data = {...?initial};

  final Map<String, String> data;
  int readCount = 0;
  int migrateCount = 0;
  int forgetCount = 0;
  bool failWrite = false;

  @override
  Future<String?> read(String account) async {
    readCount++;
    return data[account];
  }

  @override
  Future<void> write(String account, String jsessionId) async {
    if (failWrite) throw StateError('磁盘写失败');
    data[account] = jsessionId;
  }

  @override
  Future<String?> migrateLegacy(String account) async {
    migrateCount++;
    return null;
  }

  @override
  Future<void> forget(String account) async {
    forgetCount++;
    data.remove(account);
  }
}

/// 记录请求并按脚本作答的 Dio 适配器（不打真实网络）。
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter();

  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add(options);
    // 取票接口：教务用 Set-Cookie 下发新 JSESSIONID。
    if (options.path.contains('jxcjcaslogin')) {
      return ResponseBody.fromString(
        '',
        200,
        headers: {
          'set-cookie': ['JSESSIONID=FRESH-1; Path=/'],
        },
      );
    }
    // 激活接口（CAS 回跳地址）。
    return ResponseBody.fromString('ok', 200);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_ScriptedAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://jwxt.jxufe.edu.cn', validateStatus: (_) => true))
      ..httpClientAdapter = adapter;

void main() {
  group('ImsSession · 进页面不再强制重新登录', () {
    test('本地已有会话 ⇒ ensureReady 零网络请求', () async {
      final store = _FakeStore({'2025001': 'CACHED'});
      final adapter = _ScriptedAdapter();
      var resolveCount = 0;
      final session = ImsSession(
        account: '2025001',
        dio: _dio(adapter),
        store: store,
        resolveRedirect: () async {
          resolveCount++;
          return (url: 'https://ssl.jxufe.edu.cn/cas', gid: 'g');
        },
      );

      expect(await session.ensureReady(), 'CACHED');
      expect(resolveCount, 0, reason: '有会话时不得换票');
      expect(adapter.calls, isEmpty, reason: '有会话时不得发任何请求');
      expect(session.phase, ImsSessionPhase.ready);
    });

    test('本地没有会话 ⇒ 换票一次：取票 + 激活，并落盘', () async {
      final store = _FakeStore();
      final adapter = _ScriptedAdapter();
      final session = ImsSession(
        account: '2025001',
        dio: _dio(adapter),
        store: store,
        resolveRedirect: () async =>
            (url: 'https://ssl.jxufe.edu.cn/cas/login?service=x', gid: 'gid-1'),
      );

      expect(await session.ensureReady(), 'FRESH-1');
      expect(session.phase, ImsSessionPhase.ready);
      expect(store.data['2025001'], 'FRESH-1', reason: '会话要落盘');

      expect(adapter.calls.length, 2);
      expect(adapter.calls[0].path, contains('jxcjcaslogin'));
      // 第二步必须带着新票访问 CAS 回跳地址，否则教务侧仍视为未登录。
      expect(adapter.calls[1].headers['Cookie'], 'JSESSIONID=FRESH-1');
    });

    test('并发调用只换一次票（多个请求同时踩到凭证失效）', () async {
      final store = _FakeStore();
      final adapter = _ScriptedAdapter();
      final gate = Completer<void>();
      var resolveCount = 0;
      final session = ImsSession(
        account: '2025001',
        dio: _dio(adapter),
        store: store,
        resolveRedirect: () async {
          resolveCount++;
          await gate.future;
          return (url: 'https://ssl.jxufe.edu.cn/cas', gid: 'g');
        },
      );

      final first = session.ensureReady();
      final second = session.ensureReady();
      gate.complete();
      expect(await Future.wait([first, second]), ['FRESH-1', 'FRESH-1']);
      expect(resolveCount, 1, reason: '换票必须去重');
      expect(adapter.calls.length, 2, reason: '两次调用共用同一次换票');
    });

    test('换票失败 ⇒ 报错且不落盘，之后可重试成功', () async {
      final store = _FakeStore();
      final adapter = _ScriptedAdapter();
      var fail = true;
      final session = ImsSession(
        account: '2025001',
        dio: _dio(adapter),
        store: store,
        resolveRedirect: () async {
          if (fail) throw Exception('CAS 不可达');
          return (url: 'https://ssl.jxufe.edu.cn/cas', gid: 'g');
        },
      );

      await expectLater(session.ensureReady(), throwsA(isA<Exception>()));
      expect(session.phase, ImsSessionPhase.failed);
      expect(store.data, isEmpty, reason: '失败不得写入假会话');

      fail = false;
      expect(await session.ensureReady(), 'FRESH-1', reason: '失败后必须能重试');
      expect(session.phase, ImsSessionPhase.ready);
    });

    test('落盘失败不影响本次运行', () async {
      final store = _FakeStore()..failWrite = true;
      final session = ImsSession(
        account: '2025001',
        dio: _dio(_ScriptedAdapter()),
        store: store,
        resolveRedirect: () async =>
            (url: 'https://ssl.jxufe.edu.cn/cas', gid: 'g'),
      );

      expect(await session.ensureReady(), 'FRESH-1');
      expect(session.jsessionId, 'FRESH-1');
    });
  });

  group('ImsSession · 重启与切号', () {
    test('release（provider dispose）只清内存，磁盘会话仍可恢复', () async {
      final store = _FakeStore({'2025001': 'CACHED'});
      final adapter = _ScriptedAdapter();
      final session = ImsSession(
        account: '2025001',
        dio: _dio(adapter),
        store: store,
        resolveRedirect: () async =>
            (url: 'https://ssl.jxufe.edu.cn/cas', gid: 'g'),
      );

      await session.ensureReady();
      session.release();
      expect(session.hasSession, isFalse);
      expect(store.data['2025001'], 'CACHED', reason: 'release 不得动磁盘');

      // 模拟「重启应用」：同一份磁盘、全新实例。
      final restarted = ImsSession(
        account: '2025001',
        dio: _dio(adapter),
        store: store,
        resolveRedirect: () async => throw StateError('不该换票'),
      );
      expect(await restarted.ensureReady(), 'CACHED');
      expect(adapter.calls, isEmpty);
    });

    test('forget（退出登录）才清磁盘', () async {
      final store = _FakeStore({'2025001': 'CACHED'});
      final session = ImsSession(
        account: '2025001',
        dio: _dio(_ScriptedAdapter()),
        store: store,
        resolveRedirect: () async =>
            (url: 'https://ssl.jxufe.edu.cn/cas', gid: 'g'),
      );

      await session.ensureReady();
      await session.forget();
      expect(store.data, isEmpty);
      expect(store.forgetCount, 1);
    });

    test('切号：A 的会话不会被 B 复用（按账号取，取不到才换票）', () async {
      final store = _FakeStore({'A': 'SESSION-A'});
      final adapter = _ScriptedAdapter();
      var resolveCount = 0;
      final session = ImsSession(
        account: 'B',
        dio: _dio(adapter),
        store: store,
        resolveRedirect: () async {
          resolveCount++;
          return (url: 'https://ssl.jxufe.edu.cn/cas', gid: 'g');
        },
      );

      expect(await session.ensureReady(), 'FRESH-1');
      expect(resolveCount, 1, reason: 'B 无会话，必须换票而不是借用 A 的');
      expect(store.data['A'], 'SESSION-A', reason: '切号不得清掉 A 的会话');
      expect(store.data['B'], 'FRESH-1');
    });
  });

  group('ImsAuthLocalDataSource · 会话按账号隔离', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('ims_session_test');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('A 的会话读不到、也不影响 B', () async {
      final box = await Hive.openBox<String>('imsAuthScopedTest');
      final ds = ImsAuthLocalDataSource(box);

      await ds.write('A', 'session-A');
      expect(await ds.read('A'), 'session-A');
      expect(await ds.read('B'), isNull);
      expect(ds.issuedAt('A'), isNotNull);

      await ds.forget('A');
      expect(await ds.read('A'), isNull);
      expect(await ds.read('B'), isNull);
    });

    test('旧版无账号单键只被第一个账号认领一次', () async {
      final box = await Hive.openBox<String>('imsAuthLegacyTest');
      await box.put(ImsAuthLocalDataSource.legacyJsessionIdKey, 'legacy');

      final ds = ImsAuthLocalDataSource(box);
      expect(await ds.migrateLegacy('A'), 'legacy');
      expect(await ds.read('A'), 'legacy');
      expect(
        box.get(ImsAuthLocalDataSource.legacyJsessionIdKey),
        isNull,
        reason: '旧键必须删除，否则下一个账号也会认领',
      );

      expect(await ds.migrateLegacy('B'), isNull);
      expect(await ds.read('B'), isNull);
    });
  });

  group('个人数据 box 按账号隔离', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('account_box_test');
      Hive.init(tempDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('box 名：有账号用后缀，未确定账号用独立 __none', () {
      expect(accountScopedBoxName('gradesCache', '2025001'), 'gradesCache_2025001');
      expect(accountScopedBoxName('gradesCache', null), 'gradesCache__none');
      expect(accountScopedBoxName('gradesCache', '  '), 'gradesCache__none');
    });

    test('旧的无账号 box 只被第一个账号迁移认领', () async {
      final legacy = await Hive.openBox<String>('gradesCache');
      await legacy.put('grades|2025|all', '{"grades":[]}');

      final a = await openAccountScopedBox('gradesCache', 'A');
      expect(a.get('grades|2025|all'), isNotNull, reason: 'A 应继承旧数据');
      expect(legacy.get(claimedKey), 'A');

      final b = await openAccountScopedBox('gradesCache', 'B');
      expect(b.get('grades|2025|all'), isNull, reason: 'B 不得继承 A 的数据');

      final none = await openAccountScopedBox('gradesCache', null);
      expect(none.get('grades|2025|all'), isNull, reason: '未登录不得看到旧数据');
    });

    test('已有数据的账号 box 不会被旧数据再次覆盖', () async {
      final a = await openAccountScopedBox('gradesCache', 'A');
      await a.put('k', 'mine');

      final again = await openAccountScopedBox('gradesCache', 'A');
      expect(again.get('k'), 'mine');
    });
  });
}
