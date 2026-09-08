import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/features/school_calendar/data/datasources/wxcal_remote_datasource.dart';
import 'package:smarter_jxufe/features/school_calendar/data/wxcal_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 智慧江财平台用户标识（GUID）存储 box：key `guid`。
///
/// GUID 仅微信授权「智慧江财」可得（等同账号标识），App 设置中由用户自填；
/// 不配置则小程序校历数据走内置离线快照。
final wxPlatformBoxProvider = FutureProvider<Box<String>>(
  (ref) => Hive.openBox<String>('wxPlatform'),
);

/// 平台 GUID（可能为 null）。
final wxGuidProvider = FutureProvider<String?>((ref) async {
  final box = await ref.watch(wxPlatformBoxProvider.future);
  return box.get('guid');
});

/// 小程序校历专用 Dio（base wxcourse.jxufe.cn + 小程序来源头）。
final wxcalDioProvider = Provider<Dio>((ref) {
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
        'Content-Type': 'application/json',
      },
    ),
  );
});

/// 全部学期官方安排（实时优先，离线兜底）。
///
/// GUID 未配置（[wxGuidProvider] 为 null）或实时请求失败时回退内置快照。
final wxArrangementsProvider = FutureProvider<List<WxSemesterArrangement>>(
  (ref) async {
    final guid = await ref.watch(wxGuidProvider.future);
    final repo = WxcalRepository(
      guid: guid,
      live: WxcalRemoteDataSource(ref.watch(wxcalDioProvider)),
    );
    return repo.fetchAll();
  },
);
