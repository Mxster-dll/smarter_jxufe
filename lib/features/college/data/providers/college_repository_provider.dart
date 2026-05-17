import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/college/data/college_repository.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_filter_provider.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_mapper_provider.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_remote_datasource_provider.dart';

part 'college_repository_provider.g.dart';

@riverpod
Future<CollegeRepository> collegeRepository(CollegeRepositoryRef ref) async {
  final localDataSource = await ref.watch(
    collegeLocalDataSourceProvider.future,
  );
  final remoteDataSource = ref.watch(collegeRemoteDataSourceProvider);

  final collegeFilter = ref.watch(collegeFilterProvider);
  final collegeMapper = ref.watch(collegeMapperProvider);

  return CollegeRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    collegeFilter: collegeFilter,
    collegeMapper: collegeMapper,
  );
}
