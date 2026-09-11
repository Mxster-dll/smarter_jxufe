import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/mfa_result.dart';
import 'package:smarter_jxufe/features/auth/data/mfa_relogin_service.dart';

class AuthRepository {
  final AuthLocalDataSource _localDataSource;
  final AuthRemoteDataSource _remoteDataSource;
  final DeviceProfileRepository _deviceProfileRepo;

  /// 本仓库代表的账号 —— **读盘作用域**。
  ///
  /// TGC / 缓存凭据按账号分键存放（`auth` box 的 `TGC|<账号>` 等），
  /// 构造时只读 [account] 这一份，因此切换账号各拿各的磁盘状态
  /// （「切回来不用重新登录」）。**写盘始终按入参账号**
  /// （[login] / [cacheCredentials] 的第一个参数），所以「当前是 A、
  /// 正在登录 B」的切号流程也不会写串。
  final String account;

  String? _tgc;

  /// 缓存的登录凭据，用于 TGC 过期后自动重新登录。
  String? _cachedUsername;
  String? _cachedPassword;

  /// 「信任此设备」记忆：与登录凭据一同持久化。
  ///
  /// 自动重登（后台静默刷新也会走这条路）没有用户在场，
  /// 只能凭它决定是否继续携带 `trustAgent=true`。
  bool _trustDevice = false;
  String? _trustUsername;

  /// MFA 回调。当自动重登需要 MFA 验证时调用。
  /// 参数为 mfaState，回调应处理 MFA 验证流程（如显示统一 MFA 对话框）；
  /// 返回值为用户是否勾选「信任此设备」。
  /// 回调成功返回后，自动继续登录流程；若抛出异常则视为 MFA 失败。
  AuthMfaHandler? onMfaRequired;

  /// 防重入：重登正在进行中时，后续请求等待而非直接失败。
  Completer<Either<Failure, void>>? _reloginCompleter;

  /// 登录页预请求结果，包含 execution 和 loginUrl。
  /// 每次登录流程开始前通过 [prepareLogin] 设置。
  CasLoginPageInfo? _casLoginPage;

  AuthRepository({
    required AuthLocalDataSource localDataSource,
    required AuthRemoteDataSource remoteDataSource,
    required DeviceProfileRepository deviceProfileRepo,
    this.account = '',
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _deviceProfileRepo = deviceProfileRepo {
    _tgc = _localDataSource.getTgc(account);
    final (user, pass) = _localDataSource.getCachedCredentials(account);
    _cachedUsername = user;
    _cachedPassword = pass;
    _trustUsername = user;
    _trustDevice = user != null && _localDataSource.isTrustDevice(user);
  }

  /// 缓存登录凭据，供后续 TGC 过期时自动重登使用。
  /// 应在获取到账户密码后尽早调用（不依赖 login 成功）。
  /// 同时持久化到 Hive，防止 AuthRepository 实例被重建后丢失。
  void cacheCredentials(String username, String password) {
    debugPrint('[AuthRepo] cacheCredentials: $username');
    _cachedUsername = username;
    _cachedPassword = password;
    _localDataSource.saveCachedCredentials(username, password);
  }

  /// 记录（或取消）「信任此设备」并持久化。
  ///
  /// CAS 以设备指纹 `fpVisitorId` 记忆可信设备，而信任只在登录表单
  /// 携带 `trustAgent=true` 时才登记。自动重登没有用户在场，
  /// 靠这份记忆才能持续把 `trustAgent=true` 送上去 → 长期免二次验证。
  Future<void> rememberTrustDevice(String username, bool trusted) async {
    debugPrint('[AuthRepo] rememberTrustDevice: $username → $trusted');
    _trustUsername = username;
    _trustDevice = trusted;
    await _localDataSource.saveTrustDevice(username, trusted);
  }

  /// 指定账号是否已登记「信任此设备」。
  bool isTrustDevice(String username) => _trustUsername == username
      ? _trustDevice
      : _localDataSource.isTrustDevice(username);

  /// 内存里是否已有本账号的 TGC（不代表服务端仍认它）。
  bool get hasTgc => _tgc != null;

  /// 磁盘上的 TGC 在 CAS 侧是否仍然有效（**不触发自动重登**，一次请求）。
  ///
  /// 启动 / 切换账号的**免登录闸门**：为 true 说明这个账号仍是登录态，
  /// 直接进入即可（免密码、免 MFA）；为 false 才回落完整登录流程。
  ///
  /// ⚠ 与 [getImsRedirectInfo] 的区别：后者在 TGC 过期时会**静默重登**
  /// （需要时还会弹 MFA），拿它当闸门等于「每次启动都重登一遍」。
  Future<bool> isTgcAlive() async {
    final tgc = _tgc;
    if (tgc == null) return false;
    try {
      final (url, _) = await _remoteDataSource.getRedirectImsUrl(tgc);
      // ⚠️ 光「有 Location」不算数：CAS 在会话已失效时会把请求 302 打回
      // `/cas/login?...`（带 service 参数），`getRedirectImsUrl` 对任何
      // Location 都返回成功 → 会变成「假阳性 = 拿死票免登录」。
      // 真正登录态的回跳地址是**服务端**的回调（带 ticket），不会指回登录页。
      final path = Uri.tryParse(url)?.path ?? '';
      if (path.contains('/cas/login')) {
        debugPrint('[AuthRepo] isTgcAlive：CAS 打回登录页，判定为已失效');
        return false;
      }
      return true;
    } on TgcExpiredException {
      return false;
    } catch (e) {
      // 网络异常等一律视为「不可用」→ 回落完整登录（失败有明确提示）。
      debugPrint('[AuthRepo] isTgcAlive 探测失败：$e');
      return false;
    }
  }

  /// 预请求：获取 CAS 登录页面，提取 [execution] 和 [loginUrl]。
  ///
  /// 在每次登录之前必须调用。此方法将结果缓存在内部，
  /// 后续 [detectMfa] 和 [login] 会自动使用。
  Future<Either<Failure, void>> prepareLogin() async {
    try {
      _casLoginPage = await _remoteDataSource.fetchCasLoginPage();
      return const Right(null);
    } catch (e) {
      return Left(UnknownFailure('获取登录页失败: $e'));
    }
  }

  /// 第一步：检测是否需要 MFA
  Future<Either<Failure, MfaResult>> detectMfa(
    String username,
    String password,
  ) async {
    if (_casLoginPage == null) {
      return Left(UnknownFailure('请先调用 prepareLogin()'));
    }

    final fpVisitorId = _deviceProfileRepo.fpVisitorId;

    try {
      final mfaResponse = await _remoteDataSource.detectMfa(
        username: username,
        password: password,
        fpVisitorId: fpVisitorId,
        referer: _casLoginPage!.loginUrl,
        sessionCookie: _casLoginPage!.sessionCookie,
      );

      if (mfaResponse.statusCode != 200) {
        return Left(
          UnknownFailure('MFA 检测失败: statusCode=${mfaResponse.statusCode}'),
        );
      }

      final mfaJson = mfaResponse.data;
      if (mfaJson['code'] != 0) {
        return Left(UnknownFailure('MFA 检测失败: code=${mfaJson['code']}'));
      }

      final mfaData = mfaJson['data'];
      return Right(
        MfaResult(
          needMfa: mfaData['need'] == true,
          mfaState: mfaData['state'] as String,
        ),
      );
    } catch (e) {
      return Left(UnknownFailure('MFA 检测错误：$e'));
    }
  }

  /// 第二步：提交登录（MFA 完成后调用）
  Future<Either<Failure, void>> login(
    String username,
    String password,
    String mfaState, {
    String trustAgent = '',
  }) async {
    _cachedUsername = username;
    _cachedPassword = password;

    if (_casLoginPage == null) {
      return Left(UnknownFailure('请先调用 prepareLogin()'));
    }

    final fpVisitorId = _deviceProfileRepo.fpVisitorId;

    try {
      final response = await _remoteDataSource.login(
        username: username,
        password: password,
        fpVisitorId: fpVisitorId,
        mfaState: mfaState,
        execution: _casLoginPage!.execution,
        loginUrl: _casLoginPage!.loginUrl,
        sessionCookie: _casLoginPage!.sessionCookie,
        trustAgent: trustAgent,
      );

      // 401 且响应体包含 "账号或密码错误" → 密码错误
      if (response.statusCode == 401) {
        final body = response.data?.toString() ?? '';
        if (body.contains('账号或密码错误')) {
          return Left(InvalidCredentialsFailure('账号或密码错误'));
        }
        return Left(UnknownFailure('登录失败（401）：$body'));
      }

      // 302 且有 Set-Cookie → 登录成功
      if (response.statusCode == 302) {
        final cookies = response.headers['set-cookie'];
        if (cookies == null || cookies.isEmpty) {
          return Left(UnknownFailure('登录失败：未收到 Set-Cookie'));
        }

        if (!await _captureTgcFromCookies(response, username)) {
          return Left(UnknownFailure('登录失败：Set-Cookie 中未找到 TGC'));
        }
        // 用户本次勾选「信任此设备」→ 记住，供后续静默重登复用。
        if (trustAgent == 'true') {
          await rememberTrustDevice(username, true);
        }
        return const Right(null);
      }

      // 200 + 响应体包含 "登录成功" → MFA 验证后登录成功
      if (response.statusCode == 200) {
        final body = response.data?.toString() ?? '';
        if (body.contains('登录成功')) {
          // ⚠️ 这条分支同样要认 Set-Cookie 里的 TGC：走 MFA 的登录不经过
          // 302 分支，若这里不捕获，「统一登录按账号持久化」对 MFA 用户
          // 就永远落不了盘（下次启动照样得重登）。有票就存，没有则不变。
          await _captureTgcFromCookies(response, username);
          // 用户本次勾选「信任此设备」→ 记住，供后续静默重登复用。
          if (trustAgent == 'true') {
            await rememberTrustDevice(username, true);
          }
          return const Right(null);
        }
      }

      // 其他状态码
      return Left(UnknownFailure('登录失败：预期 302，实际 ${response.statusCode}'));
    } catch (e) {
      return Left(UnknownFailure('登录错误：$e'));
    }
  }

  /// 从 `Set-Cookie` 里提取 TGC 并**按 [username] 落盘**，返回是否拿到票。
  ///
  /// 两条登录成功分支（302 与 200+MFA）共用：少了它，走 MFA 的登录拿不到
  /// 可持久化的 TGC，「按账号持久化 + 免登录闸门」对这类账号就是空的。
  /// 写盘键用**入参账号**（不是本仓库绑定的账号），切号登录也不会写串。
  Future<bool> _captureTgcFromCookies(
    Response<dynamic> response,
    String username,
  ) async {
    final cookies = response.headers['set-cookie'];
    if (cookies == null || cookies.isEmpty) return false;
    for (final cookie in cookies) {
      for (final part in cookie.split(';')) {
        final trimmed = part.trim();
        if (trimmed.startsWith('TGC=')) {
          _tgc = trimmed.substring(4);
          await _localDataSource.saveTgc(username, _tgc!);
          return true;
        }
      }
    }
    return false;
  }

  /// 获取 IMS 重定向 URL 及 [gid_]。
  /// 若 TGC 已过期（CAS 返回 HTML 登录页而非 302 重定向），
  /// 自动使用缓存的凭据重新执行统一登录后重试。
  Future<Either<Failure, (String, String?)>> getImsRedirectInfo() async {
    try {
      if (_tgc == null) {
        return Left(UnknownFailure('尚未授权，getImsRedirectInfo 失败'));
      }

      final (url, gid) = await _remoteDataSource.getRedirectImsUrl(_tgc!);
      return Right((url, gid));
    } on TgcExpiredException {
      // TGC 过期 → 尝试用缓存凭据重新登录
      final reloginResult = await _relogin();
      if (reloginResult.isLeft()) {
        return Left(
          reloginResult.fold((f) => f, (_) => UnknownFailure('重登失败')),
        );
      }
      // 重登成功，用新 TGC 重试
      try {
        final (url, gid) = await _remoteDataSource.getRedirectImsUrl(_tgc!);
        return Right((url, gid));
      } catch (e) {
        return Left(UnknownFailure('IMS 重定向错误（重登后）：$e'));
      }
    } catch (e) {
      if (e is TgcExpiredException) rethrow;
      return Left(UnknownFailure('IMS 重定向错误：$e'));
    }
  }

  /// 使用缓存凭据自动重新登录。
  Future<Either<Failure, void>> _relogin() async {
    debugPrint('[AuthRepo] _relogin 触发');
    // 已有重登在进行中 → 等待其结果
    if (_reloginCompleter != null) {
      debugPrint('[AuthRepo] _relogin 等待中...');
      return _reloginCompleter!.future;
    }
    if (_cachedUsername == null || _cachedPassword == null) {
      debugPrint('[AuthRepo] _relogin 跳过：缺少缓存凭据');
      return Left(UnknownFailure('缺少缓存凭据，无法自动重登'));
    }

    final completer = Completer<Either<Failure, void>>();
    _reloginCompleter = completer;
    debugPrint('[AuthRepo] _relogin 开始，用户=$_cachedUsername');
    try {
      // 重新获取 CAS 登录页
      final prepareResult = await prepareLogin();
      if (prepareResult.isLeft()) {
        debugPrint('[AuthRepo] _relogin 失败：获取登录页失败');
        completer.complete(prepareResult);
        return prepareResult;
      }

      // MFA 检测
      final mfaResult = await detectMfa(_cachedUsername!, _cachedPassword!);
      if (mfaResult.isLeft()) {
        debugPrint('[AuthRepo] _relogin 失败：MFA检测失败');
        final r = Left<Failure, void>(
          mfaResult.fold((f) => f, (_) => UnknownFailure('MFA检测失败')),
        );
        completer.complete(r);
        return r;
      }
      final mfa = mfaResult.getOrElse(() => throw 'unreachable');

      // 已登记「信任此设备」→ 继续携带 trustAgent，用户不在场也能免二次验证。
      var trust = isTrustDevice(_cachedUsername!);

      // 如果重登需要 MFA，通过回调启动 MFA 对话框
      if (mfa.needMfa) {
        debugPrint('[AuthRepo] _relogin 需要 MFA（此前已信任=$trust）');
        bool dialogTrust = false;
        if (onMfaRequired != null) {
          try {
            dialogTrust = await onMfaRequired!(mfa.mfaState);
            debugPrint('[AuthRepo] MFA 完成（勾选信任=$dialogTrust）');
          } catch (e) {
            debugPrint('[AuthRepo] MFA 取消/失败: $e');
            final r = Left<Failure, void>(UnknownFailure('MFA 验证失败或已取消: $e'));
            completer.complete(r);
            return r;
          }
        } else {
          try {
            dialogTrust = await mfaReloginService.execute(
              mfa.mfaState,
              _cachedUsername!,
              _cachedPassword!,
            );
            debugPrint('[AuthRepo] MFA 完成（兜底，勾选信任=$dialogTrust）');
          } catch (e) {
            debugPrint('[AuthRepo] MFA 取消/失败（兜底）: $e');
            final r = Left<Failure, void>(UnknownFailure('MFA 验证失败或已取消: $e'));
            completer.complete(r);
            return r;
          }
        }
        // 用户在对话框里勾选信任 → 记住，此后重登不再需要验证。
        if (dialogTrust) {
          trust = true;
          await rememberTrustDevice(_cachedUsername!, true);
        }
      }

      // 提交登录
      debugPrint('[AuthRepo] _relogin 提交登录 trust=$trust');
      final result = await login(
        _cachedUsername!,
        _cachedPassword!,
        mfa.mfaState,
        trustAgent: trust ? 'true' : '',
      );
      debugPrint('[AuthRepo] _relogin 结果: ${result.isRight() ? "成功" : "失败"}');
      completer.complete(result);
      return result;
    } catch (e) {
      final r = Left<Failure, void>(UnknownFailure('重登异常: $e'));
      completer.complete(r);
      return r;
    } finally {
      _reloginCompleter = null;
    }
  }

  Future<Either<Failure, String>> getImsRedirectUrl() async {
    final result = await getImsRedirectInfo();
    return result.fold((f) => Left(f), (info) => Right(info.$1));
  }

  /// 获取指定平台（如 SSP 综合管理平台）的 CAS 会话回调地址。
  ///
  /// 若 TGC 已过期（CAS 返回 HTML 登录页而非 302 重定向），
  /// 自动使用缓存的凭据重新执行统一登录后重试一次。
  Future<Either<Failure, String>> getServiceRedirectUrl(
    String casLoginUrl,
  ) async {
    try {
      if (_tgc == null) {
        return Left(UnknownFailure('尚未授权，无法获取平台会话'));
      }
      return Right(
        await _remoteDataSource.getCasRedirectUrl(_tgc!, casLoginUrl),
      );
    } on TgcExpiredException {
      // TGC 过期 → 尝试用缓存凭据重新登录
      final reloginResult = await _relogin();
      if (reloginResult.isLeft()) {
        return Left(
          reloginResult.fold((f) => f, (_) => UnknownFailure('重登失败')),
        );
      }
      // 重登成功，用新 TGC 重试一次
      try {
        final url = await _remoteDataSource.getCasRedirectUrl(
          _tgc!,
          casLoginUrl,
        );
        return Right(url);
      } on TgcExpiredException catch (e) {
        return Left(UnknownFailure('统一登录已失效，请重新登录：$e'));
      } catch (e) {
        return Left(UnknownFailure('获取平台会话错误（重登后）：$e'));
      }
    } catch (e) {
      if (e is TgcExpiredException) rethrow;
      return Left(UnknownFailure('获取平台会话错误：$e'));
    }
  }
}
