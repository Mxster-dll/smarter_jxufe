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

  /// 从 CAS→IMS 重定向 URL 中提取的 gid_，提取失败则为 null。
  String? _cachedGid;

  ImsAuthRepository({
    required Dio dio,
    required AuthRepository authRepository,
    required ImsAuthLocalDataSource localDataSource,
    required ImsAuthRemoteDataSource remoteDataSource,
  }) : _dio = dio,
       _authRepository = authRepository,
       _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource;

  /// 尝试从 CAS 重定向 URL 中提取并缓存 [gid_]。
  Future<void> _tryCacheGid() async {
    if (_cachedGid != null) return;
    final result = await _authRepository.getImsRedirectInfo();
    result.fold((_) => null, (info) => _cachedGid = info.$2);
  }

  /// 登录 IMS：使用已存储的 TGC 换取 JSESSIONID
  Future<Either<Failure, void>> _activateJsessionId(String jsessionId) async {
    final redirectUrlEither = await _authRepository.getImsRedirectUrl();
    if (redirectUrlEither.isLeft()) {
      return Left(
        redirectUrlEither.swap().getOrElse(() => UnknownFailure("??")),
      );
    }
    final redirectUrl = redirectUrlEither.getOrElse(() => '');

    try {
      await _dio.get(
        redirectUrl,
        options: Options(headers: {'Cookie': 'JSESSIONID=$jsessionId'}),
      );

      return const Right(unit);
    } catch (e) {
      return Left(NetworkFailure(e.toString()));
    }
  }

  Future<String> refreshJsessionId() async {
    await _tryCacheGid(); // 先尝试提取 gid_
    final jsessionId = await _remoteDataSource.fetchJsessionId(gid: _cachedGid);
    await _localDataSource.saveJsessionId(jsessionId);

    await _activateJsessionId(jsessionId);
    return jsessionId;
  }

  Future<void> logout() => _localDataSource.clearJsessionId();

  Future<Either<Failure, String?>> getJsessionId({
    bool forceRefresh = false,
  }) async {
    try {
      final cacheJsessionId = _localDataSource.getJsessionId();

      final needRefresh =
          forceRefresh || cacheJsessionId == null; // 刷新判断逻辑要大改，要考虑是否失效
      if (!needRefresh) return Right(cacheJsessionId);

      final jsessionId = await refreshJsessionId();

      return Right(jsessionId);
    } catch (e) {
      return Left(UnknownFailure('失败: $e'));
    }
  }
}
