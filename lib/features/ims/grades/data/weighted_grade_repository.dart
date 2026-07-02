import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/grades/data/anti_corruption/weighted_grade_html_parser.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/weighted_grade_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/weighted_grade.dart';

class WeightedGradeRepository {
  final WeightedGradeRemoteDataSource _remoteDataSource;
  final WeightedGradeHtmlParser _htmlParser;
  final ImsAuthRepository _imsAuthRepo;

  WeightedGradeRepository({
    required WeightedGradeRemoteDataSource remoteDataSource,
    required WeightedGradeHtmlParser htmlParser,
    required ImsAuthRepository imsAuthRepo,
  }) : _remoteDataSource = remoteDataSource,
       _htmlParser = htmlParser,
       _imsAuthRepo = imsAuthRepo;

  /// [typeId] 加权类型：1=课程加权所有学年, 2=上学年, 3=上学期, 5=毕业加权, 6=辅修加权, 7=推免加权。
  Future<Either<Failure, WeightedGrade>> getWeightedGrade({
    required int typeId,
  }) async {
    try {
      final jsessionResult = await _imsAuthRepo.getJsessionId();
      if (jsessionResult.isLeft()) {
        return Left(
          jsessionResult.swap().getOrElse(() => UnknownFailure('??')),
        );
      }
      final jsessionId = jsessionResult.getOrElse(() => '') ?? '';
      if (jsessionId.isEmpty) {
        return Left(UnknownFailure('JSESSIONID 为空'));
      }

      final html = await _remoteDataSource.fetchWeightedGradeHtml(
        jsessionId: jsessionId,
        typeId: typeId,
      );
      final result = _htmlParser.parseHtml(html);
      return Right(result);
    } catch (e) {
      if (e.toString().contains('凭证已失效')) {
        return Left(InvalidCredentialsFailure('凭证已失效，请重新登录！'));
      }
      return Left(SyncFailure('获取排名失败: $e'));
    }
  }
}
