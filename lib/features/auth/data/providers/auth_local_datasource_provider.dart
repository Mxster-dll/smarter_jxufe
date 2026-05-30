import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_box_provider.dart';

part 'auth_local_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
Future<AuthLocalDataSource> authLocalDataSource(
  AuthLocalDataSourceRef ref,
) async {
  final box = await ref.watch(authBoxProvider.future);
  return AuthLocalDataSource(box);
}
