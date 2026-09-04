import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/second_class_credit_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/second_class_credit.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/ssp_auth_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/second_class_credit_repository.dart';

/// 第二课堂学分数据源提供者。
final secondClassCreditDataSourceProvider =
    Provider<SecondClassCreditRemoteDataSource>((ref) {
      return SecondClassCreditRemoteDataSource(ref.watch(sspDioProvider));
    });

/// 第二课堂学分业务仓库（内含会话缓存/刷新逻辑）。
final secondClassCreditRepositoryProvider =
    FutureProvider<SecondClassCreditRepository>((ref) async {
      final sspAuthRepository = await ref.watch(
        sspAuthRepositoryProvider.future,
      );
      return SecondClassCreditRepository(
        sspAuthRepository: sspAuthRepository,
        remoteDataSource: ref.watch(secondClassCreditDataSourceProvider),
      );
    });

/// 当前账户的第二课堂学分总览。
///
/// 首次进入自动换取综合管理平台会话；会话过期时自动刷新并重试一次。
final secondClassCreditOverviewProvider = FutureProvider<SecondClassOverview>((
  ref,
) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw Exception('请先登录后再查看第二课堂学分');
  }
  final repository = await ref.watch(
    secondClassCreditRepositoryProvider.future,
  );
  return repository.fetchOverview(account);
});
