import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/jh_read_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/jh_read_repository.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/jh_read_record.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/ssp_auth_providers.dart';

/// 蛟湖阅读数据源提供者。
final jhReadDataSourceProvider = Provider<JhReadRemoteDataSource>((ref) {
  return JhReadRemoteDataSource(ref.watch(sspDioProvider));
});

/// 蛟湖阅读业务仓库（内含 SSP 会话缓存/刷新逻辑）。
final jhReadRepositoryProvider = FutureProvider<JhReadRepository>((ref) async {
  final sspAuthRepository = await ref.watch(sspAuthRepositoryProvider.future);
  return JhReadRepository(
    sspAuthRepository: sspAuthRepository,
    remoteDataSource: ref.watch(jhReadDataSourceProvider),
  );
});

/// 当前账户的姓名（displayName），用于 SSP 详单按姓名过滤。
final currentStudentNameProvider = FutureProvider<String>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) return '';

  final repo = await ref.watch(accountRepositoryProvider.future);
  final result = repo.getAccounts();
  return result.fold((_) => '', (accounts) {
    for (final a in accounts) {
      if (a.cardNumber == account && a.displayName.isNotEmpty) {
        return a.displayName;
      }
    }
    return '';
  });
});

/// 当前账户的蛟湖阅读考核记录。
///
/// 首次进入会自动换取综合管理平台会话；会话过期时自动刷新并重试一次。
final jhReadRecordsProvider = FutureProvider<List<JhReadRecord>>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw Exception('请先登录后再查看蛟湖阅读情况');
  }
  final studentName = await ref.watch(currentStudentNameProvider.future);
  if (studentName.isEmpty) {
    throw Exception('暂无法获取当前学生姓名，无法查询蛟湖阅读记录');
  }
  final repository = await ref.watch(jhReadRepositoryProvider.future);
  return repository.fetchReadRecords(
    account: account,
    studentName: studentName,
  );
});
