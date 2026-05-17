import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/major/data/major_mapper.dart';
import 'package:smarter_jxufe/features/major/data/datasources/major_remote_datasource.dart';
import 'package:smarter_jxufe/features/major/data/datasources/major_local_datasource.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class MajorRepository {
  final MajorLocalDataSource _localDataSource;
  final MajorRemoteDataSource _remoteDataSource;
  final MajorMapper _majorMapper;

  MajorRepository({
    required MajorLocalDataSource localDataSource,
    required MajorRemoteDataSource remoteDataSource,
    required MajorMapper majorMapper,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _majorMapper = majorMapper;

  Future<Either<Failure, List<Major>>> getAllMajorIn(
    College college, {
    required int year,
    bool forceRefresh = false,
  }) async {
    try {
      final cacheMajors = _localDataSource.getAllMajorIn(
        college.name,
        year: year,
      );

      final needRefresh = forceRefresh || cacheMajors.isEmpty;
      if (!needRefresh) return Right(cacheMajors);

      final apiMajors = await _remoteDataSource.getMajorList(
        year,
        college.code,
      );

      final majors = _majorMapper.fromApiList(
        apiMajors,
        year: year,
        college: college,
      );

      return Right(majors);
    } catch (e) {
      return Left(SyncFailure('专业列表获取失败: $e'));
    }
  }
}
