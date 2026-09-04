import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';

/// 综合管理服务平台（ssp）会话仓库。
///
/// 职责：
/// 1. 提供按账户持久化的 JSESSIONID（本地缓存命中即返回）；
/// 2. 缓存失效 / 未命中时执行完整换取流程：
///    `GET /sso/login.html` 拿匿名 JSESSIONID + CAS URL
///    → 携带应用已有 TGC 走统一认证跳转（TGC 过期则自动重登）
///    → 用回调地址 + 匿名 JSESSIONID 激活平台会话
///    → 持久化后返回；
/// 3. 会话过期重试逻辑由业务仓库（如 [VolunteerHoursRepository]）驱动。
class SspAuthRepository {
  final SspAuthLocalDataSource _localDataSource;
  final SspAuthRemoteDataSource _remoteDataSource;
  final AuthRepository _authRepository;

  SspAuthRepository({
    required SspAuthLocalDataSource localDataSource,
    required SspAuthRemoteDataSource remoteDataSource,
    required AuthRepository authRepository,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _authRepository = authRepository;

  /// 获取指定账户的 JSESSIONID。
  ///
  /// 本地已有缓存且 [forceRefresh] 为 false 时直接返回；
  /// 否则执行 [refreshSessionId] 完整换取流程。
  Future<String> getSessionId(
    String account, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _localDataSource.getSessionId(account);
      if (cached != null && cached.isNotEmpty) return cached;
    }
    return refreshSessionId(account);
  }

  /// 走统一认证完整换取并持久化该账户的 JSESSIONID，返回新会话 ID。
  Future<String> refreshSessionId(String account) async {
    final entry = await _remoteDataSource.fetchSsoLoginEntry();

    final redirectResult = await _authRepository.getServiceRedirectUrl(
      entry.casLoginUrl,
    );
    final callbackUrl = redirectResult.fold(
      (failure) => throw Exception('获取统一认证票据失败：${failure.message ?? failure}'),
      (url) => url,
    );

    final sessionId = await _remoteDataSource.activateSession(
      callbackUrl: callbackUrl,
      jsessionId: entry.jsessionId,
    );

    await _localDataSource.saveSessionId(account, sessionId);
    return sessionId;
  }

  /// 清除指定账户的本地会话记录。
  Future<void> clearSessionId(String account) =>
      _localDataSource.clearSessionId(account);
}
