import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/college/data/college_repository.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/college_mapper_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_college_remote_datasource_provider.dart';

part 'college_repository_provider.g.dart';

@riverpod
CollegeRepository collegeRepository(CollegeRepositoryRef ref) {
  final collegeLocal = ref.watch(collegeLocalDataSourceProvider);
  final curriculumRemote = ref.watch(curriculumCollegeRemoteDataSourceProvider);
  final collegeMapper = ref.watch(collegeMapperProvider);

  return CollegeRepository(
    local: collegeLocal,
    curriculumRemote: curriculumRemote,
    collegeMapper: collegeMapper,
  );
}
