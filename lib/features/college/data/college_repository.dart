import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/college/data/anti_corruption/college_filter.dart';
import 'package:smarter_jxufe/features/college/data/datasources/college_local_datasource.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/college/data/anti_corruption/college_mapper.dart';
import 'package:smarter_jxufe/features/college/data/datasources/college_remote_datasource.dart';

class CollegeRepository {
  final CollegeLocalDataSource _localDataSource;
  final CollegeRemoteDataSource _remoteDataSource;

  final CollegeFilter _collegeFilter;
  final CollegeMapper _collegeMapper;

  CollegeRepository({
    required CollegeLocalDataSource localDataSource,
    required CollegeRemoteDataSource remoteDataSource,
    required CollegeFilter collegeFilter,
    required CollegeMapper collegeMapper,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _collegeFilter = collegeFilter,
       _collegeMapper = collegeMapper;

  Future<Either<Failure, List<College>>> getAllCollege({
    bool forceRefresh = false,
  }) async {
    try {
      final cacheColleges = _localDataSource.getAllCollege();

      final needRefresh = forceRefresh || cacheColleges.isEmpty;
      if (!needRefresh) return Right(cacheColleges);

      final apiColleges = await _remoteDataSource.getAllCollege();
      final filteredApiColleges = _collegeFilter.distinctByName(apiColleges);

      if (filteredApiColleges.length != apiColleges.length) {
        return Left(SyncFailure('有重复的专业名称'));
      }

      final colleges = _collegeMapper.fromApiList(filteredApiColleges);
      await _localDataSource.saveCollegeList(colleges);

      return Right(colleges);
    } catch (e) {
      return Left(SyncFailure('同步失败: $e'));
    }
  }
}
