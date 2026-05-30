import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_remote_datasource_provider.dart';

part 'auth_repository_provider.g.dart';

@Riverpod(keepAlive: true)
Future<AuthRepository> authRepository(AuthRepositoryRef ref) async {
  final localDataSource = await ref.watch(authLocalDataSourceProvider.future);
  final remoteDataSource = ref.watch(authRemoteDataSourceProvider);
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return AuthRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    deviceProfileRepo: deviceProfileRepo,
  );
}
