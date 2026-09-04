import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/constants/hive_box_names.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/ssp_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/ssp_auth_repository.dart';

/// 综合管理服务平台专用 Dio。
///
/// 注意：不预设 Cookie / Referer 默认头——
/// 每个请求的会话 Cookie 由会话仓库显式传入，
/// 避免再出现「硬编码一个过期 JSESSIONID」的问题。
final sspDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return Dio(
    BaseOptions(
      baseUrl: 'http://ssp.jxufe.edu.cn',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => true,
      followRedirects: false,
      headers: {
        'User-Agent': deviceProfileRepo.userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,'
            'image/avif,image/webp,image/apng,*/*;q=0.8,'
            'application/signed-exchange;v=b3;q=0.7',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
      },
    ),
  );
});

/// 综合管理平台会话存储 Box。
final sspAuthBoxProvider = FutureProvider<Box<String>>(
  (ref) => Hive.openBox<String>(sspAuthBoxName),
);

final sspAuthLocalDataSourceProvider = FutureProvider<SspAuthLocalDataSource>((
  ref,
) async {
  final box = await ref.watch(sspAuthBoxProvider.future);
  return SspAuthLocalDataSource(box);
});

final sspAuthRemoteDataSourceProvider = Provider<SspAuthRemoteDataSource>(
  (ref) => SspAuthRemoteDataSource(ref.watch(sspDioProvider)),
);

/// 会话仓库：依赖统一认证的 [AuthRepository]（keepAlive 单例），
/// TGC 过期时其内部会自动走重登（含 MFA 弹窗）。
final sspAuthRepositoryProvider = FutureProvider<SspAuthRepository>((
  ref,
) async {
  final localDataSource = await ref.watch(
    sspAuthLocalDataSourceProvider.future,
  );
  final remoteDataSource = ref.watch(sspAuthRemoteDataSourceProvider);
  final authRepository = await ref.watch(authRepositoryProvider.future);
  return SspAuthRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    authRepository: authRepository,
  );
});
