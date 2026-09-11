import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';

part 'grades_box_provider.g.dart';

/// 成绩缓存 box（**按账号隔离**，见 `core/storage/account_scoped_box.dart`）。
///
/// 账号切换后 `currentAccountProvider` 变化 → 本 provider 重跑 → 换到新账号的
/// box，因此切号不会读到上一个账号的成绩，切回来也不必重新拉取。
@Riverpod(keepAlive: true)
Future<Box<String>> gradesBox(GradesBoxRef ref) => openAccountScopedBox(
  'gradesCache',
  ref.watch(currentAccountProvider),
);
