import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository.dart';
import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';

/// 统一登录（CAS）**按账号持久化**守卫。
///
/// 用户诉求（原话）：「统一登录也要像上面说的一样，持久化，相当于对于每个
/// 账号，统一登录和 ims 都只有一个入口」+ 拍板：「TGC 有效就直接用，
/// 免密码免 MFA；TGC 失效才用保存的密码静默重登」。
///
/// 历史 bug：`auth` box 用无账号单键 `tgc` / `cachedUser` / `cachedPass`，
/// 第二个账号一登录就把前一个账号的 TGC 冲掉 → 切回来必须重新登录
/// （还可能重新弹 MFA）。本文件锁死新的按账号口径。
class _FakeRemoteDataSource extends AuthRemoteDataSource {
  _FakeRemoteDataSource() : super(Dio());

  /// 剩余「TGC 已过期」次数（每次调用递减）：
  /// `1` = 模拟「重登后新票可用」，`999` = 永远过期。
  int expireCalls = 0;

  /// true = 网络异常（普通异常，不是 TgcExpiredException）。
  bool throwNetwork = false;

  /// true = CAS 把请求 302 打回登录页（`/cas/login;jsessionid=…`）。
  ///
  /// 这是**真实的假阳性陷阱**：`getRedirectImsUrl` 对任何 Location 都算成功，
  /// 于是「会话已失效」会被误判成「TGC 有效」→ 拿死票免登录。
  bool loginPageRedirect = false;

  /// [getRedirectImsUrl] 被调用次数 —— 「零请求」断言用。
  int redirectCalls = 0;

  /// 每次提交登录收到的 trustAgent。
  final List<String> loginTrustAgents = <String>[];

  /// 服务端是否要求 MFA。
  bool needMfa = false;

  /// 登录响应形态：302 + Set-Cookie（默认）或 200 + 正文「登录成功」（MFA 后）。
  int loginStatusCode = 302;

  /// 200 分支是否也带 `Set-Cookie: TGC=…`（真实 CAS 视部署而定，两种都要能处理）。
  bool login200SetsCookie = true;

  /// 302 分支是否带 `Set-Cookie: TGC=…`（false = 服务端异常，应判登录失败）。
  bool login302SetsCookie = true;

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
      'data': {'need': needMfa, 'state': 'mfa-state-1'},
    },
  );

  @override
  Future<(String, String?)> getRedirectImsUrl(String tgc) async {
    redirectCalls++;
    if (throwNetwork) throw Exception('network down');
    if (loginPageRedirect) {
      return (
        'https://ssl.jxufe.edu.cn/cas/login;jsessionid=ABC123'
            '?service=https%3A%2F%2Fjwxt.jxufe.edu.cn%2F%2Fjxcjcaslogin',
        null,
      );
    }
    if (expireCalls > 0) {
      expireCalls--;
      throw TgcExpiredException('expired');
    }
    return ('https://jwxt.jxufe.edu.cn/jxcjcaslogin?ticket=ST-$tgc', 'gid-1');
  }

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
  }) async {
    loginTrustAgents.add(trustAgent);
    if (loginStatusCode == 200) {
      return Response<dynamic>(
        requestOptions: RequestOptions(path: '/cas/login'),
        statusCode: 200,
        data: '登录成功',
        headers: Headers.fromMap({
          if (login200SetsCookie)
            'set-cookie': ['TGC=tgc-mfa; Path=/; HttpOnly'],
        }),
      );
    }
    return Response<dynamic>(
      requestOptions: RequestOptions(path: '/cas/login'),
      statusCode: 302,
      headers: Headers.fromMap({
        if (login302SetsCookie) 'set-cookie': ['TGC=tgc-new; Path=/; HttpOnly'],
      }),
    );
  }
}

void main() {
  late Directory tempDir;
  late Box<String> box;
  late _FakeRemoteDataSource remote;
  late AuthLocalDataSource local;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('auth_session_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('authSessionTest');
    local = AuthLocalDataSource(box);
    remote = _FakeRemoteDataSource();
  });

  tearDown(() async {
    await box.close();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  AuthRepository buildRepo({String account = ''}) => AuthRepository(
    localDataSource: local,
    remoteDataSource: remote,
    deviceProfileRepo: const DeviceProfileRepository(),
    account: account,
  );

  group('AuthLocalDataSource · 按账号持久化', () {
    test('TGC 按账号隔离：删除一个不影响另一个', () async {
      await local.saveTgc('A', 'tgc-A');
      await local.saveTgc('B', 'tgc-B');

      expect(local.getTgc('A'), 'tgc-A');
      expect(local.getTgc('B'), 'tgc-B');

      await local.deleteTgc('A');
      expect(local.getTgc('A'), isNull);
      expect(local.getTgc('B'), 'tgc-B', reason: '切号/退出不应波及其它账号');
    });

    test('缓存凭据按账号隔离', () async {
      await local.saveCachedCredentials('A', 'pw-A');
      await local.saveCachedCredentials('B', 'pw-B');

      expect(local.getCachedCredentials('A'), ('A', 'pw-A'));
      expect(local.getCachedCredentials('B'), ('B', 'pw-B'));
    });

    test('空账号不读也不写任何键', () async {
      expect(local.getTgc(''), isNull);
      expect(local.getCachedCredentials(''), (null, null));
      await local.claimLegacyCredentials('');
      expect(box.keys, isEmpty);
    });
  });

  group('AuthLocalDataSource · 旧单键认领', () {
    test('认领给 cachedUser 记着的那个账号，并清掉旧键', () async {
      await box.put(AuthLocalDataSource.legacyTgcKey, 'tgc-legacy');
      await box.put(AuthLocalDataSource.legacyCachedUserKey, 'A');
      await box.put(AuthLocalDataSource.legacyCachedPassKey, 'pw-legacy');

      await local.claimLegacyCredentials('A');

      expect(local.getTgc('A'), 'tgc-legacy');
      expect(local.getCachedCredentials('A'), ('A', 'pw-legacy'));
      // 旧键必须消失：否则下一个账号会再认领一次同一份 TGC。
      expect(box.get(AuthLocalDataSource.legacyTgcKey), isNull);
      expect(box.get(AuthLocalDataSource.legacyCachedUserKey), isNull);
      expect(box.get(AuthLocalDataSource.legacyCachedPassKey), isNull);
    });

    test('认领幂等：再来一次不报错也不清掉已认领的值', () async {
      await box.put(AuthLocalDataSource.legacyCachedUserKey, 'A');
      await box.put(AuthLocalDataSource.legacyCachedPassKey, 'pw-legacy');
      await local.claimLegacyCredentials('A');
      await local.claimLegacyCredentials('A');

      expect(local.getCachedCredentials('A'), ('A', 'pw-legacy'));
    });

    test('账号不匹配 → 不认领，旧数据原样留存给它的主人', () async {
      await box.put(AuthLocalDataSource.legacyTgcKey, 'tgc-legacy');
      await box.put(AuthLocalDataSource.legacyCachedUserKey, 'A');
      await box.put(AuthLocalDataSource.legacyCachedPassKey, 'pw-legacy');

      await local.claimLegacyCredentials('B');

      expect(local.getTgc('B'), isNull, reason: '不能把 A 的 TGC 算到 B 头上');
      expect(local.getCachedCredentials('B'), (null, null));
      expect(box.get(AuthLocalDataSource.legacyTgcKey), 'tgc-legacy');
    });

    test('旧 cachedUser 为空（无线索）→ 不认领', () async {
      await box.put(AuthLocalDataSource.legacyTgcKey, 'tgc-legacy');

      await local.claimLegacyCredentials('A');

      expect(local.getTgc('A'), isNull);
      expect(box.get(AuthLocalDataSource.legacyTgcKey), 'tgc-legacy');
    });
  });

  group('AuthRepository · 读盘按账号', () {
    test('各账号只看到自己的 TGC', () async {
      await local.saveTgc('A', 'tgc-A');

      expect(buildRepo(account: 'A').hasTgc, isTrue);
      expect(buildRepo(account: 'B').hasTgc, isFalse);
    });

    test('没有本账号 TGC 时不借用他人会话，也不发请求', () async {
      await local.saveTgc('A', 'tgc-A');
      await local.saveCachedCredentials('B', 'pw-B');

      final repoB = buildRepo(account: 'B');
      final result = await repoB.getImsRedirectInfo();

      expect(result.isLeft(), isTrue);
      expect(remote.redirectCalls, 0, reason: '无 TGC 应在联网前就失败');
      expect(remote.loginTrustAgents, isEmpty, reason: '不应触发任何登录');
    });

    test('仓库绑 A、登录 B → 新 TGC 落到 B 的键，A 的 TGC 不动（切号不写串）', () async {
      await local.saveTgc('A', 'tgc-A');
      final repoA = buildRepo(account: 'A');
      // 与真实切号流程一致：先 cacheCredentials（写盘），再 prepareLogin + login。
      repoA.cacheCredentials('B', 'pw-B');
      final prepared = await repoA.prepareLogin();
      expect(prepared.isRight(), isTrue);

      final ok = await repoA.login('B', 'pw-B', 'mfa-state-1');

      expect(ok.isRight(), isTrue);
      expect(local.getTgc('B'), 'tgc-new');
      expect(local.getTgc('A'), 'tgc-A');
      expect(local.getCachedCredentials('B'), ('B', 'pw-B'));
      expect(local.getCachedCredentials('A'), (null, null));
    });
  });

  group('AuthRepository · 登录后把 TGC 落盘（两条成功分支都要）', () {
    test('200 +「登录成功」（MFA 后）也捕获并落盘 TGC', () async {
      remote.loginStatusCode = 200;
      final repo = buildRepo(account: 'A');
      final prepared = await repo.prepareLogin();
      expect(prepared.isRight(), isTrue);

      final ok = await repo.login('A', 'pw-A', 'mfa-state-1');

      expect(ok.isRight(), isTrue);
      expect(local.getTgc('A'), 'tgc-mfa', reason: 'MFA 登录也必须拿到可持久化的票');
      expect(repo.hasTgc, isTrue);
    });

    test('200 分支没带 Set-Cookie → 登录仍算成功，只是没票（原行为不变）', () async {
      remote.loginStatusCode = 200;
      remote.login200SetsCookie = false;
      final repo = buildRepo(account: 'A');
      await repo.prepareLogin();

      final ok = await repo.login('A', 'pw-A', 'mfa-state-1');

      expect(ok.isRight(), isTrue);
      expect(local.getTgc('A'), isNull);
      expect(repo.hasTgc, isFalse);
    });

    test('302 但 Set-Cookie 里没有 TGC → 仍判登录失败（原报错文案保留）', () async {
      remote.login302SetsCookie = false;
      final repo = buildRepo(account: 'A');
      await repo.prepareLogin();

      final result = await repo.login('A', 'pw-A', 'mfa-state-1');

      expect(result.isLeft(), isTrue);
      expect(
        result.fold((f) => f.message, (_) => ''),
        contains('Set-Cookie'),
      );
    });
  });

  group('AuthRepository · 自动重登使用本账号凭据', () {
    test('TGC 过期 → 用本账号缓存凭据重登，新 TGC 落回本账号键', () async {
      await local.saveTgc('A', 'tgc-old');
      await local.saveCachedCredentials('A', 'pw-A');
      await local.saveTgc('B', 'tgc-B');
      final repoA = buildRepo(account: 'A');
      remote.expireCalls = 1; // 第一次过期，重登后正常

      final result = await repoA.getImsRedirectInfo();

      expect(result.isRight(), isTrue);
      expect(remote.loginTrustAgents, isNotEmpty);
      expect(local.getTgc('A'), 'tgc-new');
      expect(local.getTgc('B'), 'tgc-B', reason: '重登只应更新本账号的 TGC');
    });
  });

  group('AuthRepository.isTgcAlive · 免登录闸门', () {
    test('无 TGC → false，且零请求', () async {
      expect(await buildRepo(account: 'A').isTgcAlive(), isFalse);
      expect(remote.redirectCalls, 0);
    });

    test('TGC 有效 → true（不发登录、不弹 MFA）', () async {
      await local.saveTgc('A', 'tgc-A');

      expect(await buildRepo(account: 'A').isTgcAlive(), isTrue);
      expect(remote.loginTrustAgents, isEmpty);
    });

    test('TGC 过期 → false，且**不触发**静默重登（闸门不得替代登录流程）', () async {
      await local.saveTgc('A', 'tgc-A');
      await local.saveCachedCredentials('A', 'pw-A');
      remote.expireCalls = 999;

      expect(await buildRepo(account: 'A').isTgcAlive(), isFalse);
      expect(
        remote.loginTrustAgents,
        isEmpty,
        reason: '闸门只做探测；重登必须留给启动/切号的完整流程（可能弹 MFA）',
      );
    });

    test('CAS 把请求 302 打回登录页 → 判为失效（不许假阳性「免登录」）', () async {
      await local.saveTgc('A', 'tgc-A');
      await local.saveCachedCredentials('A', 'pw-A');
      remote.loginPageRedirect = true;

      expect(await buildRepo(account: 'A').isTgcAlive(), isFalse);
      expect(remote.loginTrustAgents, isEmpty, reason: '闸门本身不重登');
    });

    test('网络异常 → false 且不抛出（回落完整登录）', () async {
      await local.saveTgc('A', 'tgc-A');
      remote.throwNetwork = true;

      expect(await buildRepo(account: 'A').isTgcAlive(), isFalse);
    });
  });
}
