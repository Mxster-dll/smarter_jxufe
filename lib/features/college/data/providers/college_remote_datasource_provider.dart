import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/college/data/datasources/college_remote_datasource.dart';

part 'college_remote_datasource_provider.g.dart';

@riverpod
CollegeRemoteDataSource collegeRemoteDataSource(
  CollegeRemoteDataSourceRef ref,
) {
  final dio = ref.watch(imsDioProvider);
  return CollegeRemoteDataSource(dio);
}
