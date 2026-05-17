import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/college/data/datasources/college_local_datasource.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/college/data/college_mapper.dart';
import 'package:smarter_jxufe/features/college/data/datasources/college_remote_datasource.dart';

class CollegeRepository {
  final CollegeLocalDataSource _localDataSource;
  final CollegeRemoteDataSource _remoteDataSource;
  final CollegeMapper _collegeMapper;

  CollegeRepository({
    required CollegeLocalDataSource localDataSource,
    required CollegeRemoteDataSource remoteDataSource,
    required CollegeMapper collegeMapper,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _collegeMapper = collegeMapper;

  Future<Either<Failure, List<College>>> getAllCollege({
    bool forceRefresh = false,
  }) async {
    try {
      final cacheColleges = _localDataSource.getAllCollege();

      final needRefresh = forceRefresh || cacheColleges.isEmpty;
      if (!needRefresh) return Right(cacheColleges);

      final apiColleges = await _remoteDataSource.getAllCollege();
      final colleges = _collegeMapper.fromApiList(apiColleges);

      return Right(colleges);
    } catch (e) {
      return Left(SyncFailure('同步失败: $e'));
    }
  }
}
