import 'package:dartz/dartz.dart';

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
import 'package:uuid/uuid.dart';

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

  Future<Either<Failure, void>> syncFromSystem(FunctionType function) async {
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
          await createCollege(functionCollege.name, {
            function: functionCollege.code,
          });
        } else {
          final college = matchList.first;
          college.functionIdIn[function] = functionCollege.code;
          await _local.saveCollege(college);
        }
      }

      return Right(null);
    } catch (e) {
      return Left(SyncFailure('学院同步失败: $e'));
    }
  }

  Future<Either<Failure, List<College>>> getCollegeListIn(
    FunctionType function, {
    bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh) return Right(_local.getCollegeList());

      final syncResult = await syncFromSystem(function);
      return syncResult.fold(
        Left.new,
        (success) => Right(_local.getCollegeList()),
      );
    } catch (e) {
      return Left(SyncFailure('同步失败: $e'));
    }
  }

  Future<void> createCollege(
    String standardName, [
    Map<FunctionType, String>? functionIds,
  ]) {
    College college = College(
      newUuid(),
      standardName,
      functionIdIn: functionIds,
    );
    return _local.saveCollege(college);
  }

  String newUuid() {
    while (true) {
      String uuid = Uuid().v4();
      if (!_local.contains(uuid)) return uuid;
    }
  }
}
