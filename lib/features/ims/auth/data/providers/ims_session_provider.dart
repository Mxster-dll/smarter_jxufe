import 'package:riverpod/riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/ims_dio.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_for_account_provider.dart';
import 'package:smarter_jxufe/features/ims/auth/data/datasource/ims_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/ims/auth/data/ims_session.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_local_datasource_provider.dart';

/// **全局唯一的 IMS 会话实例**（成绩 / 课表 / 毕业学分 / 培养方案 / 我的 共用）。
///
/// 口径（2026-09-11 与用户确认）：
/// - 一个实例：本 provider 是唯一入口，`currentImsDioProvider` 直接取它的 Dio；
/// - 零请求进入：本地有会话时 `ensureReady()` 不发任何请求，失效由拦截器在
///   业务请求上发现后自动 `renew()` 重试，不再每次进页面重走 CAS 换票；
/// - 切换账号即销毁重建：watch [currentAccountProvider]，账号一变整个会话
///   （Dio / 拦截器 / 内存会话）重建，旧实例只 `release` 内存、**不动磁盘**；
/// - 重启应用 / 桌面小组件访问都不丢：会话按账号落盘（`imsAuth` box），
///   且 TGC 过期还能用 `account` box 里的凭据静默重登。
///
/// 同步 provider：十几个数据源都用 `ref.watch(currentImsDioProvider)` 同步
/// 取 Dio，因此这里不能是异步 provider——异步依赖（Hive box / CAS 仓库）
/// 推迟到真正需要时再解析（见 [_LazySessionStore] 与 [_resolveRedirect]）。
final imsSessionProvider = Provider<ImsSession>((ref) {
  final account = ref.watch(currentAccountProvider);
  final deviceProfile = ref.watch(deviceProfileRepositoryProvider);
  final built = createImsDio(deviceProfile);

  final session = ImsSession(
    account: account,
    dio: built.dio,
    store: _LazySessionStore(
      () => ref.read(imsAuthLocalDataSourceProvider.future),
    ),
    resolveRedirect: () => _resolveRedirect(ref, account),
  );

  // 凭证失效 → 由本会话换票（内部去重）并由拦截器用新票重试原请求。
  built.interceptor.setRefreshCallback(session.renew);

  // 切号 / 容器销毁 / 热重载：释放内存态，磁盘会话保留给下次复用。
  ref.onDispose(session.release);

  return session;
});

/// CAS 侧解析 IMS 回跳地址与 gid。
///
/// 走 `AuthRepository.getImsRedirectInfo()`——它在 TGC 过期时会用缓存凭据
/// 静默重登后重试，因此「TGC 过期」不会直接变成「请重新登录」。
///
/// 取的是**本会话账号**那一份 CAS 仓库（`authRepositoryForAccountProvider`）：
/// `authRepositoryProvider` 绑的是「当前账号」，切号瞬间有解析时序竞争，
/// 直接按 [account] 取 family 缓存的实例最确定。
Future<({String url, String? gid})> _resolveRedirect(
  Ref ref,
  String account,
) async {
  final cas = await ref.read(authRepositoryForAccountProvider(account).future);
  final result = await cas.getImsRedirectInfo();
  return result.fold(
    (failure) => throw Exception('IMS 重定向失败：${failure.message}'),
    (info) => (url: info.$1, gid: info.$2),
  );
}

/// 惰性 store：会话真正要用到磁盘时才打开 Hive box（保持 provider 同步）。
class _LazySessionStore implements ImsSessionStore {
  _LazySessionStore(this._resolve);

  final Future<ImsAuthLocalDataSource> Function() _resolve;
  Future<ImsAuthLocalDataSource>? _dataSource;

  Future<ImsAuthLocalDataSource> get _ds => _dataSource ??= _resolve();

  @override
  Future<String?> read(String account) async => (await _ds).read(account);

  @override
  Future<void> write(String account, String jsessionId) async =>
      (await _ds).write(account, jsessionId);

  @override
  Future<String?> migrateLegacy(String account) async =>
      (await _ds).migrateLegacy(account);

  @override
  Future<void> forget(String account) async => (await _ds).forget(account);
}
