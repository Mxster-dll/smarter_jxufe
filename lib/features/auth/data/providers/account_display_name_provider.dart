import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';

/// 当前账号的本地显示名（账户记录里的 `displayName`）。
///
/// 取不到（未登录 / 未记录姓名）返回 null —— 头像的首字回退会据此退到通用图标。
/// 原定义在 `home_screen.dart`，因头像组件（共享件）也要用而迁到此处。
final currentAccountNameProvider = FutureProvider<String?>((ref) async {
  final accountRepo = await ref.watch(accountRepositoryProvider.future);
  final accounts = accountRepo.getAccounts().fold(
    (_) => <Account>[],
    (list) => list,
  );
  final current = ref.watch(currentAccountProvider);
  if (current.isEmpty) return null;
  for (final a in accounts) {
    if (a.cardNumber == current && a.displayName.isNotEmpty) {
      return a.displayName;
    }
  }
  return null;
});
