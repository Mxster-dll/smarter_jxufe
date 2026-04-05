import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_college.dart';
import 'package:smarter_jxufe/features/major/data/datasources/major_local_datasource.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';
import 'package:smarter_jxufe/features/major/domain/unified_major.dart';
import 'package:uuid/uuid.dart';

class MajorRepository {
  final MajorLocalDataSource _local;
  final CurriculumRemoteDataSource _curriculumRemote;
  // final ScheduleRemoteDataSource _scheduleRemote;
  // ... 其他系统数据源

  MajorRepository({
    required MajorLocalDataSource local,
    required CurriculumRemoteDataSource curriculumRemote,
    // required ScheduleRemoteDataSource scheduleRemote,
    // ...
  }) : _local = local,
       _curriculumRemote = curriculumRemote;

  /// 获取专业列表（返回 RawMajor）
  // Future<Either<Failure, List<RawMajor>>> getMajors(
  //   int year,
  //   String collegeCode, {
  //   bool forceRefresh = false,
  // }) async {
  //   final key = '$_majorsKeyPrefix$year$collegeCode';

  //   if (!forceRefresh) {
  //     final cached = _majorBox.get(key);
  //     if (cached != null) {
  //       return Right(cached as List<RawMajor>);
  //     }
  //   }

  //   try {
  //     final apiMajors = await _remoteDataSource.getMajorList(year, collegeCode);
  //     final rawMajors = _majorMapper.fromApiList(apiMajors);
  //     await _majorBox.put(key, rawMajors);
  //     return Right(rawMajors);
  //   } catch (e) {
  //     return Left(NetworkFailure('获取专业列表失败'));
  //   }
  // }

  /// 获取某个系统下的学院列表（返回统一学院列表，如果未映射则自动创建临时映射）
  Future<Either<Failure, List<UnifiedMajor>>> getMajorListIn(
    FunctionType function, {
    required int year,
    required CurriculumCollege college,
    bool forceRefresh = false,
  }) async {
    try {
      final apiMajors = await _fetchApiMajorsIn(function, year, college);

      // 2. 将原始学院转换为统一学院（建立或更新映射）
      final unifiedList = <UnifiedMajor>[];
      for (final raw in apiMajors) {
        // 尝试根据系统ID查找已存在的统一学院
        var unified = _local.findBySystemId(function, raw.id);
        if (unified == null) {
          // 若不存在，创建新的统一学院（使用 UUID，并填充名称）
          unified = UnifiedMajor(
            uuid: Uuid().v4(),
            name: raw.name,
            modelIn: {function: raw.id},
          );
        } else {
          // 若已存在，更新名称和系统ID（以防名称变化）
          unified = unified.copyWith(
            name: raw.name,
            modelIn: {...unified.modelIn, function: raw.id},
          );
        }
        await _local.saveMajor(unified);
        unifiedList.add(unified);
      }
      return Right(unifiedList);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  /// 根据一个系统的学院ID，获取目标系统的学院ID
  // String? getSystemIdForMajor(
  //   String unifiedMajorId,
  //   FunctionType targetSystem,
  // ) {
  //   final major = _local.getMajorById(unifiedMajorId);
  //   return major?.systemIds[targetSystem.name];
  // }

  // 辅助：调用对应系统的远程数据源获取原始学院列表
  Future<List<Major>> _fetchApiMajorsIn(
    FunctionType function,
    int year,
    CurriculumCollege college,
  ) async => switch (function) {
    .curriculum => await _curriculumRemote.getMajorList(year, college),
  };
}
