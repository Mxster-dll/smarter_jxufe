/// 图书馆订阅词云同步 · 远端端口适配器。
///
/// 把「会话管理」收在一处：**首次用到才换票**，会话失效时**只重换一次**再重试
/// （口径与本仓 §12.2「探活优先、失效才换」一致），失败即抛出交由界面如实告知。
library;

import 'package:dartz/dartz.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/auth/data/auth_repository.dart';
import 'package:smarter_jxufe/features/library_sync/data/datasources/libsp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_sync/data/datasources/libsp_subscribe_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_sync/domain/libsp_remote.dart';

/// 走真实网络的 [LibspRemote]。
class LibspRemoteAdapter implements LibspRemote {
  LibspRemoteAdapter({
    required LibspSubscribeRemoteDataSource subscribe,
    required LibspAuthRemoteDataSource auth,
    required AuthRepository authRepository,
    List<String>? trace,
  }) : _subscribe = subscribe,
       _auth = auth,
       _authRepository = authRepository,
       _trace = trace;

  final LibspSubscribeRemoteDataSource _subscribe;
  final LibspAuthRemoteDataSource _auth;
  final AuthRepository _authRepository;

  /// 非空时逐跳记录换证链（调试用；生产传 null）。
  final List<String>? _trace;

  String? _cookie;

  /// 当前会话 Cookie（仅供诊断展示，界面不要显示其内容）。
  bool get hasSession => _cookie != null && LibspAuthRemoteDataSource.hasSession(_cookie!);

  /// 取得（必要时新换）会话 Cookie。
  Future<String> _session({bool force = false}) async {
    final cached = _cookie;
    if (!force && cached != null && LibspAuthRemoteDataSource.hasSession(cached)) {
      return cached;
    }
    final Either<Failure, String> result = await _authRepository
        .getServiceRedirectUrl(LibspAuthRemoteDataSource.casServiceUrl);
    final ticketUrl = result.fold(
      (failure) => throw LibspSessionException(
        '统一认证换票失败：${failure.message}（请确认已在 App 里登录过）',
      ),
      (url) => url,
    );
    _cookie = await _auth.establishSession(ticketUrl, trace: _trace);
    return _cookie!;
  }

  /// 带一次「失效重换」的重试包装。
  Future<T> _withSession<T>(Future<T> Function(String cookie) run) async {
    final cookie = await _session();
    try {
      return await run(cookie);
    } on LibspSessionExpiredException {
      // 只在真失效时重换一次票，避免每次抖动都去打扰 CAS。
      final fresh = await _session(force: true);
      return await run(fresh);
    }
  }

  @override
  Future<List<LibspRemoteWord>> listWords() =>
      _withSession(_subscribe.listWords);

  @override
  Future<void> addWord(String name) =>
      _withSession((cookie) => _subscribe.addWord(cookie, name));

  @override
  Future<void> deleteWord(int subId) =>
      _withSession((cookie) => _subscribe.deleteWord(cookie, subId));
}
