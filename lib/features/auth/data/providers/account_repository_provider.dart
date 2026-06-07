import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/auth/data/account_repository.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_local_datasource_provider.dart';

part 'account_repository_provider.g.dart';

@Riverpod(keepAlive: true)
Future<AccountRepository> accountRepository(AccountRepositoryRef ref) async {
  final localDataSource = await ref.watch(
    accountLocalDataSourceProvider.future,
  );
  return AccountRepository(localDataSource);
}
