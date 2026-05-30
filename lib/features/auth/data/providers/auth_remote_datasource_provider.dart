import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/auth_remote_datasource.dart';

part 'auth_remote_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
AuthRemoteDataSource authRemoteDataSource(AuthRemoteDataSourceRef ref) {
  final dio = ref.watch(loginDioProvider);
  return AuthRemoteDataSource(dio);
}
