import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/curriculum_html_parser.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/curriculum_mapper.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/exception/college_not_found_failure.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/exception/major_not_found_failure.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_key.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class CurriculumRepository {
  final CurriculumLocalDataSource _localDataSource;
  final CurriculumRemoteDataSource _remoteDataSource;
  final CurriculumHtmlParser _htmlParser;
  final CurriculumMapper _curriculumMapper;

  CurriculumRepository({
    required CurriculumLocalDataSource localDataSource,
    required CurriculumRemoteDataSource remoteDataSource,
    required CurriculumHtmlParser htmlParser,
    required CurriculumMapper curriculumMapper,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _htmlParser = htmlParser,
       _curriculumMapper = curriculumMapper;

  Future<Either<Failure, Curriculum>> getCurriculum(
    int year,
    College college,
    Major major, {
    bool forceRefresh = false,
  }) async {
    try {
      final collegeId = college.functionIdIn[FunctionType.curriculum];
      if (collegeId == null) {
        return Left(CollegeNotFoundFailure('没有找到该学院'));
      }

      final majorId = major.functionIdIn[FunctionType.curriculum];
      if (majorId == null) {
        return Left(MajorNotFoundFailure('没有找到该专业'));
      }

      CurriculumKey key = CurriculumKey(
        year: year,
        collegeId: collegeId,
        majorId: majorId,
      );

      if (!forceRefresh) {
        final curriculum = _localDataSource.getCurriculumByKey(key);
        if (curriculum != null) return Right(curriculum);
      }

      final html = await _remoteDataSource.getCurriculumHtmlByKey(key);
      final matrix = _htmlParser.parse(html);
      final courses = _curriculumMapper.fromRows(matrix);
      final curriculum = Curriculum(
        year: year,
        collegeId: college.uuid,
        majorId: major.uuid,
        courses: courses,
      );
      _localDataSource.saveCurriculumByKey(key, curriculum);

      return Right(curriculum);
    } catch (e) {
      return Left(SyncFailure('TODO getCurriculum失败: $e'));
    }
  }
}
