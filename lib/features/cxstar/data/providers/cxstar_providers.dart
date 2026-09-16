/// 畅想之星「经典阅读」provider 链。
///
/// 会话三档（用户 2026-09-12 目标：拿到**个人**阅读本数与时长）：
/// 1. **统一身份认证**（首选）= 复用项目既有 CAS TGC →
///    `ua.cxstar.com/uniauth/outLogin/login517` → 个人 JWT，按账号持久化 24h；
/// 2. **手工令牌**（高级回退）= 用户从浏览器/抓包粘贴的个人 token；
/// 3. **校园网 IP 免密**（兜底）= `POST /api/auth/ip_login` 的 `IP用户`
///    公用账号，数据为全校聚合，界面必须标注。
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/cxstar/data/cxstar_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/data/cxstar_auth_repository.dart';
import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/data/datasources/cxstar_remote_datasource.dart';
import 'package:smarter_jxufe/features/cxstar/domain/cxstar_models.dart';

/// 会话与手工令牌共用的存储 box。
const String cxstarBoxName = CxstarAuthLocalDataSource.boxName;

/// 手工令牌 key（高级回退；统一认证会话用 `cxstar_tk_<账号>`）。
const String cxstarTokenKey = 'token';

/// 畅想之星业务 Dio（base m.cxstar.com；接口必须在 `/api` 前缀下）。
final cxstarDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return Dio(
    BaseOptions(
      baseUrl: 'https://m.cxstar.com',
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (status) => true,
      followRedirects: true,
      headers: {
        'User-Agent': deviceProfileRepo.userAgent,
        'Referer': 'https://m.cxstar.com/',
        'Accept': 'application/json, text/plain, */*',
      },
    ),
  );
});

/// 换证链专用 Dio：**不自动跟随重定向**（要逐跳检查 token 落在哪一跳）。
final cxstarAuthDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return Dio(
    BaseOptions(
      baseUrl: CxstarAuthRemoteDataSource.origin,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => true,
      followRedirects: false,
      headers: {
        'User-Agent': deviceProfileRepo.userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,'
            'image/avif,image/webp,image/apng,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      },
    ),
  );
});

final cxstarRemoteDataSourceProvider = Provider<CxstarRemoteDataSource>(
  (ref) => CxstarRemoteDataSource(ref.watch(cxstarDioProvider)),
);

final cxstarAuthRemoteDataSourceProvider =
    Provider<CxstarAuthRemoteDataSource>(
      (ref) =>
          CxstarAuthRemoteDataSource(ref.watch(cxstarAuthDioProvider)),
    );

final cxstarTokenBoxProvider = FutureProvider<Box<String>>(
  (ref) => Hive.openBox<String>(cxstarBoxName),
);

final cxstarAuthLocalDataSourceProvider =
    FutureProvider<CxstarAuthLocalDataSource>((ref) async {
      final box = await ref.watch(cxstarTokenBoxProvider.future);
      return CxstarAuthLocalDataSource(box);
    });

/// 统一认证会话仓库（TGC 过期由 [authRepositoryProvider] 内部静默重登）。
final cxstarAuthRepositoryProvider = FutureProvider<CxstarAuthRepository>((
  ref,
) async {
  final local = await ref.watch(cxstarAuthLocalDataSourceProvider.future);
  final remote = ref.watch(cxstarAuthRemoteDataSourceProvider);
  final authRepository = await ref.watch(authRepositoryProvider.future);
  return CxstarAuthRepository(
    localDataSource: local,
    remoteDataSource: remote,
    authRepository: authRepository,
  );
});

/// 用户手工粘贴的个人令牌；未配置为 null。
final cxstarPersonalTokenProvider = FutureProvider<String?>((ref) async {
  final box = await ref.watch(cxstarTokenBoxProvider.future);
  final token = box.get(cxstarTokenKey);
  if (token == null || token.trim().isEmpty) return null;
  return token.trim();
});

/// 页面聚合：账号 + 统计 + 逐书记录。
///
/// 取数顺序：统一认证个人会话 → 手工令牌 → 校园网 IP 公用账号兜底；
/// `CxstarOverview.source` / `fallbackNote` 反映真实来源，界面必须据此标注。
final cxstarOverviewProvider = FutureProvider<CxstarOverview>((ref) async {
  final dataSource = ref.watch(cxstarRemoteDataSourceProvider);
  final account = ref.watch(currentAccountProvider);
  String? fallbackNote;

  // ① 统一身份认证（首选，个人口径）。
  if (account.isNotEmpty) {
    try {
      final authRepository = await ref.watch(
        cxstarAuthRepositoryProvider.future,
      );
      var token = await authRepository.getSessionToken(account);
      if (token != null) {
        try {
          return await _load(
            dataSource,
            token,
            source: CxstarSessionSource.unifiedAuth,
          );
        } on CxstarApiException catch (e) {
          // 会话过期（JWT 24h）→ 强制重换一次。
          fallbackNote = '统一认证会话已过期（$e），已尝试重新获取';
          token = await authRepository.getSessionToken(
            account,
            forceRefresh: true,
          );
          if (token != null) {
            try {
              return await _load(
                dataSource,
                token,
                source: CxstarSessionSource.unifiedAuth,
              );
            } on CxstarApiException catch (e2) {
              fallbackNote = '统一认证会话不可用：$e2';
            }
          }
        }
      } else {
        fallbackNote = '未能通过统一身份认证取得畅想之星会话';
      }
    } catch (e) {
      fallbackNote = '统一身份认证换取失败：$e';
    }
  }

  // ② 手工令牌（高级回退）。
  final manual = await ref.watch(cxstarPersonalTokenProvider.future);
  if (manual != null) {
    try {
      return await _load(
        dataSource,
        manual,
        source: CxstarSessionSource.manualToken,
      );
    } on CxstarApiException catch (e) {
      fallbackNote = '手工令牌不可用：$e';
    }
  }

  // ③ 校园网 IP 免密（公用账号，全校聚合）。
  final token = await dataSource.ipLogin();
  return _load(
    dataSource,
    token,
    source: CxstarSessionSource.ipShared,
    fallbackNote: fallbackNote,
  );
});

Future<CxstarOverview> _load(
  CxstarRemoteDataSource dataSource,
  String token, {
  required CxstarSessionSource source,
  String? fallbackNote,
}) async {
  final user = await dataSource.fetchUser(token);
  final summary = await dataSource.fetchSummary(token);
  final records = await dataSource.fetchRecords(token);
  return CxstarOverview(
    user: user,
    summary: summary,
    records: records,
    source: source,
    fallbackNote: fallbackNote,
  );
}
