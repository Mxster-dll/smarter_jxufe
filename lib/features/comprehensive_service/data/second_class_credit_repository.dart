import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/second_class_credit_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/second_class_credit.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/ssp_auth_repository.dart';

/// 第二课堂学分业务仓库。
///
/// 组合 [SspAuthRepository]（会话管理）与
/// [SecondClassCreditRemoteDataSource]（数据拉取）：
/// - 首次进入自动换取并持久化 JSESSIONID；
/// - 会话过期自动刷新后重试一次；
/// - 反复过期向上抛出明确错误。
class SecondClassCreditRepository {
  final SspAuthRepository _sspAuthRepository;
  final SecondClassCreditRemoteDataSource _remoteDataSource;

  SecondClassCreditRepository({
    required SspAuthRepository sspAuthRepository,
    required SecondClassCreditRemoteDataSource remoteDataSource,
  }) : _sspAuthRepository = sspAuthRepository,
       _remoteDataSource = remoteDataSource;

  /// 拉取指定账户的第二课堂学分总览（成绩单 + 预警板）。
  Future<SecondClassOverview> fetchOverview(String account) async {
    final sessionId = await _sspAuthRepository.getSessionId(account);
    try {
      return await _fetchWithSession(sessionId);
    } on SspSessionExpiredException {
      // 会话过期 → 走统一认证重新换取后重试一次
      final freshSessionId = await _sspAuthRepository.refreshSessionId(account);
      try {
        return await _fetchWithSession(freshSessionId);
      } on SspSessionExpiredException {
        throw Exception('综合管理平台会话刷新失败，请稍后重试');
      }
    }
  }

  Future<SecondClassOverview> _fetchWithSession(String sessionId) async {
    final results = await Future.wait([
      _remoteDataSource.fetchCreditReport(sessionId: sessionId),
      _remoteDataSource.fetchCreditBoard(sessionId: sessionId),
    ]);
    final report = results[0] as SecondClassCreditReport;
    final board = results[1] as CreditBoardData;
    return SecondClassOverview(
      report: report,
      boardRows: board.rows,
      milestones: board.milestones,
      totalRequired: board.totalRequired,
      totalPassed: board.totalPassed,
    );
  }
}
