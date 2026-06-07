import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';

class AuthRepository {
  final AuthLocalDataSource _localDataSource;
  final AuthRemoteDataSource _remoteDataSource;
  final DeviceProfileRepository _deviceProfileRepo;

  String? _tgc; // tgc 和 jid 的管理方式不一致，考虑本地数据源究竟存什么，

  AuthRepository({
    required AuthLocalDataSource localDataSource,
    required AuthRemoteDataSource remoteDataSource,
    required DeviceProfileRepository deviceProfileRepo,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _deviceProfileRepo = deviceProfileRepo;

  Future<Either<Failure, bool>> login(String username, String password) async {
    final fpVisitorId = _deviceProfileRepo.fpVisitorId;

    try {
      final mfaResponse = await _remoteDataSource.detectMfa(
        username: username,
        password: password,
        fpVisitorId: fpVisitorId,
      );

      // 非 200 状态码视为 MFA 检测失败
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
      final needMfa = mfaData['need'] == true;
      final mfaState = mfaData['state'] as String;

      final response = await _remoteDataSource.login(
        username: username,
        password: password,
        fpVisitorId: fpVisitorId,
        mfaState: mfaState,
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

        // 查找 TGC cookie
        for (var cookie in cookies) {
          final parts = cookie.split(';');
          for (var part in parts) {
            final trimmed = part.trim();
            if (trimmed.startsWith('TGC=')) {
              _tgc = trimmed.substring(4);
              return Right(needMfa);
            }
          }
        }

        return Left(UnknownFailure('登录失败：Set-Cookie 中未找到 TGC'));
      }

      // 200 + needMfa → MFA 验证未完成，需要显示二维码
      if (response.statusCode == 200 && needMfa) {
        return Right(true);
      }

      // 其他状态码
      return Left(UnknownFailure('登录失败：预期 302，实际 ${response.statusCode}'));
    } catch (e) {
      return Left(UnknownFailure('登录错误：$e'));
    }
  }

  Future<Either<Failure, String>> getImsRedirectUrl() async {
    try {
      if (_tgc == null) return Left(UnknownFailure("尚未授权，getImsRedirectUrl失败"));

      final url = await _remoteDataSource.getRedirectImsUrl(_tgc!);
      return Right(url);
    } catch (e) {
      return Left(UnknownFailure("login 错误：$e"));
    }
  }
}
