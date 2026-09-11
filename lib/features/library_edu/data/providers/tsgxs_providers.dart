import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/network/device_profile_repository_provider.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_answer_bank.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_auth_local_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_auth_repository.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_progress_store.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_repository.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_models.dart';

/// 入馆教育(tsgxs.jxufe.cn)专用 Dio。
///
/// 平台为 http(80)，不预设 Cookie 默认头——每个请求的会话 Cookie
/// 由会话仓库显式传入(与 SSP 相同的约定)。
final tsgxsDioProvider = Provider<Dio>((ref) {
  final deviceProfileRepo = ref.watch(deviceProfileRepositoryProvider);
  return Dio(
    BaseOptions(
      baseUrl: 'http://tsgxs.jxufe.cn',
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

/// 入馆教育会话存储 Box(按账户 key)。
final tsgxsAuthBoxProvider = FutureProvider<Box<String>>(
  (ref) => Hive.openBox<String>('tsgxs'),
);

final tsgxsAuthLocalDataSourceProvider =
    FutureProvider<TsgxsAuthLocalDataSource>((ref) async {
      final box = await ref.watch(tsgxsAuthBoxProvider.future);
      return TsgxsAuthLocalDataSource(box);
    });

final tsgxsAuthRemoteDataSourceProvider = Provider<TsgxsAuthRemoteDataSource>(
  (ref) => TsgxsAuthRemoteDataSource(ref.watch(tsgxsDioProvider)),
);

/// 会话仓库：依赖统一认证的 [AuthRepository](keepAlive 单例)，
/// TGC 过期时其内部会自动走重登(含 MFA 弹窗)。
final tsgxsAuthRepositoryProvider = FutureProvider<TsgxsAuthRepository>((
  ref,
) async {
  final localDataSource = await ref.watch(
    tsgxsAuthLocalDataSourceProvider.future,
  );
  final remoteDataSource = ref.watch(tsgxsAuthRemoteDataSourceProvider);
  final authRepository = await ref.watch(authRepositoryProvider.future);
  return TsgxsAuthRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    authRepository: authRepository,
  );
});

// ---------------- 业务层 ----------------

/// 业务数据源(HTML 解析)。
final tsgxsApiDataSourceProvider = Provider<TsgxsApiRemoteDataSource>(
  (ref) => TsgxsApiRemoteDataSource(ref.watch(tsgxsDioProvider)),
);

/// 业务仓库(带会话自动续期)。
final tsgxsRepositoryProvider = FutureProvider<TsgxsRepository>((ref) async {
  return TsgxsRepository(
    auth: await ref.watch(tsgxsAuthRepositoryProvider.future),
    api: ref.watch(tsgxsApiDataSourceProvider),
  );
});

/// 首页(章节 id 列表 + 皮肤 id)。
final tsgxsHomeProvider =
    FutureProvider<({List<String> chapterIds, String? themeId})>((ref) async {
      final account = ref.watch(currentAccountProvider);
      if (account.isEmpty) {
        throw const TsgxsApiException('请先登录后再查看入馆教育');
      }
      final repo = await ref.watch(tsgxsRepositoryProvider.future);
      return repo.fetchHome(account);
    });

/// 当前皮肤 id(首页未取到则回退书生版)。
final tsgxsThemeIdProvider = FutureProvider<String>((ref) async {
  final home = await ref.watch(tsgxsHomeProvider.future);
  return home.themeId ?? tsgxsDefaultThemeId;
});

/// 全部章节地图(首页 → 逐章拉取)。
///
/// **顺序解锁容错**:上一章未通过时,后续章节地图会 302 到 `/html/401.html`
/// (实测 2026-09-11),若直接抛异常会让整个列表失败 → 首页章节区只剩一张
/// 错误卡(用户曾因此认为「一章都没有」)。这里把未解锁章降级为占位章
/// ([TsgxsChapter.locked]),保证 5 张章节卡始终可渲染。
final tsgxsChaptersProvider = FutureProvider<List<TsgxsChapter>>((ref) async {
  final account = ref.watch(currentAccountProvider);
  final repo = await ref.watch(tsgxsRepositoryProvider.future);
  final home = await ref.watch(tsgxsHomeProvider.future);
  final themeId = home.themeId ?? tsgxsDefaultThemeId;
  final out = <TsgxsChapter>[];
  for (final id in home.chapterIds) {
    try {
      out.add(
        await repo.fetchChapter(account, chapterId: id, themeId: themeId),
      );
    } on TsgxsAccessDeniedException {
      out.add(TsgxsChapter.locked(id));
    }
  }
  return out;
});

/// 单章地图。
final tsgxsChapterProvider = FutureProvider.family<TsgxsChapter, String>((
  ref,
  chapterId,
) async {
  final account = ref.watch(currentAccountProvider);
  final repo = await ref.watch(tsgxsRepositoryProvider.future);
  final themeId = await ref.watch(tsgxsThemeIdProvider.future);
  return repo.fetchChapter(account, chapterId: chapterId, themeId: themeId);
});

/// 学习内容页。
final tsgxsContentProvider = FutureProvider.family<TsgxsContent, String>((
  ref,
  nodeId,
) async {
  final account = ref.watch(currentAccountProvider);
  final repo = await ref.watch(tsgxsRepositoryProvider.future);
  final themeId = await ref.watch(tsgxsThemeIdProvider.future);
  return repo.fetchContent(account, nodeId: nodeId, themeId: themeId);
});

/// 我的成绩。
final tsgxsGradesProvider = FutureProvider<List<TsgxsGrade>>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw const TsgxsApiException('请先登录后再查看入馆教育');
  }
  final repo = await ref.watch(tsgxsRepositoryProvider.future);
  return repo.fetchGrades(account);
});

/// 排行榜。
final tsgxsRankingProvider = FutureProvider<TsgxsRanking>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw const TsgxsApiException('请先登录后再查看入馆教育');
  }
  final repo = await ref.watch(tsgxsRepositoryProvider.future);
  return repo.fetchRanking(account);
});

/// 个人资料。
final tsgxsProfileProvider = FutureProvider<TsgxsProfile>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw const TsgxsApiException('请先登录后再查看入馆教育');
  }
  final repo = await ref.watch(tsgxsRepositoryProvider.future);
  return repo.fetchProfile(account);
});

/// 章节考试状态。
final tsgxsExamStatusProvider = FutureProvider.family<TsgxsExamStatus, String>((
  ref,
  chapterId,
) async {
  final account = ref.watch(currentAccountProvider);
  final repo = await ref.watch(tsgxsRepositoryProvider.future);
  return repo.fetchExamStatus(account, chapterId: chapterId);
});

/// 本地已浏览节点(仅 UI 展示用;服务端另有自己的学习记录)。
final tsgxsVisitedStoreProvider = FutureProvider<TsgxsVisitedStore>((
  ref,
) async {
  final box = await ref.watch(tsgxsAuthBoxProvider.future);
  return TsgxsVisitedStore(box, ref.watch(currentAccountProvider));
});

/// 本地题库(题目 id → 正确答案,跨账号共享)。
final tsgxsAnswerBankProvider = FutureProvider<TsgxsAnswerBank>((ref) async {
  final box = await ref.watch(tsgxsAuthBoxProvider.future);
  return TsgxsAnswerBank(box);
});
