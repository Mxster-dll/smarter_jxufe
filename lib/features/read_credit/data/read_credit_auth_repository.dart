/// 阅读学分平台会话仓库（镜像 tsgxs / SSP 会话仓库模式）。
///
/// 1. 按账号提供持久化会话 Cookie（本地命中即返回）；
/// 2. 缺失或强制刷新时执行完整换证链：CAS service 入口（复用
///    [AuthRepository.getServiceRedirectUrl]，TGC 过期会自动静默重登）
///    → 带 ticket 的平台回调地址 → 逐跳收集平台域 Set-Cookie → 持久化；
/// 3. 业务请求发现 302 回登录页时由业务仓库驱动刷新。
library;

import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/read_credit/data/datasources/read_credit_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/read_credit/data/read_credit_auth_local_datasource.dart';

class ReadCreditAuthRepository {
  final ReadCreditAuthLocalDataSource _local;
  final ReadCreditAuthRemoteDataSource _remote;
  final AuthRepository _authRepository;

  ReadCreditAuthRepository({
    required ReadCreditAuthLocalDataSource localDataSource,
    required ReadCreditAuthRemoteDataSource remoteDataSource,
    required AuthRepository authRepository,
  }) : _local = localDataSource,
       _remote = remoteDataSource,
       _authRepository = authRepository;

  /// 取指定账号的平台会话 Cookie；本地缓存含鉴权标识时直接返回。
  Future<String> getSessionCookie(
    String account, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _local.getCookie(account);
      if (cached != null && ReadCreditAuthRemoteDataSource.hasSession(cached)) {
        return cached;
      }
    }
    return refreshSessionCookie(account);
  }

  /// 走统一认证完整换取并持久化会话 Cookie。
  ///
  /// 票据一次性：若首次换取未拿到 `uid`/`token`（链路中途失效），重走整条
  /// 链路一次（取新票据）。
  Future<String> refreshSessionCookie(
    String account, {
    List<String>? trace,
  }) async {
    final lines = trace ?? <String>[];
    String? cookie;
    for (var attempt = 0; attempt < 2; attempt++) {
      final redirectResult = await _authRepository.getServiceRedirectUrl(
        ReadCreditAuthRemoteDataSource.casServiceUrl,
      );
      final ticketUrl = redirectResult.fold(
        (failure) => throw ReadCreditSessionExpiredException(
          '获取统一认证票据失败：${failure.message ?? failure}',
        ),
        (url) => url,
      );
      cookie = await _remote.establishSession(ticketUrl, trace: lines);
      if (ReadCreditAuthRemoteDataSource.hasSession(cookie)) break;
      lines.add('第 ${attempt + 1} 次换取未取得会话标识，重走整条换取链…');
    }
    final session = cookie ?? '';
    await _local.saveCookie(account, session);
    return session;
  }

  /// 清除指定账号的本地会话。
  Future<void> clearSessionCookie(String account) =>
      _local.clearCookie(account);
}
