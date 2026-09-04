import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/constants/hive_box_names.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/data_center/data/data_center_repository.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/dzj_auth_repository.dart';
import 'package:smarter_jxufe/features/data_center/data/models/data_center_models.dart';

/// 竹简数据中台专用 Dio（https）。
///
/// 注意：不预设 Cookie 默认头，会话 Cookie 由各数据源显式携带。
final dzjDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return Dio(
    BaseOptions(
      baseUrl: 'https://dzj.jxufe.edu.cn',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => true,
      headers: {
        'User-Agent': deviceProfileRepo.userAgent,
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
      },
    ),
  );
});

/// 竹简会话存储 Box。
final dzjAuthBoxProvider = FutureProvider<Box<String>>(
  (ref) => Hive.openBox<String>(dzjAuthBoxName),
);

final dzjAuthLocalDataSourceProvider = FutureProvider<DzjAuthLocalDataSource>((
  ref,
) async {
  final box = await ref.watch(dzjAuthBoxProvider.future);
  return DzjAuthLocalDataSource(box);
});

final dzjAuthRemoteDataSourceProvider = Provider<DzjAuthRemoteDataSource>(
  (ref) => DzjAuthRemoteDataSource(ref.watch(dzjDioProvider)),
);

final dzjApiRemoteDataSourceProvider = Provider<DzjApiRemoteDataSource>(
  (ref) => DzjApiRemoteDataSource(ref.watch(dzjDioProvider)),
);

/// 会话仓库：TGC 过期时内部自动重登（含 MFA 弹窗）。
final dzjAuthRepositoryProvider = FutureProvider<DzjAuthRepository>((
  ref,
) async {
  final localDataSource = await ref.watch(
    dzjAuthLocalDataSourceProvider.future,
  );
  final remoteDataSource = ref.watch(dzjAuthRemoteDataSourceProvider);
  final authRepository = await ref.watch(authRepositoryProvider.future);
  return DzjAuthRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    authRepository: authRepository,
  );
});

/// 个人数据中心业务仓库。
final dataCenterRepositoryProvider = FutureProvider<DataCenterRepository>((
  ref,
) async {
  final dzjAuthRepository = await ref.watch(dzjAuthRepositoryProvider.future);
  return DataCenterRepository(
    authRepository: dzjAuthRepository,
    remoteDataSource: ref.watch(dzjApiRemoteDataSourceProvider),
  );
});

/// 当前账户的个人数据中心全量概览。
///
/// 首次进入自动换取数据中台会话（TGC 过期自动重登）；整批失败自动
/// 刷新会话并重试一次。
final dataCenterOverviewProvider = FutureProvider<DataCenterOverview>((
  ref,
) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw Exception('请先登录后再查看个人数据中心');
  }
  final repository = await ref.watch(dataCenterRepositoryProvider.future);
  return repository.fetchOverview(account);
});
