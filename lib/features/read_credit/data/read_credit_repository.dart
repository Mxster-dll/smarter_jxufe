/// 阅读学分业务仓库：带会话调用 + 会话失效自动刷新重试一次。
library;

import 'package:smarter_jxufe/features/read_credit/data/datasources/read_credit_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/read_credit/data/datasources/read_credit_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/read_credit/data/read_credit_auth_repository.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';

class ReadCreditRepository {
  final ReadCreditAuthRepository _auth;
  final ReadCreditApiRemoteDataSource _api;

  ReadCreditRepository({
    required ReadCreditAuthRepository auth,
    required ReadCreditApiRemoteDataSource api,
  }) : _auth = auth,
       _api = api;

  Future<T> _withSession<T>(
    String account,
    Future<T> Function(String cookie) run,
  ) async {
    final cookie = await _auth.getSessionCookie(account);
    try {
      return await run(cookie);
    } on ReadCreditSessionExpiredException {
      final fresh = await _auth.refreshSessionCookie(account);
      return run(fresh);
    }
  }

  /// 学分查询（5 项达标 + 学分状态）。
  Future<ReadCreditScore> fetchScore(String account) =>
      _withSession(account, _api.fetchScore);

  /// 某一项的明细表。
  Future<ReadCreditDetail> fetchDetail(String account, ReadCreditKind kind) =>
      _withSession(account, (cookie) => _api.fetchDetail(cookie, kind));
}
