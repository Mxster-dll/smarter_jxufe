import 'package:dartz/dartz.dart';
import 'package:smarter_jxufe/core/exception/no_match_failure.dart';
import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/multiple_match_failure.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/major_mapper.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_major_remote_datasource.dart';
import 'package:smarter_jxufe/features/major/data/major_local_datasource.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

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

  Future<Either<Failure, void>> _syncFromSystem(
    FunctionType function, {
    required int year,
    required College college,
  }) async {
    try {
      final systemId = college.functionIdIn[FunctionType.curriculum];
      if (systemId == null) {
        return Left(NoMatchFailure('没有找到该学院'));
      }

      final apiMajors = await switch (function) {
        .curriculum => _curriculumRemote.getMajorList(year, systemId),
      };

      final functionMajors = apiMajors.map(_majorMapper.fromApi).toList();

      for (final functionMajor in functionMajors) {
        final matchList = _local.findMajorKnownAs(functionMajor.name);
        // if (matchList.length > 1) {
        //   return Left(
        //     MultipleMatchFailure(
        //       '名称为 "${functionMajor.name}" 的专业不唯一: $matchList',
        //     ),
        //   );
        // }

        if (matchList.isEmpty) {
          await _createMajor(
            functionMajor.name,
            functionIds: {function: functionMajor.code},
            year: year,
            college: college,
          );
        } else {
          final major = matchList.first;
          major.functionIdIn[function] = functionMajor.code;
          await _local.saveMajor(major, year: year, collegeId: systemId);
        }
      }

      return Right(null);
    } catch (e) {
      return Left(SyncFailure('专业同步失败: $e'));
    }
  }

  Future<Either<Failure, List<Major>>> getMajorListIn(
    FunctionType function, {
    required int year,
    required College college,
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh) {
        final cache = _local.getMajorListIn(
          function,
          year: year,
          collegeId: college.uuid,
        );
        if (cache != null) return Right(cache);
      }

      final systemId = college.functionIdIn[FunctionType.curriculum];
      if (systemId == null) {
        return Left(NoMatchFailure('没有找到该学院'));
      }

      final syncResult = await _syncFromSystem(
        function,
        year: year,
        college: college,
      );
      return syncResult.fold(
        Left.new,
        (success) => Right(
          _local.getMajorListIn(
                function,
                year: year,
                collegeId: college.uuid,
              ) ??
              [],
        ),
      );
    } catch (e) {
      return Left(SyncFailure('同步失败: $e'));
    }
  }

  Future<void> _createMajor(
    String standardName, {
    Map<FunctionType, String>? functionIds,
    required int year,
    required College college,
  }) {
    const maxAttempts = 5;
    for (int i = 0; i < maxAttempts; i++) {
      final uuid = Uuid().v4();
      if (!_local.contains(uuid)) {
        final major = Major(uuid, standardName, functionIdIn: functionIds);
        return _local.saveMajor(major, year: year, collegeId: college.uuid);
      }
    }

    throw Exception('生成 Uuid 失败，超过最大重试次数');
  }
}
