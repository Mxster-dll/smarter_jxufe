import 'package:collection/collection.dart';
import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/college/domain/unified_college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/college_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/college_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_college.dart';

class CurriculumCollegeRepository {
  final CollegeLocalDataSource _localDataSource;
  final CollegeRemoteDataSource _remoteDataSource;

  CurriculumCollegeRepository({
    required CollegeLocalDataSource localDataSource,
    required CollegeRemoteDataSource remoteDataSource,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource;

  Future<Either<Failure, List<CurriculumCollege>>> syncAll() async {
    try {
      final colleges = await _remoteDataSource.getCollegeList();
      await Future.wait(colleges.map(_localDataSource.saveCollege));

      return Right(colleges);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, CurriculumCollege>> getCollegeById(
    String id, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cache = _localDataSource.getCollegeById(id);
      if (cache != null) return Right(cache);
    }

    try {
      final updateResult = await syncAll();
      return updateResult.fold(Left.new, (colleges) {
        final found = colleges.firstWhereOrNull((c) => c.code == id);
        if (found == null) return Left(NotFoundFailure("不存在的id: $id"));

        return Right(found);
      });
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, CurriculumCollege>> adaptFrom(
    UnifiedCollege college, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final id = college.functionIds[FunctionType.curriculum];
      if (id != null) {
        final result = await getCollegeById(id);
        if (result.isRight()) return result;
      }
    }

    await syncAll();

    final id = college.functionIds[FunctionType.curriculum];
    if (id == null) return Left(MappingFailure('该学院无对应id'));

    return getCollegeById(id);
  }
}
