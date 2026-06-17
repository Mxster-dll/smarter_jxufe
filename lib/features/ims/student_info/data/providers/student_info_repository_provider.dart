import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod/riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/anti_corruption/student_info_mapper.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/datasources/student_info_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/datasources/student_info_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/student_info_repository.dart';

/// Hive Box 用于学生信息缓存。
final studentInfoBoxProvider = FutureProvider<Box<String>>((ref) {
  return Hive.openBox<String>('studentInfo');
});

/// 本地数据源。
final studentInfoLocalDataSourceProvider =
    FutureProvider<StudentInfoLocalDataSource>((ref) async {
      final box = await ref.watch(studentInfoBoxProvider.future);
      return StudentInfoLocalDataSource(box);
    });

/// 远程数据源（使用 imsDio）。
final studentInfoRemoteDataSourceProvider =
    Provider<StudentInfoRemoteDataSource>((ref) {
      final dio = ref.watch(imsDioProvider);
      return StudentInfoRemoteDataSource(dio);
    });

/// 映射器。
final studentInfoMapperProvider = Provider<StudentInfoMapper>((ref) {
  return StudentInfoMapper();
});

/// 学生信息仓库。
final studentInfoRepositoryProvider = FutureProvider<StudentInfoRepository>((
  ref,
) async {
  final localDataSource = await ref.watch(
    studentInfoLocalDataSourceProvider.future,
  );
  final remoteDataSource = ref.watch(studentInfoRemoteDataSourceProvider);
  final mapper = ref.watch(studentInfoMapperProvider);
  final imsAuthRepo = await ref.watch(imsAuthRepositoryProvider.future);

  return StudentInfoRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    mapper: mapper,
    imsAuthRepo: imsAuthRepo,
  );
});
