import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:smarter_jxufe/features/ims/auth/data/ims_session_renewal.dart';

/// 会话状态（界面据此决定"直接进页面"还是"转圈/报错"）。
enum ImsSessionPhase {
  /// 尚无会话（本地没有、也没续过）。
  empty,

  /// 会话可用（来自本地持久化或刚续期得到）。
  ready,

  /// 正在续期（换票）。
  renewing,

  /// 续期失败（无可用会话）。
  failed,
}

/// 会话持久化（**按账号隔离**）。
///
/// 实现见 `ImsAuthLocalDataSource`（Hive box `imsAuth`，键 `JSESSIONID|<账号>`）。
abstract interface class ImsSessionStore {
  /// 读该账号已持久化的会话（读 Hive box，不发网络）。
  Future<String?> read(String account);

  /// 写入该账号的会话。
  Future<void> write(String account, String jsessionId);

  /// 把历史版本遗留的「无账号单键」会话认领给 [account]（惰性迁移，只成功一次）。
  Future<String?> migrateLegacy(String account);

  /// 删除该账号的会话（退出登录用；**切换账号不要调**）。
  Future<void> forget(String account);
}

/// CAS 侧的重定向解析：返回 IMS 回跳地址与 gid。
typedef ImsRedirectResolver = Future<({String url, String? gid})> Function();

/// **全局唯一的 IMS 实例**（成绩 / 课表 / 毕业学分 / 培养方案 / 我的 共用）。
///
/// 设计口径（2026-09-11 与用户确认）：
/// 1. **一个实例**：由 `imsSessionProvider`（`@Riverpod(keepAlive: true)`）持有，
///    所有 IMS 数据源走同一个 [dio]，凭证失效也由同一个拦截器回调 [renew]；
/// 2. **零请求进入**：本地有会话时 [ensureReady] 只读内存/磁盘、**不发任何请求**；
///    真正的失效由 `ImsAuthInterceptor` 在业务请求上发现后自动 [renew] 并重试；
/// 3. **切换账号即销毁重建**：`imsSessionProvider` watch `currentAccountProvider`，
///    账号一变整个实例重建（旧实例 [release] 释放内存态）；
/// 4. **重启/小组件不丢会话**：会话按账号落盘（TGC 过期还能用 `account` box 里的
///    凭据静默重登），[release] 只清内存、**绝不删磁盘**——只有 [forget] 才删。
class ImsSession {
  ImsSession({
    required this.account,
    required this.dio,
    required ImsSessionStore store,
    required ImsRedirectResolver resolveRedirect,
  }) : _store = store,
       _resolveRedirect = resolveRedirect;

  /// 本会话归属的账号卡号（学号）。空串 = 尚未确定账号。
  final String account;

  /// 本会话独占的 IMS Dio（含 GBK 解码器与本会话私有的失效重试拦截器）。
  final Dio dio;

  final ImsSessionStore _store;
  final ImsRedirectResolver _resolveRedirect;

  ImsSessionPhase _phase = ImsSessionPhase.empty;
  String? _jsessionId;
  DateTime? _issuedAt;
  Object? _lastError;

  /// 续期去重：并发请求同时踩到凭证失效时，只换一次票。
  Future<String>? _inflight;

  ImsSessionPhase get phase => _phase;

  /// 当前内存中的 JSESSIONID（未就绪时为 null）。
  String? get jsessionId => _jsessionId;

  /// 会话签发（或从磁盘恢复）的时间。
  DateTime? get issuedAt => _issuedAt;

  /// 最近一次续期失败的原因。
  Object? get lastError => _lastError;

  /// 内存里是否已有可用会话。
  bool get hasSession => (_jsessionId ?? '').isNotEmpty;

  /// 取一个可用会话。
  ///
  /// - 本地（内存 → 磁盘）已有会话：**一个请求都不发**，直接返回；
  /// - 本地没有：走 [renew] 换票（CAS TGC → JSESSIONID），失败则抛异常。
  ///
  /// 注：本地会话"是否仍然有效"不在这里判定——到期由业务请求触发拦截器
  /// 自动续期重试，避免每次进页面都多一次探活往返。
  Future<String> ensureReady() async {
    final cached = _jsessionId ?? await _restore();
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    return renew();
  }

  /// 强制换票（无视本地会话），成功后落盘。
  ///
  /// 并发调用共享同一次换票（[_inflight] 去重）。
  Future<String> renew() {
    final inflight = _inflight;
    if (inflight != null) return inflight;

    final future = _renew();
    _inflight = future;
    return future.whenComplete(() {
      if (identical(_inflight, future)) _inflight = null;
    });
  }

  Future<String> _renew() async {
    _phase = ImsSessionPhase.renewing;
    try {
      final redirect = await _resolveRedirect();
      final fresh = await fetchAndActivateJsessionId(
        imsDio: dio,
        redirectUrl: redirect.url,
        gid: redirect.gid,
      );
      await adopt(fresh);
      debugPrint('[ImsSession] 换票成功 account=$account');
      return fresh;
    } catch (e, s) {
      _phase = ImsSessionPhase.failed;
      _lastError = e;
      debugPrint('[ImsSession] 换票失败 account=$account: $e\n$s');
      rethrow;
    }
  }

  /// 采用一个刚拿到的会话（换票成功、或拦截器在别处换到票后回写）。
  Future<void> adopt(String jsessionId) async {
    if (jsessionId.isEmpty) return;
    _jsessionId = jsessionId;
    _issuedAt = DateTime.now();
    _phase = ImsSessionPhase.ready;
    _lastError = null;
    try {
      await _store.write(account, jsessionId);
    } catch (e) {
      // 落盘失败不致命：本次运行仍可用，只是重启后要重新换票。
      debugPrint('[ImsSession] 会话落盘失败 account=$account: $e');
    }
  }

  /// 释放内存态（**不动磁盘**）。
  ///
  /// provider dispose（切号 / 容器销毁 / 热重载）时调用；磁盘上的会话保留，
  /// 因此重启应用或切回本账号都还能直接复用。
  void release() {
    _jsessionId = null;
    _issuedAt = null;
    _inflight = null;
    _phase = ImsSessionPhase.empty;
  }

  /// 忘记本账号的会话（内存 + 磁盘）。**退出登录**才用。
  Future<void> forget() async {
    release();
    try {
      await _store.forget(account);
    } catch (e) {
      debugPrint('[ImsSession] 清除会话失败 account=$account: $e');
    }
  }

  /// 内存 → 磁盘恢复；磁盘也没有时顺带做一次旧版单键迁移。
  Future<String?> _restore() async {
    try {
      var cached = await _store.read(account);
      cached ??= await _store.migrateLegacy(account);
      if (cached == null || cached.isEmpty) {
        _phase = ImsSessionPhase.empty;
        return null;
      }
      _jsessionId = cached;
      _phase = ImsSessionPhase.ready;
      return cached;
    } catch (e) {
      debugPrint('[ImsSession] 读取本地会话失败 account=$account: $e');
      _phase = ImsSessionPhase.empty;
      return null;
    }
  }

  @override
  String toString() =>
      'ImsSession(account=$account, phase=${_phase.name}, '
      'hasSession=$hasSession)';
}
