import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_college_remote_datasource.dart';

part 'curriculum_college_remote_datasource_provider.g.dart';

@riverpod
CurriculumCollegeRemoteDataSource curriculumCollegeRemoteDataSource(
  CurriculumCollegeRemoteDataSourceRef ref,
) {
  final dio = ref.watch(imsDioProvider);
  return CurriculumCollegeRemoteDataSource(dio);
}
