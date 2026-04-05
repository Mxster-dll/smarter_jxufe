import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/datasources/repositories/curriculum_college_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/college_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/college_remote_datasource_provider.dart';

part 'curriculum_college_repository_provider.g.dart';

@riverpod
CurriculumCollegeRepository curriculumCollegeRepository(
  CurriculumCollegeRepositoryRef ref,
) {
  final localDataSource = ref.watch(collegeLocalDataSourceProvider);
  final remoteDataSource = ref.watch(collegeRemoteDataSourceProvider);

  return CurriculumCollegeRepository(
    remoteDataSource: remoteDataSource,
    localDataSource: localDataSource,
  );
}
