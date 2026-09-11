import 'dart:io';

import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_auth_remote_datasource.dart';

/// 入馆教育(tsgxs.jxufe.cn)会话仓库(镜像 SSP/dzj 会话仓库模式)。
///
/// 1. 按账户提供持久化的平台会话 Cookie(本地命中即返回)；
/// 2. 缓存缺失/强制刷新时执行完整换取流程：
///    CAS service 入口(复用 [AuthRepository.getServiceRedirectUrl]，TGC
///    过期自动重登)→ 拿带 ticket 的 casapi 回调地址 → 逐跳跟随收集
///    tsgxs 域 Set-Cookie → 持久化；
/// 3. 业务请求发现会话失效(被重定向回登录页)由业务仓库驱动刷新。
class TsgxsAuthRepository {
  final TsgxsAuthLocalDataSource _localDataSource;
  final TsgxsAuthRemoteDataSource _remoteDataSource;
  final AuthRepository _authRepository;

  TsgxsAuthRepository({
    required TsgxsAuthLocalDataSource localDataSource,
    required TsgxsAuthRemoteDataSource remoteDataSource,
    required AuthRepository authRepository,
  }) : _localDataSource = localDataSource,
       _remoteDataSource = remoteDataSource,
       _authRepository = authRepository;

  /// 获取指定账户的平台会话 Cookie；本地有缓存且非强制刷新时直接返回。
  ///
  /// **缓存必须含鉴权标识 `uid`**(cblogin 签发)才可用:缺 uid 的是匿名态
  /// Cookie(仅 `ASP.NET_SessionId; from`),首页/章节页仍能 200,但
  /// `/Web/Exam`、成绩、排行榜会 302 到 `/web/user/logout`。
  Future<String> getSessionCookie(
    String account, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _localDataSource.getCookie(account);
      if (cached != null &&
          cached.isNotEmpty &&
          TsgxsAuthRemoteDataSource.hasUid(cached)) {
        return cached;
      }
    }
    return refreshSessionCookie(account);
  }

  /// 走统一认证完整换取并持久化该账户的会话 Cookie。
  /// [trace] 非空时收集换证逐跳诊断行（透传远程数据源）。
  ///
  /// 换取结果必须含 `uid`;否则说明本次链路没走到 cblogin(票据一次性,
  /// 无法在中途补救),重走整条链路一次(取新票据)。失败时把逐跳诊断
  /// 写入 [traceLogPath],便于排查(只含 URL/状态码/Cookie **名**,无账密)。
  Future<String> refreshSessionCookie(
    String account, {
    List<String>? trace,
  }) async {
    final lines = trace ?? <String>[];
    try {
      String? cookie;
      for (var attempt = 0; attempt < 2; attempt++) {
        final redirectResult = await _authRepository.getServiceRedirectUrl(
          TsgxsAuthRemoteDataSource.casServiceUrl,
        );
        final ticketUrl = redirectResult.fold(
          (failure) =>
              throw Exception('获取统一认证票据失败：${failure.message ?? failure}'),
          (url) => url,
        );
        lines.add('票据地址(${attempt + 1}): ${_mask(ticketUrl)}');

        cookie = await _remoteDataSource.establishSession(
          ticketUrl,
          trace: lines,
        );
        if (TsgxsAuthRemoteDataSource.hasUid(cookie)) break;
        lines.add('第 ${attempt + 1} 次换取未取得 uid,重走整条换取链…');
      }
      final session = cookie ?? '';
      if (!TsgxsAuthRemoteDataSource.hasUid(session)) {
        await _dumpTrace(lines, '未取得 uid(account=$account)');
      }
      await _localDataSource.saveCookie(account, session);
      return session;
    } catch (e) {
      await _dumpTrace(lines, '换取失败(account=$account): $e');
      rethrow;
    }
  }

  /// 逐跳诊断落盘路径(`%TEMP%\tsgxs_login_trace.log`)。
  static String get traceLogPath =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'tsgxs_login_trace.log';

  /// 写诊断文件;失败静默(诊断本身不得影响主流程)。
  static Future<void> _dumpTrace(List<String> lines, String reason) async {
    try {
      await File(traceLogPath).writeAsString(
        '== ${DateTime.now().toIso8601String()} $reason\n'
        '${lines.map(_mask).join('\n')}\n',
      );
    } catch (_) {
      // 诊断写盘失败可忽略。
    }
  }

  /// 脱敏:票据、会话 id、uid 的值一律打码。
  static String _mask(String line) => line
      .replaceAll(RegExp(r'ticket=ST-[^&\s]+'), 'ticket=ST-***')
      .replaceAllMapped(
        RegExp(r'(ASP\.NET_SessionId=)[^;\s]+'),
        (m) => '${m[1]}***',
      )
      .replaceAllMapped(RegExp(r'(uid=)[0-9a-fA-F-]{8,}'), (m) => '${m[1]}***');

  /// 清除指定账户的本地会话。
  Future<void> clearSessionCookie(String account) =>
      _localDataSource.clearCookie(account);

  /// 覆盖持久化指定账户的会话 Cookie（用于业务调用过程中服务端下发新
  /// Cookie 后同步，如 SelectTheme 登录成功返回的新会话）。
  Future<void> updateSessionCookie(String account, String cookie) =>
      _localDataSource.saveCookie(account, cookie);
}
