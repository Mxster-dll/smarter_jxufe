import 'package:dartz/dartz.dart';
import 'package:get_storage/get_storage.dart';
import 'package:dio/dio.dart';
import 'package:smarter_jxufe/core/errors/failures.dart';
import 'ims_auth_remote_datasource.dart';

class ImsAuthRepository {
  final ImsAuthRemoteDataSource _remoteDataSource;
  final GetStorage _storage;
  static const String _keyJSessionId = 'jsessionid';

  ImsAuthRepository(this._remoteDataSource, this._storage);

  String? get currentSessionId => _storage.read<String>(_keyJSessionId);

  Future<Either<Failure, String>> login(String gid) async {
    try {
      final jsessionId = await _remoteDataSource.fetchJSessionId(gid);
      await _storage.write(_keyJSessionId, jsessionId);
      return Right(jsessionId);
    } on DioException catch (e) {
      return Left(NetworkFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, String>> refresh(String gid) async {
    await _storage.remove(_keyJSessionId);
    return login(gid);
  }

  Future<void> saveJSessionId(String jsessionId) async {
    await _storage.write(_keyJSessionId, jsessionId);
  }

  Future<void> clearSession() async {
    await _storage.remove(_keyJSessionId);
  }
}
