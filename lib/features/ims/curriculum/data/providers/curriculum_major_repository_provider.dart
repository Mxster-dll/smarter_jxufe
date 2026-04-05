import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/repositories/curriculum_major_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/major_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/major_remote_datasource_provider.dart';

part 'curriculum_major_repository_provider.g.dart';

@riverpod
CurriculumMajorRepository curriculumMajorRepository(
  CurriculumMajorRepositoryRef ref,
) {
  final localDataSource = ref.watch(majorLocalDataSourceProvider);
  final remoteDataSource = ref.watch(majorRemoteDataSourceProvider);

  return CurriculumMajorRepository(
    remoteDataSource: remoteDataSource,
    localDataSource: localDataSource,
  );
}
