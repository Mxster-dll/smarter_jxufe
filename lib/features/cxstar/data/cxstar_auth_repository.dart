/// 畅想之星个人会话仓库（镜像 tsgxs / 阅读学分 的会话仓库模式）。
///
/// 1. 按账号提供持久化的个人 JWT（本地命中且形态合法即返回，24h 内不重复换证）；
/// 2. 缺失或强制刷新时执行完整换证链：CAS service 入口
///    （复用 [AuthRepository.getServiceRedirectUrl]，TGC 过期会静默重登）
///    → 逐跳收集回跳地址 / Set-Cookie / 正文里的个人 token → 持久化；
/// 3. 业务请求 401 时由 provider 驱动 [refreshSessionToken] 重试一次。
///
/// [getSessionToken] **不抛异常**：换证失败返回 null，由调用方回退
/// 手工令牌或校园网 IP 免密（公用账号），保证页面始终有数据。
library;

import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/cxstar/data/cxstar_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_auth_remote_datasource.dart';

class CxstarAuthRepository {
  final CxstarAuthLocalDataSource _local;
  final CxstarAuthRemoteDataSource _remote;
  final AuthRepository _authRepository;

  CxstarAuthRepository({
    required CxstarAuthLocalDataSource localDataSource,
    required CxstarAuthRemoteDataSource remoteDataSource,
    required AuthRepository authRepository,
  }) : _local = localDataSource,
       _remote = remoteDataSource,
       _authRepository = authRepository;

  /// 取指定账号的个人 token；换证失败返回 null（调用方回退其它源）。
  Future<String?> getSessionToken(
    String account, {
    bool forceRefresh = false,
  }) async {
    if (account.isEmpty) return null;
    if (!forceRefresh) {
      final cached = _local.getToken(account);
      if (CxstarAuthRemoteDataSource.looksLikeToken(cached)) return cached;
    }
    try {
      return await refreshSessionToken(account);
    } catch (_) {
      return null;
    }
  }

  /// 走统一认证完整换取并持久化个人 token。
  ///
  /// 票据一次性：首次未取得 token 时重走整条链路一次（取新票据）。
  Future<String> refreshSessionToken(
    String account, {
    List<String>? trace,
  }) async {
    final lines = trace ?? <String>[];
    String? token;
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      final redirectResult = await _authRepository.getServiceRedirectUrl(
        CxstarAuthRemoteDataSource.casServiceUrl,
      );
      final ticketUrl = redirectResult.fold(
        (failure) => throw CxstarSessionException(
          '获取统一认证票据失败：${failure.message ?? failure}',
        ),
        (url) => url,
      );
      try {
        token = await _remote.establishSession(ticketUrl, trace: lines);
      } on CxstarSessionException catch (e) {
        lastError = e;
        lines.add('第 ${attempt + 1} 次换取失败：$e');
        continue;
      }
      if (CxstarAuthRemoteDataSource.looksLikeToken(token)) break;
      lines.add('第 ${attempt + 1} 次换取未取得合法 token，重走整条换取链…');
      token = null;
    }
    if (token == null || !CxstarAuthRemoteDataSource.looksLikeToken(token)) {
      throw CxstarSessionException(
        '畅想之星个人会话建立失败：${lastError ?? '两次换取均未取得 token'}',
      );
    }
    await _local.saveToken(account, token);
    return token;
  }

  /// 清除指定账号的本地会话（下次访问重新换证）。
  Future<void> clearSessionToken(String account) => _local.clearToken(account);
}
