import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/exception/sync_failure.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/anti_corruption/student_info_mapper.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/anti_corruption/student_info_xml_parser.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/datasources/student_info_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/datasources/student_info_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';

class StudentInfoRepository {
  final StudentInfoLocalDataSource _localDataSource;
  final StudentInfoRemoteDataSource _remoteDataSource;
  final StudentInfoXmlParser _xmlParser;
  final StudentInfoMapper _mapper;
  final ImsAuthRepository _imsAuthRepo;

  StudentInfoRepository({
    required StudentInfoLocalDataSource localDataSource,
    required StudentInfoRemoteDataSource remoteDataSource,
    required StudentInfoXmlParser xmlParser,
    required StudentInfoMapper mapper,
    required ImsAuthRepository imsAuthRepo,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _xmlParser = xmlParser,
       _mapper = mapper,
       _imsAuthRepo = imsAuthRepo;

  Either<Failure, StudentInfo?> getCachedStudentInfo() {
    try {
      return Right(_localDataSource.getStudentInfo());
    } catch (e) {
      return Left(CacheFailure('读取学生信息缓存失败: $e'));
    }
  }

  Future<Either<Failure, StudentInfo>> _fetchAndSaveStudentInfo() async {
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

      final xml = await _remoteDataSource.fetchStudentInfoXml(
        jsessionId: jsessionId,
      );
      final parsed = _xmlParser.parse(xml);
      final info = _mapper.fromParsed(parsed);
      await _localDataSource.saveStudentInfo(info);
      return Right(info);
    } catch (e) {
      return Left(SyncFailure('获取学生信息失败: $e'));
    }
  }

  Future<Either<Failure, StudentInfo>> getStudentInfo({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _localDataSource.getStudentInfo();
      if (cached != null) return Right(cached);
    }

    return _fetchAndSaveStudentInfo();
  }

  Future<Either<Failure, void>> clearCache() async {
    try {
      await _localDataSource.clear();
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('清除学生信息缓存失败: $e'));
    }
  }
}
