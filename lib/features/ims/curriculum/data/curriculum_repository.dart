import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/curriculum_html_parser.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/curriculum_mapper.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_key.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class CurriculumRepository {
  final CurriculumLocalDataSource _localDataSource;
  final CurriculumRemoteDataSource _remoteDataSource;
  final CurriculumHtmlParser _htmlParser;
  final CurriculumMapper _curriculumMapper;
  final ImsAuthRepository _imsAuthRepo;

  CurriculumRepository({
    required CurriculumLocalDataSource localDataSource,
    required CurriculumRemoteDataSource remoteDataSource,
    required CurriculumHtmlParser htmlParser,
    required CurriculumMapper curriculumMapper,
    required ImsAuthRepository imsAuthRepo,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _htmlParser = htmlParser,
       _curriculumMapper = curriculumMapper,
       _imsAuthRepo = imsAuthRepo;

  Future<Either<Failure, Curriculum>> getCurriculumIn(
    int year,
    College college,
    Major major, {
    bool forceRefresh = false,
  }) async {
    try {
      CurriculumKey key = CurriculumKey(
        year: year,
        college: college,
        major: major,
      );

      final cacheCurriculum = _localDataSource.getCurriculumByKey(key);

      final needRefresh = forceRefresh || cacheCurriculum == null;
      if (!needRefresh) return Right(cacheCurriculum);

      final result = await _imsAuthRepo.getJsessionId();

      return result.fold(
        (error) => Left(UnknownFailure('获取JSESSIONID失败: $error')),
        (jsessionId) async {
          final html = await _remoteDataSource.getCurriculumHtmlByKey(
            key,
            jsessionId: jsessionId ?? '',
          );
          final matrix = _htmlParser.parse(html);
          final courses = _curriculumMapper.fromRows(matrix);
          final curriculum = Curriculum(
            year: year,
            collegeName: college.name,
            majorName: major.name,
            courses: courses,
          );

          _localDataSource.saveCurriculumByKey(key, curriculum);

          return Right(curriculum);
        },
      );
    } catch (e) {
      return Left(SyncFailure('获取培养方案失败: $e'));
    }
  }
}
