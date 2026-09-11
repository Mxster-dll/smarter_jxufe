import 'package:dio/dio.dart';
import 'package:riverpod/riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_session_provider.dart';

/// 当前登录账户卡号（学号）。
///
/// 定义已迁至 `current_account_provider.dart`（打断与 `imsSessionProvider`
/// 的循环依赖），此处**转出**，既有 `import 'dio_providers.dart'` 的调用方
/// 无需改动。
export 'package:smarter_jxufe/core/network/current_account_provider.dart';

/// 当前 IMS Dio = **全局唯一会话**持有的那一个。
///
/// 所有教务数据源（成绩 / 课表 / 学籍 / 培养方案 / 毕业学分 / 加权 / 调课）
/// 都从这里取 Dio，因此：
/// - 会话（含 JSESSIONID、失效自动换票的重试拦截器）全 App 只有一份；
/// - 切换账号时 `imsSessionProvider` 随 `currentAccountProvider` 重建，
///   本 provider 随之换到新实例（旧实例 `release`）。
///
/// 会话实现与口径见 `lib/features/ims/auth/data/ims_session.dart`。
final currentImsDioProvider = Provider<Dio>(
  (ref) => ref.watch(imsSessionProvider).dio,
);

/// 按账户卡号分例的 Login（CAS 统一登录）Dio。
///
/// CAS 侧无可复用的会话状态，仅承载登录流程，因此仍按账号分例即可。
final loginDioProvider = Provider.family<Dio, String>((ref, account) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://ssl.jxufe.edu.cn',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (status) => true,
      followRedirects: false,
      headers: {'User-Agent': deviceProfileRepo.userAgent},
    ),
  );
  // applyFiddlerProxy(dio); // [DEBUG] 抓包用，发布前取消注释
  return dio;
});

/// 当前账户的 Login Dio，由 [currentAccountProvider] 驱动。
final currentLoginDioProvider = Provider<Dio>((ref) {
  final account = ref.watch(currentAccountProvider);
  return ref.watch(loginDioProvider(account));
});
