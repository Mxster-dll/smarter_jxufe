import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/grades/data/anti_corruption/grades_html_parser.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/grades_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/grades_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_query_params.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_result.dart';

class GradesRepository {
  final GradesRemoteDataSource _remoteDataSource;
  final GradesHtmlParser _htmlParser;
  final ImsAuthRepository _imsAuthRepo;
  final GradesLocalDataSource _localDataSource;

  GradesRepository({
    required GradesRemoteDataSource remoteDataSource,
    required GradesHtmlParser htmlParser,
    required ImsAuthRepository imsAuthRepo,
    required GradesLocalDataSource localDataSource,
  }) : _remoteDataSource = remoteDataSource,
       _htmlParser = htmlParser,
       _imsAuthRepo = imsAuthRepo,
       _localDataSource = localDataSource;

  /// 获取成绩：优先返回缓存，若 [forceRefresh] 为 true 或缓存为空则从远程拉取。
  /// 远程拉取时会与本地缓存比对，若有新增/减少的课程会在 [GradesResult] 中携带 diff 信息。
  Future<Either<Failure, GradesResult>> getGrades(
    GradesQueryParams params, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _localDataSource.getCachedGrades(params);
      if (cached != null) return Right(cached);
    }

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

      final remoteResult = await _fetchWithRetry(jsessionId, params);
      return remoteResult.fold((failure) => Left(failure), (fresh) async {
        // 与本地缓存比对变更
        final cached = _localDataSource.getCachedGrades(params);
        List<String>? added, removed;
        if (cached != null) {
          final oldNames = cached.grades.map((g) => g.courseName).toSet();
          final newNames = fresh.grades.map((g) => g.courseName).toSet();
          added = newNames.difference(oldNames).toList();
          removed = oldNames.difference(newNames).toList();
        }
        // 存入缓存（不带 diff 信息）
        await _localDataSource.saveGrades(params, fresh);
        return Right(
          GradesResult(
            grades: fresh.grades,
            newCourseNames: added,
            removedCourseNames: removed,
          ),
        );
      });
    } catch (e) {
      return Left(SyncFailure('获取成绩失败: $e'));
    }
  }

  /// 清除所有成绩缓存。
  Future<void> clearCache() => _localDataSource.clearAll();

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
