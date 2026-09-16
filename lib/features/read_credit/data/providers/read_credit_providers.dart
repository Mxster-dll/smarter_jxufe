/// 阅读学分平台 provider 链。
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/cxstar/data/providers/cxstar_providers.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/features/library_edu/data/providers/tsgxs_providers.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/read_credit/data/datasources/read_credit_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/read_credit/data/datasources/read_credit_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/read_credit/data/read_credit_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/read_credit/data/read_credit_auth_repository.dart';
import 'package:smarter_jxufe/features/read_credit/data/read_credit_repository.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';
import 'package:smarter_jxufe/features/read_credit/domain/read_credit_progress.dart';

/// 阅读学分平台专用 Dio（https，不预设 Cookie —— 会话由仓库显式传入）。
final readCreditDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return Dio(
    BaseOptions(
      baseUrl: ReadCreditAuthRemoteDataSource.origin,
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

/// 会话存储 Box（按账号 key）。
final readCreditBoxProvider = FutureProvider<Box<String>>(
  (ref) => Hive.openBox<String>(ReadCreditAuthLocalDataSource.boxName),
);

final readCreditLocalDataSourceProvider =
    FutureProvider<ReadCreditAuthLocalDataSource>((ref) async {
      final box = await ref.watch(readCreditBoxProvider.future);
      return ReadCreditAuthLocalDataSource(box);
    });

final readCreditAuthRemoteDataSourceProvider =
    Provider<ReadCreditAuthRemoteDataSource>(
      (ref) => ReadCreditAuthRemoteDataSource(ref.watch(readCreditDioProvider)),
    );

/// 会话仓库：依赖统一认证的 [AuthRepository]（keepAlive 单例），
/// TGC 过期时其内部会自动重登。
final readCreditAuthRepositoryProvider =
    FutureProvider<ReadCreditAuthRepository>((ref) async {
      final local = await ref.watch(readCreditLocalDataSourceProvider.future);
      final remote = ref.watch(readCreditAuthRemoteDataSourceProvider);
      final authRepository = await ref.watch(authRepositoryProvider.future);
      return ReadCreditAuthRepository(
        localDataSource: local,
        remoteDataSource: remote,
        authRepository: authRepository,
      );
    });

final readCreditApiDataSourceProvider = Provider<ReadCreditApiRemoteDataSource>(
  (ref) => ReadCreditApiRemoteDataSource(ref.watch(readCreditDioProvider)),
);

/// 业务仓库（带会话自动续期）。
final readCreditRepositoryProvider = FutureProvider<ReadCreditRepository>((
  ref,
) async {
  return ReadCreditRepository(
    auth: await ref.watch(readCreditAuthRepositoryProvider.future),
    api: ref.watch(readCreditApiDataSourceProvider),
  );
});

/// 学分查询（5 项达标 + 学分状态）。
final readCreditScoreProvider = FutureProvider<ReadCreditScore>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw const ReadCreditApiException('请先登录后再查看阅读学分');
  }
  final repo = await ref.watch(readCreditRepositoryProvider.future);
  return repo.fetchScore(account);
});

/// 某一项的明细表。
final readCreditDetailProvider =
    FutureProvider.family<ReadCreditDetail, ReadCreditKind>((ref, kind) async {
      final account = ref.watch(currentAccountProvider);
      if (account.isEmpty) {
        throw const ReadCreditApiException('请先登录后再查看阅读学分');
      }
      final repo = await ref.watch(readCreditRepositoryProvider.future);
      return repo.fetchDetail(account, kind);
    });

/// 四部分进度（实际口径 vs 平台口径，用户 2026-09-11 拍板）。
///
/// 平台汇总页只在 5 月 / 11 月更新，故「实际」优先取 App 侧可实时获取的口径：
/// 入馆教育 = 五章闯关实时状态；普通阅读纸质借阅 = 学生个人数据中心；
/// 其余部分回退平台明细表的实时统计。任一路径失败只降级该项，不整页报错。
final readCreditProgressProvider = FutureProvider<ReadCreditProgressBundle>((
  ref,
) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw const ReadCreditApiException('请先登录后再查看阅读学分');
  }
  final repo = await ref.watch(readCreditRepositoryProvider.future);

  // 平台学分查询（失败不致命：实际口径仍可展示）。
  ReadCreditScore? score;
  try {
    score = await repo.fetchScore(account);
  } catch (_) {
    score = null;
  }

  // 明细逐项容忍失败（明细是实时数据，也是「实际」的主要来源）。
  final details = <ReadCreditKind, ReadCreditDetail>{};
  for (final kind in const [
    ReadCreditKind.classic,
    ReadCreditKind.ordinary,
    ReadCreditKind.libraryEdu,
    ReadCreditKind.infoLiteracy,
  ]) {
    try {
      details[kind] = await repo.fetchDetail(account, kind);
    } catch (_) {
      // 单项明细失败 → 该项不给实际值，其余照常。
    }
  }

  if (score == null && details.isEmpty) {
    throw const ReadCreditApiException('阅读学分数据获取失败，请稍后重试');
  }

  return buildReadCreditProgress(
    score: score,
    details: details,
    libraryEdu: await _eduProgress(ref),
    borrowCounts: await _borrowCounts(ref, account),
    cxstar: await _cxstarProgress(ref),
  );
});

/// 畅想之星平台侧的个人阅读计数（经典阅读的**实际**口径，App 内实时）。
///
/// 只采信**个人**会话：校园网 IP 免密登录得到的是全校公用账号（全校聚合），
/// 拿它当个人进度会严重高估（实测 2160 册 vs 个人 13 册）。
Future<ReadCreditCxstarProgress?> _cxstarProgress(Ref ref) async {
  try {
    final overview = await ref.read(cxstarOverviewProvider.future);
    if (!overview.personal) return null;
    return (
      books: overview.summary.readCount,
      minutes: overview.summary.readMinutes,
    );
  } catch (_) {
    return null;
  }
}

/// 入馆教育五章闯关实时进度（App 直连 tsgxs，不依赖平台汇总）。
///
/// 逐章口径：已通过 → 计入；服务端明确「答题尚未开放」（`blocked` =
/// 前序章节未通过 / 线索未学完）→ 不计入（这是确定的未通过）。但请求
/// 本身失败（会话失效 / 网络抖动）属于**未知**，不能当成未通过 ——
/// 早前按未通过计，任何一次抖动都会让整项掉成 4/5 并显示「未完成」。
/// 出现未知时整体返回 null，卡片回退服务端状态并给出说明。
Future<ReadCreditEduProgress?> _eduProgress(Ref ref) async {
  try {
    final home = await ref.read(tsgxsHomeProvider.future);
    final ids = home.chapterIds;
    if (ids.isEmpty) return null;
    var passed = 0;
    var unknown = false;
    for (final id in ids) {
      try {
        final status = await ref.read(tsgxsExamStatusProvider(id).future);
        if (status.state == TsgxsExamState.passed) passed++;
      } catch (_) {
        // 状态取不到 = 未知（会话 / 网络），不当作未通过。
        unknown = true;
      }
    }
    if (unknown) return null;
    return (passed: passed, total: ids.length);
  } catch (_) {
    return null;
  }
}

/// 学生个人数据中心的图书借阅册数（键 `本周 / 本月 / 本年`）。
Future<Map<String, int>> _borrowCounts(Ref ref, String account) async {
  try {
    final repository = await ref.read(dataCenterRepositoryProvider.future);
    return await repository.fetchBorrowCountsOnly(account) ?? const {};
  } catch (_) {
    return const {};
  }
}
