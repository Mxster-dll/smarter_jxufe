import 'package:riverpod/riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/data/anti_corruption/grades_html_parser.dart';
import 'package:smarter_jxufe/features/ims/grades/data/datasources/grades_remote_datasource.dart';
import 'package:smarter_jxufe/features/ims/grades/data/grades_repository.dart';

final gradesRemoteDataSourceProvider = Provider<GradesRemoteDataSource>((ref) {
  final dio = ref.watch(currentImsDioProvider);
  return GradesRemoteDataSource(dio);
});

final gradesHtmlParserProvider = Provider<GradesHtmlParser>((ref) {
  return GradesHtmlParser();
});

final gradesRepositoryProvider = FutureProvider<GradesRepository>((ref) async {
  final remoteDataSource = ref.watch(gradesRemoteDataSourceProvider);
  final htmlParser = ref.watch(gradesHtmlParserProvider);
  final imsAuthRepo = await ref.watch(imsAuthRepositoryProvider.future);

  return GradesRepository(
    remoteDataSource: remoteDataSource,
    htmlParser: htmlParser,
    imsAuthRepo: imsAuthRepo,
  );
});
