import 'dart:async';

import 'package:dartz/dartz.dart';
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

  String? _tgc;

  /// 缓存的登录凭据，用于 TGC 过期后自动重新登录。
  String? _cachedUsername;
  String? _cachedPassword;

  /// MFA 回调。当自动重登需要 MFA 验证时调用。
  /// 参数为 mfaState，回调应处理 MFA 验证流程（如显示统一 MFA 对话框）。
  /// 回调成功返回后，自动继续登录流程；若抛出异常则视为 MFA 失败。
  Future<void> Function(String mfaState)? onMfaRequired;

  /// 防重入：重登正在进行中时，后续请求等待而非直接失败。
  Completer<Either<Failure, void>>? _reloginCompleter;

  /// 登录页预请求结果，包含 execution 和 loginUrl。
  /// 每次登录流程开始前通过 [prepareLogin] 设置。
  CasLoginPageInfo? _casLoginPage;

  AuthRepository({
    required AuthLocalDataSource localDataSource,
    required AuthRemoteDataSource remoteDataSource,
    required DeviceProfileRepository deviceProfileRepo,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _deviceProfileRepo = deviceProfileRepo {
    _tgc = _localDataSource.getTgc();
    final (user, pass) = _localDataSource.getCachedCredentials();
    _cachedUsername = user;
    _cachedPassword = pass;
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

        for (var cookie in cookies) {
          final parts = cookie.split(';');
          for (var part in parts) {
            final trimmed = part.trim();
            if (trimmed.startsWith('TGC=')) {
              _tgc = trimmed.substring(4);
              await _localDataSource.saveTgc(_tgc!);
              return const Right(null);
            }
          }
        }

        return Left(UnknownFailure('登录失败：Set-Cookie 中未找到 TGC'));
      }

      // 200 + 响应体包含 "登录成功" → MFA 验证后登录成功
      if (response.statusCode == 200) {
        final body = response.data?.toString() ?? '';
        if (body.contains('登录成功')) {
          return const Right(null);
        }
      }

      // 其他状态码
      return Left(UnknownFailure('登录失败：预期 302，实际 ${response.statusCode}'));
    } catch (e) {
      return Left(UnknownFailure('登录错误：$e'));
    }
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

      // 如果重登需要 MFA，通过回调启动 MFA 对话框
      if (mfa.needMfa) {
        debugPrint('[AuthRepo] _relogin 需要 MFA');
        if (onMfaRequired != null) {
          try {
            await onMfaRequired!(mfa.mfaState);
            debugPrint('[AuthRepo] MFA 完成');
          } catch (e) {
            debugPrint('[AuthRepo] MFA 取消/失败: $e');
            final r = Left<Failure, void>(UnknownFailure('MFA 验证失败或已取消: $e'));
            completer.complete(r);
            return r;
          }
        } else {
          try {
            await mfaReloginService.execute(
              mfa.mfaState,
              _cachedUsername!,
              _cachedPassword!,
            );
            debugPrint('[AuthRepo] MFA 完成（兜底）');
          } catch (e) {
            debugPrint('[AuthRepo] MFA 取消/失败（兜底）: $e');
            final r = Left<Failure, void>(UnknownFailure('MFA 验证失败或已取消: $e'));
            completer.complete(r);
            return r;
          }
        }
      }

      // 提交登录
      debugPrint('[AuthRepo] _relogin 提交登录');
      final result = await login(
        _cachedUsername!,
        _cachedPassword!,
        mfa.mfaState,
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
}
