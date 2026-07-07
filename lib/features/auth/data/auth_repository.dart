import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/mfa_result.dart';

class AuthRepository {
  final AuthLocalDataSource _localDataSource;
  final AuthRemoteDataSource _remoteDataSource;
  final DeviceProfileRepository _deviceProfileRepo;

  String? _tgc;

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
  /// 返回 (重定向URL, gid_字符串或null)
  Future<Either<Failure, (String, String?)>> getImsRedirectInfo() async {
    try {
      if (_tgc == null) {
        return Left(UnknownFailure('尚未授权，getImsRedirectInfo 失败'));
      }

      final (url, gid) = await _remoteDataSource.getRedirectImsUrl(_tgc!);
      return Right((url, gid));
    } catch (e) {
      return Left(UnknownFailure('IMS 重定向错误：$e'));
    }
  }

  Future<Either<Failure, String>> getImsRedirectUrl() async {
    final result = await getImsRedirectInfo();
    return result.fold((f) => Left(f), (info) => Right(info.$1));
  }
}
