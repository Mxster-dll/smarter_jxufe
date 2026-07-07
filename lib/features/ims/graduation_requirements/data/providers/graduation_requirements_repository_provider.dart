import 'package:riverpod/riverpod.dart';

import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/graduation_requirements_repository.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/providers/graduation_requirements_html_parser_provider.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/providers/graduation_requirements_remote_datasource_provider.dart';

/// 毕业学分要求 Repository Provider。
final graduationRequirementsRepositoryProvider =
    FutureProvider<GraduationRequirementsRepository>((ref) async {
      final remoteDataSource = ref.watch(
        graduationRequirementsRemoteDataSourceProvider,
      );
      final htmlParser = ref.watch(graduationRequirementsHtmlParserProvider);
      final imsAuthRepo = await ref.watch(imsAuthRepositoryProvider.future);

      return GraduationRequirementsRepository(
        remoteDataSource: remoteDataSource,
        htmlParser: htmlParser,
        imsAuthRepo: imsAuthRepo,
      );
    });
