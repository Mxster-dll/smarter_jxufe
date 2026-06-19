import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/grades_remote_datasource.dart';

part 'grades_remote_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
GradesRemoteDataSource gradesRemoteDataSource(GradesRemoteDataSourceRef ref) {
  final dio = ref.watch(currentImsDioProvider);

  return GradesRemoteDataSource(dio);
}
