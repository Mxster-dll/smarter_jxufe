import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/jh_read_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/jh_read_record.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/ssp_auth_repository.dart';

/// 蛟湖阅读业务仓库。
///
/// 组合 [SspAuthRepository]（会话管理）与 [JhReadRemoteDataSource]（数据拉取）：
/// - 会话过期 → 自动刷新并重试一次；
/// - 反复过期 → 抛出明确错误。
class JhReadRepository {
  final SspAuthRepository _sspAuthRepository;
  final JhReadRemoteDataSource _remoteDataSource;

  JhReadRepository({
    required SspAuthRepository sspAuthRepository,
    required JhReadRemoteDataSource remoteDataSource,
  }) : _sspAuthRepository = sspAuthRepository,
       _remoteDataSource = remoteDataSource;

  /// 拉取指定账户的蛟湖阅读考核记录。
  Future<List<JhReadRecord>> fetchReadRecords({
    required String account,
    required String studentName,
  }) async {
    final sessionId = await _sspAuthRepository.getSessionId(account);
    try {
      return await _remoteDataSource.fetchReadRecords(
        sessionId: sessionId,
        studentName: studentName,
      );
    } on SspSessionExpiredException {
      // 会话过期 → 走统一认证重新换取后重试一次
      final freshSessionId = await _sspAuthRepository.refreshSessionId(account);
      try {
        return await _remoteDataSource.fetchReadRecords(
          sessionId: freshSessionId,
          studentName: studentName,
        );
      } on SspSessionExpiredException {
        throw Exception('综合管理平台会话刷新失败，请稍后重试');
      }
    }
  }
}
