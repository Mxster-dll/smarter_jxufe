import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_major_remote_datasource.dart';

part 'curriculum_major_remote_datasource_provider.g.dart';

@riverpod
CurriculumMajorRemoteDataSource curriculumMajorRemoteDataSource(
  CurriculumMajorRemoteDataSourceRef ref,
) {
  final dio = ref.watch(imsDioProvider);
  return CurriculumMajorRemoteDataSource(dio);
}
