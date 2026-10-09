import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/curriculum_html_parser.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/anti_corruption/curriculum_mapper.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_terms_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_key.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_terms.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class CurriculumRepository {
  final CurriculumLocalDataSource _localDataSource;
  final CurriculumRemoteDataSource _remoteDataSource;
  final CurriculumTermsLocalDataSource _termsLocalDataSource;
  final CurriculumHtmlParser _htmlParser;
  final CurriculumMapper _curriculumMapper;
  final ImsAuthRepository _imsAuthRepo;

  CurriculumRepository({
    required CurriculumLocalDataSource localDataSource,
    required CurriculumRemoteDataSource remoteDataSource,
    required CurriculumTermsLocalDataSource termsLocalDataSource,
    required CurriculumHtmlParser htmlParser,
    required CurriculumMapper curriculumMapper,
    required ImsAuthRepository imsAuthRepo,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _termsLocalDataSource = termsLocalDataSource,
       _htmlParser = htmlParser,
       _curriculumMapper = curriculumMapper,
       _imsAuthRepo = imsAuthRepo;

  /// 理论课程（**缓存优先**：命中本地缓存不发网络，离线可用）。
  ///
  /// 真去抓表时，会把这张表的**开课学期**（第 2 列 `学年学期`）一并落到侧表 ——
  /// 两者同源，必须同批写，见 [getCourseSemestersIn] 的对齐判据。
  Future<Either<Failure, Curriculum>> getCurriculumIn(
    int year,
    College college,
    Major major, {
    bool forceRefresh = false,
  }) async {
    try {
      final key = CurriculumKey(year: year, college: college, major: major);

      final cacheCurriculum = _localDataSource.getCurriculumByKey(key);
      if (!forceRefresh && cacheCurriculum != null) return Right(cacheCurriculum);

      final fetched = await _fetch(key);
      return fetched.fold((failure) => Left(failure), (r) => Right(r.curriculum));
    } catch (e) {
      return Left(SyncFailure('获取培养方案失败: $e'));
    }
  }

  /// 理论课程每一门的**开课学期**（`学年学期` 原文，与课程同序）。
  ///
  /// - 侧表命中且与课程表**条数对齐** → 直接返回（不发网络）；
  /// - 侧表缺失 / 对不上（2026-10 之前的老缓存没有侧表）→ 重抓一次表，两张表一起刷新；
  /// - 抓不到（没会话 / 网络失败）→ `Left`，调用方按「开课学期没取到」如实提示，
  ///   **不要**退化成空学期列表去冒充「都没排定」。
  Future<Either<Failure, List<String>>> getCourseSemestersIn(
    int year,
    College college,
    Major major, {
    bool forceRefresh = false,
  }) async {
    try {
      final key = CurriculumKey(year: year, college: college, major: major);

      final cached = _alignedCachedTerms(key);
      if (!forceRefresh && cached != null) return Right(cached.semesters);

      final fetched = await _fetch(key);
      return fetched.fold((failure) => Left(failure), (r) => Right(r.terms.semesters));
    } catch (e) {
      return Left(SyncFailure('获取开课学期失败: $e'));
    }
  }

  /// 缓存里的侧表，且**必须与课程表条数一致**才算数 —— 对不上宁可当作没取到，
  /// 也不能把学期错配到别的课上（见 `curriculum_terms.dart` 的对齐口径）。
  CurriculumTerms? _alignedCachedTerms(CurriculumKey key) {
    final terms = _termsLocalDataSource.get(
      key.year,
      key.college.name,
      key.major.name,
    );
    if (terms == null) return null;
    final courses = _localDataSource.getCurriculumByKey(key);
    if (courses == null) return terms;
    return terms.alignsWith(courses.courses.length) ? terms : null;
  }

  /// 抓一次「查看教学计划表」，解析出课程与开课学期并**一起落盘**。
  Future<Either<Failure, ({Curriculum curriculum, CurriculumTerms terms})>>
  _fetch(CurriculumKey key) async {
    final session = await _imsAuthRepo.getJsessionId();
    if (session.isLeft()) {
      return Left(
        UnknownFailure(
          '获取JSESSIONID失败: '
          '${session.swap().getOrElse(() => UnknownFailure('??')).message}',
        ),
      );
    }
    final jsessionId = session.getOrElse(() => '') ?? '';

    final html = await _remoteDataSource.getCurriculumHtmlByKey(
      key,
      jsessionId: jsessionId,
    );
    final matrix = _htmlParser.parse(html);
    final courses = _curriculumMapper.fromRows(matrix);
    final rawSemesters = _curriculumMapper.semestersFromRows(matrix);

    final curriculum = Curriculum(
      year: key.year,
      collegeName: key.college.name,
      majorName: key.major.name,
      courses: courses,
    );
    final terms = CurriculumTerms(
      year: key.year,
      collegeName: key.college.name,
      majorName: key.major.name,
      entries: [
        for (var i = 0; i < courses.length; i++)
          CurriculumTermEntry(
            code: courses[i].code,
            name: courses[i].name,
            semester: i < rawSemesters.length ? rawSemesters[i] : '',
          ),
      ],
      lastUpdated: DateTime.now(),
    );

    await _localDataSource.saveCurriculumByKey(key, curriculum);
    await _termsLocalDataSource.save(
      year: key.year,
      collegeName: key.college.name,
      majorName: key.major.name,
      terms: terms,
    );

    return Right((curriculum: curriculum, terms: terms));
  }
}
