import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/datasources/student_info_remote_datasource.dart';

part 'student_info_remote_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
StudentInfoRemoteDataSource studentInfoRemoteDataSource(
  StudentInfoRemoteDataSourceRef ref,
) {
  final dio = ref.watch(imsDioProvider);

  return StudentInfoRemoteDataSource(dio);
}
