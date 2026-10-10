import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/dio_factory.dart';

import 'package:smarter_jxufe/features/platform_guid/data/providers/guid_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/datasources/wxcal_remote_datasource.dart';
import 'package:smarter_jxufe/features/school_calendar/data/wxcal_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 内置离线学期快照（同步可得，无需 GUID）。
///
/// 「当下学期」判定（[currentSchoolTerm]）与教学周推算（[resolveTeachingWeek]）
/// 都要按**日期区间**定位学期，故需要一个同步数据源 —— 实时校历是异步的，
/// 首帧拿不到。快照覆盖 2017 秋 ~ 2026 秋，见 wxcal_offline_data.dart。
final offlineSemesterTermsProvider = Provider<List<WxSemesterArrangement>>(
  (ref) => wxcalOfflineToDomain(),
);

/// 小程序校历专用 Dio（base wxcourse.jxufe.cn + 小程序来源头）。
final wxcalDioProvider = Provider<Dio>((ref) {
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
      'Content-Type': 'application/json',
    },
  );
});

/// 全部学期官方安排（实时优先，离线兜底）。
///
/// 实时需要**两样都齐**：用户在设置里填的平台 GUID（[platformGuidProvider]）
/// 与构建期注入的平台 appSecret（`--dart-define=BN_APP_SECRET=…`）。缺任何一样
/// 都回退内置快照 —— 后者是正常路径，不是降级异常（离线快照覆盖 2017 秋 ~ 2026 秋）。
final wxArrangementsProvider = FutureProvider<List<WxSemesterArrangement>>(
  (ref) async {
    final guid = await ref.watch(platformGuidProvider.future);
    final repo = WxcalRepository(
      guid: guid,
      secret: bnAppSecret,
      live: WxcalRemoteDataSource(ref.watch(wxcalDioProvider)),
    );
    return repo.fetchAll();
  },
);
