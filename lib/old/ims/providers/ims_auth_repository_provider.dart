import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/ims_auth_repository.dart';

part 'ims_auth_repository_provider.g.dart';

@riverpod
ImsAuthRepository imsAuthRepository(ImsAuthRepositoryRef ref, String account) {
  // 这里需要根据 IMS 模块的实际实现来构建
  // 例如：
  // final sessionManager = ref.watch(imsSessionManagerProvider(account));
  // final remote = ref.watch(imsAuthRemoteDataSourceProvider(account));
  // return ImsAuthRepositoryImpl(remote, sessionManager);
  throw UnimplementedError('需按账号构建 ImsAuthRepository');
}
