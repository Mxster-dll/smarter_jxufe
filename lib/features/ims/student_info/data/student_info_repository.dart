import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/anti_corruption/student_info_mapper.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/datasources/student_info_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/datasources/student_info_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/user.dart';

/// 学生基本信息仓库，协调本地缓存、IMS 鉴权与远程数据源。
///
/// 数据流：
/// 1. 从 [ImsAuthRepository] 获取 JSESSIONID
/// 2. 凭 JSESSIONID 请求 STU_BaseInfoAction.do
/// 3. 解析结果并持久化到 Hive 缓存
class StudentInfoRepository {
  final StudentInfoLocalDataSource _localDataSource;
  final StudentInfoRemoteDataSource _remoteDataSource;
  final StudentInfoMapper _mapper;
  final ImsAuthRepository _imsAuthRepo;

  StudentInfoRepository({
    required StudentInfoLocalDataSource localDataSource,
    required StudentInfoRemoteDataSource remoteDataSource,
    required StudentInfoMapper mapper,
    required ImsAuthRepository imsAuthRepo,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _mapper = mapper,
       _imsAuthRepo = imsAuthRepo;

  /// 获取缓存的用户信息，无缓存时返回 null。
  Either<Failure, User?> getCachedUser() {
    try {
      return Right(_localDataSource.getUser());
    } catch (e) {
      return Left(CacheFailure('读取学生信息缓存失败: $e'));
    }
  }

  /// 从教务系统远程获取学生信息并缓存到本地。
  Future<Either<Failure, User>> _fetchAndSaveUser() async {
    try {
      final jsessionResult = await _imsAuthRepo.getJsessionId();
      if (jsessionResult.isLeft()) {
        return Left(
          jsessionResult.swap().getOrElse(() => UnknownFailure('??')),
        );
      }
      final jsessionId = jsessionResult.getOrElse(() => '');
      if (jsessionId == null || jsessionId.isEmpty) {
        return Left(UnknownFailure('JSESSIONID 为空'));
      }

      final parsed = await _remoteDataSource.fetchStudentInfo(
        jsessionId: jsessionId,
      );
      final user = _mapper.fromParsed(parsed);
      await _localDataSource.saveUser(user);
      return Right(user);
    } catch (e) {
      return Left(SyncFailure('获取学生信息失败: $e'));
    }
  }

  /// 获取学生信息：优先返回缓存，若 [forceRefresh] 为 true 或缓存为空则从远程拉取。
  Future<Either<Failure, User>> getUser({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _localDataSource.getUser();
      if (cached != null) return Right(cached);
    }

    return _fetchAndSaveUser();
  }

  /// 清除本地缓存。
  Future<Either<Failure, void>> clearCache() async {
    try {
      await _localDataSource.clear();
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('清除学生信息缓存失败: $e'));
    }
  }
}
