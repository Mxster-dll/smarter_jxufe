import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/dio_factory.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/leave/data/datasources/leave_remote_datasource.dart';
import 'package:smarter_jxufe/features/leave/domain/leave_models.dart';
import 'package:smarter_jxufe/features/platform_guid/data/providers/guid_providers.dart';

/// 请假接口专用 Dio（平台管理域 .edu.cn，与校历/网费同款来源头）。
///
/// 服务端按来源放行：须带 servicewechat 页面 Referer 与浏览器 UA；
/// GUID + bn 签名的鉴权在请求体内（见 [LeaveRemoteDataSource]）。
final leaveDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return createAppDio(
    baseUrl: 'https://wxcourse.jxufe.edu.cn',
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    userAgent: deviceProfileRepo.userAgent,
    headers: {
      'Referer':
          'https://servicewechat.com/wx70c0beda0bb7b021/143/page-frame.html',
      'Accept': 'application/json, text/plain, */*',
    },
  );
});

/// 请假远程数据源。
final leaveRemoteDataSourceProvider = Provider<LeaveRemoteDataSource>(
  (ref) => LeaveRemoteDataSource(ref.watch(leaveDioProvider)),
);

/// 「我的请假」记录列表。
///
/// 前置条件：已登录（学号）+ 已配置平台 GUID。GUID 缺失时抛出面向 UI 的
/// [LeaveApiException]，由页面引导用户去配置。
final leaveListProvider = FutureProvider<List<LeaveListRecord>>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw const LeaveApiException('请先登录后再查看请假记录');
  }
  final guid = await ref.watch(platformGuidProvider.future);
  if (guid == null || guid.trim().isEmpty) {
    throw const LeaveApiException('未配置平台标识（GUID），无法读取请假记录');
  }
  final ds = ref.watch(leaveRemoteDataSourceProvider);
  return ds.fetchList(guid: guid.trim(), wxUsername: account);
});

/// 单条请假详情（信息 + 审批历史）。
final leaveDetailBundleProvider =
    FutureProvider.family<LeaveDetailBundle, String>((ref, instanceId) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw const LeaveApiException('请先登录后再查看请假详情');
  }
  final guid = await ref.watch(platformGuidProvider.future);
  if (guid == null || guid.trim().isEmpty) {
    throw const LeaveApiException('未配置平台标识（GUID），无法读取请假详情');
  }
  final ds = ref.watch(leaveRemoteDataSourceProvider);
  final info = await ds.fetchDetail(
    guid: guid.trim(),
    wxUsername: account,
    instanceId: instanceId,
  );
  List<LeaveApprovalStep> approvals = const [];
  try {
    approvals = await ds.fetchApprovals(
      guid: guid.trim(),
      wxUsername: account,
      instanceId: instanceId,
    );
  } catch (_) {
    // 审批历史非关键路径：失败不阻断详情展示。
  }
  return LeaveDetailBundle(info: info, approvals: approvals);
});
