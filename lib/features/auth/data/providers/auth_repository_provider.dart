import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_for_account_provider.dart';

part 'auth_repository_provider.g.dart';

/// 当前账号的统一登录（CAS）仓库 —— 对外唯一入口。
///
/// watch [currentAccountProvider] → 切号即指向该账号的仓库，磁盘上的
/// TGC / 凭据随之换成该账号那一份（`TGC|<账号>`），因此「切回来」只要
/// TGC 还在有效期就**免密码免 MFA**；实现见
/// [authRepositoryForAccountProvider]。
@Riverpod(keepAlive: true)
Future<AuthRepository> authRepository(AuthRepositoryRef ref) async {
  final account = ref.watch(currentAccountProvider);
  return ref.watch(authRepositoryForAccountProvider(account).future);
}
