import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/network_service/data/datasources/network_service_remote_datasource.dart';
import 'package:smarter_jxufe/features/network_service/domain/network_service_models.dart';

/// 未配置平台标识时的提示（与网费段口径一致，页面据此给「启用实时源」入口）。
const String kNetworkServiceNeedGuid = '未配置微信平台标识（GUID），无法读取网络服务数据';

/// 网络服务数据源（与网费共用同一个 Dio：同域、同 Referer / UA 口径）。
final networkServiceDataSourceProvider =
    Provider<NetworkServiceRemoteDataSource>(
      (ref) => NetworkServiceRemoteDataSource(ref.watch(netFeeDioProvider)),
    );

/// 平台 GUID（与网费 / 校历共用 Hive `wxPlatform` 的 `guid` 键）。
final networkServiceGuidProvider = FutureProvider<String?>((ref) async {
  final guid = await ref.watch(netFeeGuidProvider.future);
  final trimmed = guid?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
});

/// 取 GUID，未配置即抛（消息带 [NetworkServiceException.needGuid]）。
Future<String> requireNetworkServiceGuid(Ref ref) async {
  final guid = await ref.watch(networkServiceGuidProvider.future);
  if (guid == null) {
    throw const NetworkServiceException(
      kNetworkServiceNeedGuid,
      needGuid: true,
    );
  }
  return guid;
}

NetworkServiceRemoteDataSource _source(Ref ref) =>
    ref.watch(networkServiceDataSourceProvider);

/// 账号概览（余额 / 套餐 / 状态 / 本周期用量 / 有效期）。
final networkAccountProvider = FutureProvider<NetworkAccount>((ref) async {
  final guid = await requireNetworkServiceGuid(ref);
  return _source(ref).fetchAccount(guid);
});

/// 在线会话（可强制下线）。
final networkOnlineSessionsProvider =
    FutureProvider<List<NetworkOnlineSession>>((ref) async {
      final guid = await requireNetworkServiceGuid(ref);
      return _source(ref).fetchOnlineSessions(guid);
    });

/// 近期上网记录（首页表，5 条）。
final networkLoginHistoryProvider = FutureProvider<List<NetworkLoginRecord>>((
  ref,
) async {
  final guid = await requireNetworkServiceGuid(ref);
  return _source(ref).fetchLoginHistory(guid);
});

/// 上网记录明细（按日期窗口）。
final networkUsageRecordsProvider =
    FutureProvider.family<List<NetworkUsageRecord>, NetworkUsageQuery>((
      ref,
      query,
    ) async {
      final guid = await requireNetworkServiceGuid(ref);
      return _source(
        ref,
      ).fetchUsageRecords(guid, from: query.from, to: query.to);
    });

/// 历史账单（按年）。
final networkMonthBillsProvider = FutureProvider.family<NetworkMonthBills, int>(
  (ref, year) async {
    final guid = await requireNetworkServiceGuid(ref);
    return _source(ref).fetchMonthBills(guid, year);
  },
);

/// 充值明细。
final networkPaymentsProvider = FutureProvider<List<NetworkPayment>>((
  ref,
) async {
  final guid = await requireNetworkServiceGuid(ref);
  return _source(ref).fetchPayments(guid);
});

/// 业务办理记录。
final networkOperatorLogsProvider = FutureProvider<List<NetworkOperatorLog>>((
  ref,
) async {
  final guid = await requireNetworkServiceGuid(ref);
  return _source(ref).fetchOperatorLogs(guid);
});

/// 我的设备（含在线状态，可解绑）。
final networkDevicesProvider = FutureProvider<List<NetworkDevice>>((ref) async {
  final guid = await requireNetworkServiceGuid(ref);
  return _source(ref).fetchDevices(guid);
});

/// 资费介绍（可选套餐与价格）。
final networkPlansProvider = FutureProvider<List<NetworkPlan>>((ref) async {
  final guid = await requireNetworkServiceGuid(ref);
  return _source(ref).fetchPlans(guid);
});

/// 报停记录。
final networkStopLogsProvider = FutureProvider<List<NetworkOperationLog>>((
  ref,
) async {
  final guid = await requireNetworkServiceGuid(ref);
  return _source(ref).fetchStopLogs(guid);
});

/// 复通记录。
final networkReopenLogsProvider = FutureProvider<List<NetworkOperationLog>>((
  ref,
) async {
  final guid = await requireNetworkServiceGuid(ref);
  return _source(ref).fetchReopenLogs(guid);
});

/// 预约套餐日志。
final networkPackageLogsProvider = FutureProvider<List<NetworkPackageLog>>((
  ref,
) async {
  final guid = await requireNetworkServiceGuid(ref);
  return _source(ref).fetchPackageLogs(guid);
});

/// 预约套餐页可选套餐 + 下单 csrftoken。
final networkPackageOptionsProvider = FutureProvider<NetworkPackageOptions>((
  ref,
) async {
  final guid = await requireNetworkServiceGuid(ref);
  return _source(ref).fetchPackageOptions(guid);
});

/// 网络服务整组 provider（失效用；family 也按「provider 本身」失效整族）。
final List<ProviderOrFamily> networkServiceProviders = <ProviderOrFamily>[
  networkAccountProvider,
  networkOnlineSessionsProvider,
  networkLoginHistoryProvider,
  networkUsageRecordsProvider,
  networkMonthBillsProvider,
  networkPaymentsProvider,
  networkOperatorLogsProvider,
  networkDevicesProvider,
  networkPlansProvider,
  networkStopLogsProvider,
  networkReopenLogsProvider,
  networkPackageLogsProvider,
  networkPackageOptionsProvider,
];

/// 失效整组网络服务数据（下拉刷新 / 写操作后对账 / 会话重登后调用）。
///
/// ⚠ 家庭 provider（family）不需要逐个清 —— 传「provider 本身」即清掉整族实例。
void invalidateNetworkService(WidgetRef ref) {
  for (final provider in networkServiceProviders) {
    ref.invalidate(provider);
  }
}

/// [invalidateNetworkService] 的 `Ref` 版本（provider 内部用）。
void invalidateNetworkServiceIn(Ref ref) {
  for (final provider in networkServiceProviders) {
    ref.invalidate(provider);
  }
}
