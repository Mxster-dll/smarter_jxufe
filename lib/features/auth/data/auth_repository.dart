import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';

class AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;

  String? _tgc;

  AuthRepository({required AuthRemoteDataSource remoteDataSource})
    : _remoteDataSource = remoteDataSource;

  /// 登录流程：检测 MFA → 提交登录 → 获取 TGC → 构造 User
  Future<Either<Failure, void>> login(String username, String password) async {
    final fpVisitorId = _generateFpVisitorId();

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

  String _generateFpVisitorId() {
    return "9d832cfb4202ae54caf83ba4e2e1d8a2";
  }
}
