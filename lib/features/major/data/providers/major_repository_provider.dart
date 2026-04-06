import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/major_mapper_provider.dart';

import 'package:smarter_jxufe/features/major/data/major_repository.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_major_remote_datasource_provider.dart';

part 'major_repository_provider.g.dart';

@riverpod
MajorRepository majorRepository(MajorRepositoryRef ref) {
  final majorLocal = ref.watch(majorLocalDataSourceProvider);
  final curriculumRemote = ref.watch(curriculumMajorRemoteDataSourceProvider);
  final majorMapper = ref.watch(majorMapperProvider);

  return MajorRepository(
    local: majorLocal,
    curriculumRemote: curriculumRemote,
    majorMapper: majorMapper,
  );
}
