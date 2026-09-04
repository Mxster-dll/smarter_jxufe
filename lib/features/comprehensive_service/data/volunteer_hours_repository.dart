import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/volunteer_hours_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/ssp_auth_repository.dart';

/// 志愿服务时长业务仓库。
///
/// 组合 [SspAuthRepository]（会话管理）与
/// [VolunteerHoursRemoteDataSource]（数据拉取），实现：
/// - 首次进入：自动换取并持久化 JSESSIONID；
/// - 会话过期：自动刷新会话后重试一次；
/// - 反复过期：向上抛出明确错误，交由 UI 提示用户。
class VolunteerHoursRepository {
  final SspAuthRepository _sspAuthRepository;
  final VolunteerHoursRemoteDataSource _remoteDataSource;

  VolunteerHoursRepository({
    required SspAuthRepository sspAuthRepository,
    required VolunteerHoursRemoteDataSource remoteDataSource,
  }) : _sspAuthRepository = sspAuthRepository,
       _remoteDataSource = remoteDataSource;

  /// 拉取指定账户的志愿活动列表。
  Future<List<VolunteerActivity>> fetchActivities(String account) async {
    // 第一次尝试：命中本地持久化会话即直接使用
    final sessionId = await _sspAuthRepository.getSessionId(account);
    try {
      return await _remoteDataSource.fetchVolunteerActivities(
        sessionId: sessionId,
      );
    } on SspSessionExpiredException {
      // 会话过期 → 走统一认证重新换取后重试一次
      final freshSessionId = await _sspAuthRepository.refreshSessionId(account);
      try {
        return await _remoteDataSource.fetchVolunteerActivities(
          sessionId: freshSessionId,
        );
      } on SspSessionExpiredException {
        throw Exception('综合管理平台会话刷新失败，请稍后重试');
      }
    }
  }
}
