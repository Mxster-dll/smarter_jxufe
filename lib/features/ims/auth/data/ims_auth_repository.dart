import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/ims/auth/data/datasource/ims_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/auth/data/datasource/ims_auth_remote_datasource.dart';

class ImsAuthRepository {
  final Dio _dio;

  final AuthRepository _authRepository;
  final ImsAuthLocalDataSource _localDataSource;
  final ImsAuthRemoteDataSource _remoteDataSource;

  ImsAuthRepository({
    required Dio dio,
    required AuthRepository authRepository,
    required ImsAuthLocalDataSource localDataSource,
    required ImsAuthRemoteDataSource remoteDataSource,
  }) : _dio = dio,
       _authRepository = authRepository,
       _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource;

  /// 登录 IMS：使用已存储的 TGC 换取 JSESSIONID
  /// 前提：全局认证已完成，TGC 已存在于 AuthRepository 中
  /// 如果 TGC 缺失或无效，抛出异常
  Future<Either<Failure, void>> login() async {
    // 1. 从统一认证获取重定向 URL
    final redirectUrlEither = await _authRepository.getImsRedirectUrl();
    if (redirectUrlEither.isLeft()) {
      return Left(
        redirectUrlEither.swap().getOrElse(() => UnknownFailure("??")),
      );
    }
    final redirectUrl = redirectUrlEither.getOrElse(() => '');

    try {
      // 2. 访问重定向 URL，不自动跟随重定向
      final imsResponse = await _dio.get(
        redirectUrl,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => true,
        ),
      );

      // 3. 提取 Set-Cookie 中的 JSESSIONID
      final setCookie = imsResponse.headers['set-cookie'];
      if (setCookie == null || setCookie.isEmpty) {
        return Left(UnknownFailure("setCookie empty"));
      }
      final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(setCookie.first);
      final jsessionId = match?.group(1);
      if (jsessionId == null) {
        return Left(UnknownFailure("jsessionId empty"));
      }

      // 4. 保存 JSESSIONID
      await _localDataSource.saveJsessionId(jsessionId);
      return const Right(unit);
    } catch (e) {
      // 网络或 Dio 异常
      return Left(NetworkFailure(e.toString()));
    }
  }

  Future<void> refreshJsessionId() async {
    final jsessionId = await _remoteDataSource.fetchJsessionId();

    await _localDataSource.saveJsessionId(jsessionId);
  }

  Future<void> logout() => _localDataSource.clearJsessionId();

  Future<Either<Failure, String?>> getJsessionId({
    bool forceRefresh = false,
  }) async {
    try {
      final cacheJsessionId = _localDataSource.getJsessionId();

      final needRefresh = forceRefresh || cacheJsessionId == null;
      if (!needRefresh) return Right(cacheJsessionId);

      final jsessionId = await _remoteDataSource.fetchJsessionId();

      return Right(jsessionId);
    } catch (e) {
      return Left(UnknownFailure('失败: $e'));
    }
  }
}
