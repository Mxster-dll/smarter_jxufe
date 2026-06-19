import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/data/grades_repository.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/grades_html_parser_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/grades_remote_datasource_provider.dart';

part 'grades_repository_provider.g.dart';

@Riverpod(keepAlive: true)
Future<GradesRepository> gradesRepository(GradesRepositoryRef ref) async {
  final remoteDataSource = ref.watch(gradesRemoteDataSourceProvider);
  final htmlParser = ref.watch(gradesHtmlParserProvider);
  final imsAuthRepo = await ref.watch(imsAuthRepositoryProvider.future);

  return GradesRepository(
    remoteDataSource: remoteDataSource,
    htmlParser: htmlParser,
    imsAuthRepo: imsAuthRepo,
  );
}
