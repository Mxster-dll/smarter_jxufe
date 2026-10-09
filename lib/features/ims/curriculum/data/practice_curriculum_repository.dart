import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/practice_curriculum_html_parser.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/practice_curriculum_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/practice_curriculum_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

/// 实践环节仓库：**缓存优先**（命中本地不发网络），与 [CurriculumRepository] 同形。
class PracticeCurriculumRepository {
  final PracticeCurriculumLocalDataSource _localDataSource;
  final PracticeCurriculumRemoteDataSource _remoteDataSource;
  final PracticeCurriculumHtmlParser _htmlParser;
  final ImsAuthRepository _imsAuthRepo;

  PracticeCurriculumRepository({
    required PracticeCurriculumLocalDataSource localDataSource,
    required PracticeCurriculumRemoteDataSource remoteDataSource,
    required PracticeCurriculumHtmlParser htmlParser,
    required ImsAuthRepository imsAuthRepo,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _htmlParser = htmlParser,
       _imsAuthRepo = imsAuthRepo;

  Future<Either<Failure, PracticeCurriculum>> getPracticeCurriculumIn(
    int year,
    College college,
    Major major, {
    bool forceRefresh = false,
  }) async {
    try {
      final cached = _localDataSource.get(year, college.name, major.name);
      if (!forceRefresh && cached != null) return Right(cached);

      final jsessionResult = await _imsAuthRepo.getJsessionId();
      if (jsessionResult.isLeft()) {
        return Left(
          UnknownFailure(
            '获取JSESSIONID失败: ${jsessionResult.swap().getOrElse(() => UnknownFailure('??')).message}',
          ),
        );
      }
      final jsessionId = jsessionResult.getOrElse(() => '');

      final html = await _remoteDataSource.getPracticeCurriculumHtml(
        year,
        college.code,
        major.code,
        jsessionId: jsessionId ?? '',
      );
      final stages = _htmlParser.parseHtml(html);
      final curriculum = PracticeCurriculum(
        year: year,
        collegeName: college.name,
        majorName: major.name,
        stages: stages,
        lastUpdated: DateTime.now(),
      );
      await _localDataSource.save(
        year: year,
        collegeName: college.name,
        majorName: major.name,
        curriculum: curriculum,
      );
      return Right(curriculum);
    } catch (e) {
      return Left(SyncFailure('获取实践环节培养方案失败: $e'));
    }
  }
}
