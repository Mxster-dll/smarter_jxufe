import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import '../../../ims/data/repositories/ims_auth_repository.dart';
import '../datasources/login_local_datasource.dart';
import '../datasources/login_remote_datasource.dart';

class LoginRepository {
  final LoginRemoteDataSource _remoteDataSource;
  final LoginLocalDataSource _localDataSource;
  final ImsAuthRepository _imsAuthRepository;

  LoginRepository(
    this._remoteDataSource,
    this._localDataSource,
    this._imsAuthRepository,
  );

  // 固定 gid，可直接从 remote 获取
  String get gid => LoginRemoteDataSource.gid;

  /// 执行完整登录流程
  Future<Either<Failure, String>> login(
    String username,
    String password,
  ) async {
    try {
      // 1. 预加载登录页面（获取 execution 等）
      await _remoteDataSource.preloadLoginPage();

      // 2. 提交用户名密码，获取重定向地址
      final redirectUrl = await _remoteDataSource.login(username, password);

      // 3. 从重定向地址获取 JSESSIONID
      final jsessionId = await _remoteDataSource.getJSessionIdFromRedirect(
        redirectUrl,
      );

      // 4. 保存 JSESSIONID 到 IMS 会话管理器
      await _imsAuthRepository.saveJSessionId(jsessionId);

      // 5. 可选：保存最后登录的用户名
      await _localDataSource.saveLastUsername(username);

      return Right(jsessionId);
    } on DioException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// 登出
  Future<void> logout() async {
    await _imsAuthRepository.clearSession();
    await _localDataSource.clearLastUsername();
  }
}
