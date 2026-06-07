import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/constants/hive_box_names.dart';
import 'package:smarter_jxufe/features/auth/data/datasources/account_local_datasource.dart';

part 'account_local_datasource_provider.g.dart';

@Riverpod(keepAlive: true)
Future<Box<String>> accountBox(AccountBoxRef ref) =>
    Hive.openBox<String>(accountBoxName);

@Riverpod(keepAlive: true)
Future<AccountLocalDataSource> accountLocalDataSource(
  AccountLocalDataSourceRef ref,
) async {
  final box = await ref.watch(accountBoxProvider.future);
  return AccountLocalDataSource(box);
}
