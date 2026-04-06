import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/multiple_match_failure.dart';
import 'package:smarter_jxufe/core/exception/no_match_failure.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/major_mapper.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_major_remote_datasource.dart';
import 'package:smarter_jxufe/features/major/data/major_local_datasource.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';
import 'package:uuid/uuid.dart';

class MajorRepository {
  final MajorLocalDataSource _local;
  final CurriculumMajorRemoteDataSource _curriculumRemote;
  final MajorMapper _majorMapper;

  MajorRepository({
    required MajorLocalDataSource local,
    required CurriculumMajorRemoteDataSource curriculumRemote,
    required MajorMapper majorMapper,
  }) : _local = local,
       _curriculumRemote = curriculumRemote,
       _majorMapper = majorMapper;

  Future<Either<Failure, void>> syncFromSystem(
    FunctionType function, {
    required int year,
    required String collegeId,
  }) async {
    try {
      final apiMajors = await switch (function) {
        .curriculum => _curriculumRemote.getMajorList(year, collegeId),
      };

      final functionMajors = apiMajors.map(_majorMapper.fromApi).toList();

      for (final functionMajor in functionMajors) {
        final matchList = _local.findMajorKnownAs(functionMajor.name);
        if (matchList.length > 1) {
          return Left(
            MultipleMatchFailure(
              '名称为 "${functionMajor.name}" 的专业不唯一: $matchList',
            ),
          );
        }

        if (matchList.isEmpty) {
          // if (!_whitelist.contains(functionMajor.name)) {
          //   return Left(
          //     NoMatchFailure('没有找到名称为 "${functionCollege.name}" 的学院'),
          //   );
          // }
          await createMajor(functionMajor.name, {function: functionMajor.code});
        } else {
          final major = matchList.first;
          major.functionIdIn[function] = functionMajor.code;
          await _local.saveMajor(major);
        }
      }

      return Right(null);
    } catch (e) {
      return Left(SyncFailure('专业同步失败: $e'));
    }
  }

  Future<Either<Failure, List<Major>>> getMajorListIn(
    int year,
    College college,
    FunctionType function, {
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh) return Right(_local.getMajorList());

      final collegeId = college.functionIdIn[FunctionType.curriculum];
      if (collegeId == null) {
        return Left(NoMatchFailure('没有找到该学院'));
      }

      final syncResult = await syncFromSystem(
        function,
        year: year,
        collegeId: collegeId,
      );
      return syncResult.fold(
        Left.new,
        (success) => Right(_local.getMajorList()),
      );
    } catch (e) {
      return Left(SyncFailure('同步失败: $e'));
    }
  }

  Future<void> createMajor(
    String standardName, [
    Map<FunctionType, String>? functionIds,
  ]) {
    Major major = Major(newUuid(), standardName, functionIdIn: functionIds);
    return _local.saveMajor(major);
  }

  String newUuid() {
    while (true) {
      String uuid = Uuid().v4();
      if (!_local.contains(uuid)) return uuid;
    }
  }
}
