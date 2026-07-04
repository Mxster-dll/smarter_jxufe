import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/grades_remote_datasource.dart';
// [DEBUG] 测试成绩变更提示时取消下行注释
// import 'package:smarter_jxufe/debug/fake_grades_remote_datasource.dart';

part 'grades_remote_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
GradesRemoteDataSource gradesRemoteDataSource(GradesRemoteDataSourceRef ref) {
  // [DEBUG] 测试成绩变更提示时取消下行注释
  //   return FakeGradesRemoteDataSource();

  final dio = ref.watch(currentImsDioProvider);
  return GradesRemoteDataSource(dio);
}
