import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/volunteer_hours_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/ssp_auth_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/volunteer_hours_repository.dart';

/// 志愿服务时长数据源提供者。
final volunteerHoursDataSourceProvider =
    Provider<VolunteerHoursRemoteDataSource>((ref) {
      return VolunteerHoursRemoteDataSource(ref.watch(sspDioProvider));
    });

/// 志愿服务时长业务仓库（内含会话缓存/刷新逻辑）。
final volunteerHoursRepositoryProvider =
    FutureProvider<VolunteerHoursRepository>((ref) async {
      final sspAuthRepository = await ref.watch(
        sspAuthRepositoryProvider.future,
      );
      return VolunteerHoursRepository(
        sspAuthRepository: sspAuthRepository,
        remoteDataSource: ref.watch(volunteerHoursDataSourceProvider),
      );
    });

/// 当前账户的志愿服务活动列表。
///
/// 首次进入会自动换取综合管理平台会话；会话过期时自动刷新并重试一次。
final volunteerActivitiesProvider = FutureProvider<List<VolunteerActivity>>((
  ref,
) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw Exception('请先登录后再查看志愿服务时长');
  }
  final repository = await ref.watch(volunteerHoursRepositoryProvider.future);
  return repository.fetchActivities(account);
});
