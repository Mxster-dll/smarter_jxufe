import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/qr_login/data/datasources/scan_login_remote_datasource.dart';

part 'scan_login_remote_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
ScanLoginRemoteDataSource scanLoginRemoteDataSource(
  ScanLoginRemoteDataSourceRef ref,
) {
  final dio = ref.watch(loginDioProvider);
  return ScanLoginRemoteDataSource(dio);
}
