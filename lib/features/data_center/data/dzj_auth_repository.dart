import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';

/// 竹简数据中台（dzj 学生个人数据中心）会话仓库。
///
/// 职责（镜像 SSP 会话仓库模式）：
/// 1. 按账户提供持久化的 [DzjSession]（本地缓存命中即返回）；
/// 2. 缓存缺失 / 失效时执行完整换取流程：
///    CAS service 入口（复用 [AuthRepository.getServiceRedirectUrl]，TGC
///    过期自动重登）→ 拿带 ticket 的 dzj 回调地址 → 访问并收取服务端下发的
///    SESSION / fixedSalt → 持久化；
/// 3. 会话失效重试由业务仓库（如 [DataCenterRepository]）驱动。
class DzjAuthRepository {
  final DzjAuthLocalDataSource _localDataSource;
  final DzjAuthRemoteDataSource _remoteDataSource;
  final AuthRepository _authRepository;

  /// 学生个人数据中心首页在统一认证中的 service 入口。
  static const String casServiceUrl =
      'https://ssl.jxufe.edu.cn/cas/login'
      '?service=https%3A%2F%2Fdzj.jxufe.edu.cn%2Fapp%2F66eef481a9a3';

  DzjAuthRepository({
    required DzjAuthLocalDataSource localDataSource,
    required DzjAuthRemoteDataSource remoteDataSource,
    required AuthRepository authRepository,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _authRepository = authRepository;

  /// 获取指定账户的会话，无缓存 / 强制刷新时执行换取流程。
  Future<DzjSession> getSession(
    String account, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _localDataSource.getSession(account);
      if (cached != null) return cached;
    }
    return refreshSession(account);
  }

  /// 正在进行的会话换取（按账户）—— **单飞**。
  ///
  /// 为什么必须单飞（2026-10-01 立）：数据中心页改成「先上屏、各卡自己取数」
  /// 之后，页面一开，概览 / 子页面清单 / 补充模块 / 相关人员 / 校内关系
  /// **会同时**发现会话已死并各自喊「换会话」——从前它们被首屏那一批
  /// 串在后面，恰好只有一个在换。放任并发换票有两个后果：
  /// ① 统一认证的 ST 是一次性的，并发换票互相作废；② 开一次页面白打
  /// 多遍认证往返。这里按账户复用同一个 Future（与 [AuthRepository] 里
  /// `_reloginCompleter` 防重入同一套路）。
  final Map<String, Future<DzjSession>> _inFlight = {};

  /// 走统一认证完整换取并持久化该账户会话（并发调用只换一次）。
  Future<DzjSession> refreshSession(String account) {
    final running = _inFlight[account];
    if (running != null) return running;

    final future = _establish(account);
    _inFlight[account] = future;
    return future.whenComplete(() {
      if (identical(_inFlight[account], future)) _inFlight.remove(account);
    });
  }

  /// 真正的换取动作（[refreshSession] 的单飞壳子包在外面）。
  Future<DzjSession> _establish(String account) async {
    final redirectResult = await _authRepository.getServiceRedirectUrl(
      casServiceUrl,
    );
    final ticketUrl = redirectResult.fold(
      (failure) => throw DzjApiException('获取统一认证票据失败：${failure.message ?? failure}'),
      (url) => url,
    );

    final session = await _remoteDataSource.establishSession(ticketUrl);
    await _localDataSource.saveSession(account, session);
    return session;
  }

  /// 清除指定账户的本地会话。
  Future<void> clearSession(String account) =>
      _localDataSource.clearSession(account);
}
