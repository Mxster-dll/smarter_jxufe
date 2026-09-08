import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/features/electricity/data/datasources/electricity_remote_datasource.dart';
import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';

/// 智慧江财供电服务专用 Dio。
///
/// 服务器按 Referer 放行：无 `servicewechat.com` 来源的裸请求会 403，
/// 因此所有请求固定携带小程序页面来源头。
final electricityDioProvider = Provider<Dio>((ref) {
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

/// 宿舍电费远程数据源。
final electricityRemoteDataSourceProvider = Provider<ElectricityRemoteDataSource>(
  (ref) => ElectricityRemoteDataSource(ref.watch(electricityDioProvider)),
);

/// 电费「学号 → 已绑定宿舍」本地记忆 box。
///
/// key = 学号，value = [RoomBindingRecord] 的 JSON。
/// 进入页面时凭记忆免选宿舍直接查询；更换宿舍后写回。
final electricityBindingBoxProvider = FutureProvider<Box<String>>(
  (ref) => Hive.openBox<String>('electricityBinding'),
);

