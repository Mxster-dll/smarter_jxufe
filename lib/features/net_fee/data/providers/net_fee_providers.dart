import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/dio_factory.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/net_fee/data/datasources/net_fee_recharge_remote_datasource.dart';
import 'package:smarter_jxufe/features/net_fee/data/datasources/net_fee_remote_datasource.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_recharge.dart';
import 'package:smarter_jxufe/features/platform_guid/data/providers/guid_providers.dart';

/// 网费计费域专用 Dio（智慧江财平台，与电费/校历同源反代）。
///
/// 服务器按来源放行：必须携带 servicewechat 页面 Referer 与浏览器 UA；
/// checkAppAuth 走管理域绝对 URL（https://wxcourse.jxufe.edu.cn），
/// 业务接口走本 base（https://wxcourse.jxufe.cn）。
final netFeeDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return createAppDio(
    baseUrl: 'https://wxcourse.jxufe.cn',
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

/// 网费远程数据源。
final netFeeRemoteDataSourceProvider = Provider<NetFeeRemoteDataSource>(
  (ref) => NetFeeRemoteDataSource(ref.watch(netFeeDioProvider)),
);

/// 网费双源汇总（用户拍板：双源兜底）。
///
/// - 已配置 GUID → 小程序实时计费源（余额 + 近一年充值记录）；
///   实时源拉取失败自动回退门户概览，并携带 [NetFeeSummary.liveError]。
/// - 未配置 GUID → 门户个人数据中心概览源（仅余额，人事表口径非实时）。
final netFeeSummaryProvider = FutureProvider<NetFeeSummary>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw const NetFeeApiException('请先登录后再查看校园网');
  }
  final guid = await ref.watch(platformGuidProvider.future);
  if (guid == null) {
    return _fetchPortal(ref, account, hasGuid: false);
  }
  final dataSource = ref.watch(netFeeRemoteDataSourceProvider);
  try {
    final enc = await dataSource.fetchEncUserId(guid);
    final accountInfo = await dataSource.fetchBalance(enc);
    final records = await dataSource.fetchRecords(enc);
    return NetFeeSummary(
      source: NetFeeSource.wxLive,
      hasGuid: true,
      balance: accountInfo.balance,
      username: accountInfo.username.isEmpty ? account : accountInfo.username,
      records: records,
    );
  } catch (e) {
    // 实时源异常（GUID 失效 / 网络 / 接口变动）→ 门户兜底。
    return _fetchPortal(ref, account, hasGuid: true, liveError: '$e');
  }
});

/// 校方收银台专用 Dio（`self.jxufe.cn`）。
///
/// ⚠ **不能复用 [netFeeDioProvider]**：那是 wxcourse 小程序平台（baseUrl 与
/// servicewechat Referer），而收银台的 Referer 必须是它**自己页面**的地址 ——
/// 缺了直接 `403 Illegal Referer`（真机踩过）。UA 仍取同一份设备档案。
final netFeeWebPayDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return createAppDio(
    baseUrl: kNetFeeWebPayOrigin,
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    userAgent: deviceProfileRepo.userAgent,
    headers: {'Accept': 'text/html,application/json,*/*'},
  );
});

/// 校方收银台数据源（下单 / 二维码 / 轮询）。
///
/// **非 autoDispose**：一次充值里「下单 → 取二维码 → 轮询订单」要共用同一份会话
/// （`JSESSIONID` 绑着订单），中途重建就查不到自己那笔单了。
final netFeeRechargeRemoteDataSourceProvider =
    Provider<NetFeeRechargeRemoteDataSource>(
      (ref) =>
          NetFeeRechargeRemoteDataSource(ref.watch(netFeeWebPayDioProvider)),
    );

/// 门户个人数据中心源兜底拉取。
Future<NetFeeSummary> _fetchPortal(
  Ref ref,
  String account, {
  required bool hasGuid,
  String? liveError,
}) async {
  double? balance;
  try {
    final repository = await ref.watch(dataCenterRepositoryProvider.future);
    balance = await repository.fetchNetworkBalanceOnly(account);
  } catch (_) {
    balance = null;
  }
  return NetFeeSummary(
    source: balance != null ? NetFeeSource.portal : NetFeeSource.none,
    hasGuid: hasGuid,
    balance: balance,
    username: account,
    liveError: liveError,
  );
}
