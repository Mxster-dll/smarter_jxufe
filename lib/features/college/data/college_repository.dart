import 'package:dartz/dartz.dart';
import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/multiple_match_failure.dart';
import 'package:smarter_jxufe/core/exception/no_match_failure.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/college/data/college_local_datasource.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/college/domain/college_default_aliases.dart';
import 'package:smarter_jxufe/features/college/domain/college_name_normalizer.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/college_mapper.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_college_remote_datasource.dart';

class CollegeRepository {
  static final List<String> _whitelist = CollegeDefaultAliases
      .defaultAliases
      .keys
      .toList();

  final CollegeLocalDataSource _local;
  final CurriculumCollegeRemoteDataSource _curriculumRemote;
  final CollegeMapper _collegeMapper;

  CollegeRepository({
    required CollegeLocalDataSource local,
    required CurriculumCollegeRemoteDataSource curriculumRemote,
    required CollegeMapper collegeMapper,
  }) : _local = local,
       _curriculumRemote = curriculumRemote,
       _collegeMapper = collegeMapper;

  Future<Either<Failure, void>> syncFromSystem(
    FunctionType function, {
    required int year,
  }) async {
    try {
      final apiColleges = await switch (function) {
        .curriculum => _curriculumRemote.getCollegeList(),
      };

      final functionColleges = apiColleges.map(_collegeMapper.fromApi).toList();

      for (final functionCollege in functionColleges) {
        final matchList = _local.findCollegeKnownAs(functionCollege.name);
        if (matchList.length > 1) {
          return Left(
            MultipleMatchFailure(
              '名称为 "${functionCollege.name}" 的学院不唯一: $matchList',
            ),
          );
        }

        if (matchList.isEmpty) {
          final standardName = CollegeNameNormalizer.normalize(
            functionCollege.name,
          );
          if (!_whitelist.contains(standardName)) {
            return Left(
              NoMatchFailure('没有找到名称为 "${functionCollege.name}" 的学院'),
            );
          }
          await createCollege(
            functionCollege.name,
            functionIds: {function: functionCollege.code},
            year: year,
          );
        } else {
          final college = matchList.first;
          college.functionIdIn[function] = functionCollege.code;
          await _local.saveCollege(college, year: year);
        }
      }

      return Right(null);
    } catch (e) {
      return Left(SyncFailure('学院同步失败: $e'));
    }
  }

  Future<Either<Failure, List<College>>> getCollegeListIn(
    FunctionType function, {
    required int year,
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh) {
        final cache = _local.getCollegeListIn(function, year: year);
        if (cache != null) return Right(cache);
      }

      final syncResult = await syncFromSystem(function, year: year);
      return syncResult.fold(
        Left.new,
        (success) => Right(_local.getCollegeListIn(function, year: year) ?? []),
      );
    } catch (e) {
      return Left(SyncFailure('同步失败: $e'));
    }
  }

  Future<void> createCollege(
    String standardName, {
    Map<FunctionType, String>? functionIds,
    required int year,
  }) async {
    const maxAttempts = 5;
    for (int i = 0; i < maxAttempts; i++) {
      final uuid = Uuid().v4();
      if (!_local.contains(uuid)) {
        final major = College(uuid, standardName, functionIdIn: functionIds);
        await _local.saveCollege(major, year: year);
      }
    }

    throw Exception('生成 Uuid 失败，超过最大重试次数');
  }
}
