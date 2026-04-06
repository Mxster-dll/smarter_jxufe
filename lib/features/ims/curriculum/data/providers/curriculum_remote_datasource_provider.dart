import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/major_mapper_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/curriculum_remote_datasource.dart';

part 'curriculum_remote_datasource_provider.g.dart';

@riverpod
CurriculumRemoteDataSource curriculumRemoteDataSource(
  CurriculumRemoteDataSourceRef ref,
) {
  final dio = ref.watch(imsDioProvider);
  final majorMapper = ref.watch(majorMapperProvider);

  return CurriculumRemoteDataSource(dio: dio, majorMapper: majorMapper);
}
