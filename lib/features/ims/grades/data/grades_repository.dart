import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/grades/data/anti_corruption/grades_html_parser.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/grades_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';

class GradesRepository {
  final GradesRemoteDataSource _remoteDataSource;
  final GradesHtmlParser _htmlParser;
  final ImsAuthRepository _imsAuthRepo;

  GradesRepository({
    required GradesRemoteDataSource remoteDataSource,
    required GradesHtmlParser htmlParser,
    required ImsAuthRepository imsAuthRepo,
  }) : _remoteDataSource = remoteDataSource,
       _htmlParser = htmlParser,
       _imsAuthRepo = imsAuthRepo;

  Future<Either<Failure, GradesResult>> getGrades(
    GradesQueryParams params,
  ) async {
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

      return await _fetchWithRetry(jsessionId, params);
    } catch (e) {
      return Left(SyncFailure('获取成绩失败: $e'));
    }
  }

  Future<Either<Failure, GradesResult>> _fetchWithRetry(
    String jsessionId,
    GradesQueryParams params,
  ) async {
    try {
      final html = await _remoteDataSource.fetchGradesHtml(
        jsessionId: jsessionId,
        params: params,
      );
      final result = _htmlParser.parseHtml(html);
      return Right(result);
    } catch (e) {
      if (e.toString().contains('凭证已失效')) {
        // 刷新 JSESSIONID 并重试一次
        final refreshResult = await _imsAuthRepo.getJsessionId(
          forceRefresh: true,
        );
        if (refreshResult.isLeft()) {
          return Left(InvalidCredentialsFailure('凭证已失效，请重新登录!'));
        }
        final newJsessionId = refreshResult.getOrElse(() => '');
        if (newJsessionId == null || newJsessionId.isEmpty) {
          return Left(InvalidCredentialsFailure('凭证已失效，请重新登录!'));
        }

        try {
          final html = await _remoteDataSource.fetchGradesHtml(
            jsessionId: newJsessionId,
            params: params,
          );
          final result = _htmlParser.parseHtml(html);
          return Right(result);
        } catch (retryError) {
          if (retryError.toString().contains('凭证已失效')) {
            return Left(InvalidCredentialsFailure('凭证已失效，请重新登录!'));
          }
          return Left(SyncFailure('获取成绩失败: $retryError'));
        }
      }
      return Left(SyncFailure('获取成绩失败: $e'));
    }
  }
}
