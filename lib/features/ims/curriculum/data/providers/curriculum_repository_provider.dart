import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/curriculum_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_html_parser_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_mapper_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_remote_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_terms_providers.dart';

part 'curriculum_repository_provider.g.dart';

@Riverpod(keepAlive: true)
Future<CurriculumRepository> curriculumRepository(
  CurriculumRepositoryRef ref,
) async {
  final localDataSource = await ref.watch(
    curriculumLocalDataSourceProvider.future,
  );
  final remoteDataSource = ref.watch(curriculumRemoteDataSourceProvider);
  // ⚠ 本函数的**函数体**是手改的（加了开课学期侧表这一路依赖），没重跑
  // build_runner —— 生成物里的 `_$curriculumRepositoryHash` 因此偏旧。
  // 那只影响 dev 期「生成物是否最新」的提示，不改运行时行为；下次谁跑
  // build_runner 会自动对齐。
  final termsLocalDataSource = await ref.watch(
    curriculumTermsLocalDataSourceProvider.future,
  );
  final htmlParser = ref.watch(curriculumHtmlParserProvider);
  final curriculumMapper = ref.watch(curriculumMapperProvider);
  final imsAuthRepo = await ref.watch(imsAuthRepositoryProvider.future);

  return CurriculumRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    termsLocalDataSource: termsLocalDataSource,
    htmlParser: htmlParser,
    curriculumMapper: curriculumMapper,
    imsAuthRepo: imsAuthRepo,
  );
}
