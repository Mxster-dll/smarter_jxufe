import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/qr_login/data/datasources/wecom_login_remote_datasource.dart';

part 'wecom_login_remote_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
WecomLoginRemoteDataSource wecomLoginRemoteDataSource(
  WecomLoginRemoteDataSourceRef ref,
) {
  final dio = ref.watch(loginDioProvider);
  return WecomLoginRemoteDataSource(dio);
}
