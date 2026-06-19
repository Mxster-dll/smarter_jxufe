import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_auth_repository.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_remote_datasource_provider.dart';

part 'ims_auth_repository_provider.g.dart';

@Riverpod(keepAlive: true)
Future<ImsAuthRepository> imsAuthRepository(ImsAuthRepositoryRef ref) async {
  final dio = ref.watch(currentImsDioProvider);
  final authRepository = await ref.watch(authRepositoryProvider.future);
  final localDataSource = await ref.watch(
    imsAuthLocalDataSourceProvider.future,
  );
  final remoteDataSource = ref.watch(imsAuthRemoteDataSourceProvider);

  final repository = ImsAuthRepository(
    dio: dio,
    authRepository: authRepository,
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
  );

  // 注入 JSESSIONID 刷新回调到 IMS 拦截器，实现凭证失效自动重试
  setJsessionIdRefreshCallback(() => repository.refreshJsessionId());

  return repository;
}
