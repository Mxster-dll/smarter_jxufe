import 'package:riverpod/riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/datasources/graduation_requirements_remote_datasource.dart';

/// 毕业学分要求远程数据源 Provider。
final graduationRequirementsRemoteDataSourceProvider =
    Provider<GraduationRequirementsRemoteDataSource>((ref) {
      final dio = ref.watch(currentImsDioProvider);
      return GraduationRequirementsRemoteDataSource(dio);
    });
