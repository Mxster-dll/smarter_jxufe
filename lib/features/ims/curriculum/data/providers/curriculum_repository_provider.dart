import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/curriculum_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_html_parser_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_mapper_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_remote_datasource_provider.dart';

part 'curriculum_repository_provider.g.dart';

@riverpod
CurriculumRepository curriculumRepository(CurriculumRepositoryRef ref) {
  final localDataSource = ref.watch(curriculumLocalDataSourceProvider);
  final remoteDataSource = ref.watch(curriculumRemoteDataSourceProvider);
  final htmlParser = ref.watch(curriculumHtmlParserProvider);
  final curriculumMapper = ref.watch(curriculumMapperProvider);

  return CurriculumRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    htmlParser: htmlParser,
    curriculumMapper: curriculumMapper,
  );
}
