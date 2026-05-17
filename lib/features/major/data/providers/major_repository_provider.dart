import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_filter_provider.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_mapper_provider.dart';

import 'package:smarter_jxufe/features/major/data/major_repository.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_remote_datasource_provider.dart';

part 'major_repository_provider.g.dart';

@riverpod
Future<MajorRepository> majorRepository(MajorRepositoryRef ref) async {
  final majorLocal = await ref.watch(majorLocalDataSourceProvider.future);
  final curriculumRemote = ref.watch(majorRemoteDataSourceProvider);

  final majorFilter = ref.watch(majorFilterProvider);
  final majorMapper = ref.watch(majorMapperProvider);

  return MajorRepository(
    localDataSource: majorLocal,
    remoteDataSource: curriculumRemote,
    majorFilter: majorFilter,
    majorMapper: majorMapper,
  );
}
