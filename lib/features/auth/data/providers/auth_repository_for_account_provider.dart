import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_local_datasource_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_remote_datasource_provider.dart';

/// **指定账号**的统一登录（CAS）仓库 —— 手写 provider（非 riverpod_generator）。
///
/// 口径（2026-09-11 与用户确认：「统一登录也要像 IMS 一样持久化，
/// 对于每个账号，统一登录和 IMS 都只有一个入口」）：
///
/// - **按账号持久化**：TGC / 缓存凭据存在 `auth` box 的 `TGC|<账号>`、
///   `CACHEDUSER|<账号>`、`CACHEDPASS|<账号>` 键里，切换账号互不覆盖
///   → 切回来（或重启应用）只要 TGC 没过期，`AuthRepository.isTgcAlive()`
///   即为真，**免密码、免 MFA** 直接进入；TGC 真过期才用缓存凭据静默重登。
/// - **仓库绑账号**：构造时只读该账号那一份磁盘状态（读盘作用域 = [account]），
///   而写盘（`login` / `cacheCredentials`）始终按**入参账号**，因此「当前是 A、
///   正在登录 B」的切号流程不会写串。
/// - **family 缓存实例**：同一账号拿到的永远是同一个 `AuthRepository`，
///   MFA 回调（`onMfaRequired`）与内存里的 TGC 都随之共享 —— 切号把
///   `currentAccountProvider` 指向 B 之后，`authRepositoryProvider` 取到的
///   正是登录 B 用到的那一个实例，回调不会丢。
/// - **旧数据迁移**：历史无账号单键（`tgc` / `cachedUser` / `cachedPass`）
///   由 `claimLegacyCredentials(account)` 认领给 `cachedUser` 记着的那个账号，
///   认领后删除旧键（只发生一次）。
///
/// 注意：这里刻意**不用** `autoDispose` —— [authRepositoryProvider] 与
/// `imsSessionProvider` 都会 `ref.read` 它，自动销毁会让在途的 future 被丢弃。
final authRepositoryForAccountProvider =
    FutureProvider.family<AuthRepository, String>((ref, account) async {
  final localDataSource = await ref.watch(authLocalDataSourceProvider.future);
  // 旧版无账号单键 → 认领给本账号（其它账号调用时不动旧键）。
  await localDataSource.claimLegacyCredentials(account);
  return AuthRepository(
    localDataSource: localDataSource,
    remoteDataSource: ref.watch(authRemoteDataSourceProvider),
    deviceProfileRepo: ref.watch(deviceProfileRepositoryProvider),
    account: account,
  );
});
