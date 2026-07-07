import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/anti_corruption/graduation_requirements_html_parser.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/datasources/graduation_requirements_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/graduation_requirement.dart';

class GraduationRequirementsRepository {
  final GraduationRequirementsRemoteDataSource _remoteDataSource;
  final GraduationRequirementsHtmlParser _htmlParser;
  final ImsAuthRepository _imsAuthRepo;

  GraduationRequirementsRepository({
    required GraduationRequirementsRemoteDataSource remoteDataSource,
    required GraduationRequirementsHtmlParser htmlParser,
    required ImsAuthRepository imsAuthRepo,
  }) : _remoteDataSource = remoteDataSource,
       _htmlParser = htmlParser,
       _imsAuthRepo = imsAuthRepo;

  /// 获取毕业学分要求。
  Future<Either<Failure, List<GraduationRequirement>>>
  getGraduationRequirements() async {
    try {
      final jsessionResult = await _imsAuthRepo.getJsessionId();
      if (jsessionResult.isLeft()) {
        return Left(
          jsessionResult.swap().getOrElse(() => UnknownFailure('??')),
        );
      }
      final jsessionId = jsessionResult.getOrElse(() => '');
      if (jsessionId == null || jsessionId.isEmpty) {
        return Left(UnknownFailure('JSESSIONID 为空'));
      }

      final html = await _remoteDataSource.fetchGraduationRequirementsHtml(
        jsessionId: jsessionId,
      );

      final requirements = _htmlParser.parseHtml(html);
      return Right(requirements);
    } catch (e) {
      return Left(SyncFailure('获取毕业学分要求失败: $e'));
    }
  }
}
