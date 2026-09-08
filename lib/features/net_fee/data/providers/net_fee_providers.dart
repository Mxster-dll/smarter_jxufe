import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/net_fee/data/datasources/net_fee_remote_datasource.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';

/// 网费计费域专用 Dio（智慧江财平台，与电费/校历同源反代）。
///
/// 服务器按来源放行：必须携带 servicewechat 页面 Referer 与浏览器 UA；
/// checkAppAuth 走管理域绝对 URL（https://wxcourse.jxufe.edu.cn），
/// 业务接口走本 base（https://wxcourse.jxufe.cn）。
final netFeeDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return Dio(
    BaseOptions(
      baseUrl: 'https://wxcourse.jxufe.cn',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (status) => true,
      headers: {
        'User-Agent': deviceProfileRepo.userAgent,
        'Referer':
            'https://servicewechat.com/wx70c0beda0bb7b021/143/page-frame.html',
        'Accept': 'application/json, text/plain, */*',
      },
    ),
  );
});

/// 微信平台配置 Box（与校历 feature 共用同一 Hive box 'wxPlatform'）。
///
/// key 'guid' = 智慧江财平台用户标识（GUID）。校历页填写的配置网费直接复用；
/// 网费页亦可在此读写，两处保持同步。
final netFeePlatformBoxProvider = FutureProvider<Box<String>>(
  (ref) => Hive.openBox<String>('wxPlatform'),
);

/// 已配置的平台 GUID；未配置为 null。
final netFeeGuidProvider = FutureProvider<String?>((ref) async {
  final box = await ref.watch(netFeePlatformBoxProvider.future);
  final guid = box.get('guid');
  if (guid == null || guid.trim().isEmpty) return null;
  return guid.trim();
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
    throw const NetFeeApiException('请先登录后再查看网费');
  }
  final guid = await ref.watch(netFeeGuidProvider.future);
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
