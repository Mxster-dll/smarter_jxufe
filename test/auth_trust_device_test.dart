import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository.dart';
import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';

/// 「信任此设备」持久化守卫。
///
/// 背景：CAS 只在登录表单携带 `trustAgent=true` 时登记可信设备；
/// 自动重登（含后台静默刷新）没有用户在场，若丢掉这个标记，
/// 每次重登都会被要求重新扫码/短信验证 —— 即用户反馈的「重复登录」。
class _FakeRemoteDataSource extends AuthRemoteDataSource {
  _FakeRemoteDataSource() : super(Dio());

  /// 每次提交登录时收到的 trustAgent 值。
  final List<String> loginTrustAgents = <String>[];

  /// 服务端是否要求 MFA（真实场景由 fpVisitorId 是否可信决定）。
  bool needMfa = true;

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

  /// 模拟 TGC 已过期：取重定向 URL 时抛 [TgcExpiredException] 触发自动重登。
  @override
  Future<(String, String?)> getRedirectImsUrl(String tgc) async =>
      throw TgcExpiredException('expired');

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
    return Response<dynamic>(
      requestOptions: RequestOptions(path: '/cas/login'),
      statusCode: 302,
      headers: Headers.fromMap({
        'set-cookie': ['TGC=tgc-new; Path=/; HttpOnly'],
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
    tempDir = Directory.systemTemp.createTempSync('auth_trust_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('authTrustTest');
    local = AuthLocalDataSource(box);
    remote = _FakeRemoteDataSource();
  });

  tearDown(() async {
    await box.close();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// 仓库绑账号（TGC / 凭据按账号分键存放）——本文件统一用该账号。
  AuthRepository buildRepo({String account = '201600035929'}) => AuthRepository(
    localDataSource: local,
    remoteDataSource: remote,
    deviceProfileRepo: const DeviceProfileRepository(),
    account: account,
  );

  group('AuthLocalDataSource · 信任设备持久化', () {
    test('默认不信任；记录后可按账号查回', () async {
      expect(local.isTrustDevice('201600035929'), isFalse);
      expect(local.getTrustDevices(), isEmpty);

      await local.saveTrustDevice('201600035929', true);

      expect(local.isTrustDevice('201600035929'), isTrue);
      expect(local.isTrustDevice('201600035930'), isFalse);
      // 持久化：同一 box 重新构造数据源仍读得到。
      expect(
        AuthLocalDataSource(box).isTrustDevice('201600035929'),
        isTrue,
      );
    });

    test('取消信任会移除记录', () async {
      await local.saveTrustDevice('201600035929', true);
      await local.saveTrustDevice('201600035929', false);
      expect(local.isTrustDevice('201600035929'), isFalse);
      expect(local.getTrustDevices(), isEmpty);
    });

    test('多账号互不串号', () async {
      await local.saveTrustDevice('A', true);
      await local.saveTrustDevice('B', true);
      await local.saveTrustDevice('A', false);
      expect(local.isTrustDevice('A'), isFalse);
      expect(local.isTrustDevice('B'), isTrue);
    });

    test('损坏 JSON 容错为空表（不抛异常）', () async {
      await box.put('trustDevices', '{不是 json');
      expect(local.getTrustDevices(), isEmpty);
      expect(local.isTrustDevice('A'), isFalse);
    });
  });

  group('AuthRepository · 自动重登携带 trustAgent', () {
    /// TGC 过期 → _relogin → 提交登录；返回本次登录收到的 trustAgent。
    Future<List<String>> triggerRelogin(
      AuthRepository repo, {
      required bool dialogTrusts,
      bool attachHandler = true,
    }) async {
      if (attachHandler) {
        repo.onMfaRequired = (mfaState) async => dialogTrusts;
      }
      // _tgc 为 null 时不会走网络，直接返回「尚未授权」。
      final result = await repo.getImsRedirectInfo();
      expect(result.isLeft(), isTrue, reason: 'TGC 过期场景应失败（已是过期值）');
      return remote.loginTrustAgents;
    }

    test('首次勾选「信任此设备」→ trustAgent=true 并持久化', () async {
      await local.saveTgc('201600035929', 'tgc-old');
      await local.saveCachedCredentials('201600035929', 'pw');
      final repo = buildRepo();

      await triggerRelogin(repo, dialogTrusts: true);

      expect(remote.loginTrustAgents, ['true']);
      expect(repo.isTrustDevice('201600035929'), isTrue);
      expect(local.isTrustDevice('201600035929'), isTrue);
    });

    test('未勾选信任 → trustAgent 为空且不记录', () async {
      await local.saveTgc('201600035929', 'tgc-old');
      await local.saveCachedCredentials('201600035929', 'pw');
      final repo = buildRepo();

      await triggerRelogin(repo, dialogTrusts: false);

      expect(remote.loginTrustAgents, ['']);
      expect(repo.isTrustDevice('201600035929'), isFalse);
      expect(local.isTrustDevice('201600035929'), isFalse);
    });

    test('已登记信任 → 重启后自动重登仍携带 true（无需用户再勾选）', () async {
      await local.saveTgc('201600035929', 'tgc-old');
      await local.saveCachedCredentials('201600035929', 'pw');
      await local.saveTrustDevice('201600035929', true);

      // 模拟 App 重启：全新的 AuthRepository / 数据源实例，读同一个 box。
      final restartedLocal = AuthLocalDataSource(box);
      final restartedRepo = AuthRepository(
        localDataSource: restartedLocal,
        remoteDataSource: remote,
        deviceProfileRepo: const DeviceProfileRepository(),
        account: '201600035929',
      );
      expect(restartedRepo.isTrustDevice('201600035929'), isTrue);

      // 即使这次对话框返回「未勾选」，历史信任也应继续送达 CAS。
      await triggerRelogin(restartedRepo, dialogTrusts: false);

      expect(remote.loginTrustAgents, ['true']);
    });

    test('登录成功后按 trustAgent 落盘（手动登录路径）', () async {
      final repo = buildRepo();
      // login() 要求先预请求 CAS 登录页（提取 execution）。
      final prepared = await repo.prepareLogin();
      expect(prepared.isRight(), isTrue);

      final ok = await repo.login(
        '201600035929',
        'pw',
        'mfa-state-1',
        trustAgent: 'true',
      );

      expect(ok.isRight(), isTrue);
      expect(repo.isTrustDevice('201600035929'), isTrue);
      expect(local.isTrustDevice('201600035929'), isTrue);
    });
  });
}
