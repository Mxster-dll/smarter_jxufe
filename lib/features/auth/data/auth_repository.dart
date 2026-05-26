import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';

class AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final DeviceProfileRepository _deviceProfileRepo;

  String? _tgc;

  AuthRepository({
    required AuthRemoteDataSource remoteDataSource,
    required DeviceProfileRepository deviceProfileRepo,
  }) : _remoteDataSource = remoteDataSource,
       _deviceProfileRepo = deviceProfileRepo;

  /// 登录流程：检测 MFA → 提交登录 → 获取 TGC
  Future<Either<Failure, void>> login(String username, String password) async {
    final fpVisitorId = _deviceProfileRepo.fpVisitorId;

    try {
      // 1. 检测 MFA，获取 state
      final mfaState = await _remoteDataSource.detectMfa(
        username: username,
        password: password,
        fpVisitorId: fpVisitorId,
      );

      // 2. 提交登录，获取 TGC
      _tgc = await _remoteDataSource.login(
        username: username,
        password: password,
        fpVisitorId: fpVisitorId,
        mfaState: mfaState,
      );
      return Right(null);
    } catch (e) {
      return Left(UnknownFailure("login 错误：$e"));
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
