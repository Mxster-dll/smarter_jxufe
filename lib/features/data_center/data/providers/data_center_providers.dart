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
import 'package:smarter_jxufe/features/data_center/domain/dzj_extra.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_my_fields.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_page_body.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_page_tree.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';

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
    throw DzjApiException('请先登录后再查看个人数据中心');
  }
  final repository = await ref.watch(dataCenterRepositoryProvider.future);
  return repository.fetchOverview(account);
});

/// 某个维度的校内关系**名单**（按需拉取，family 参数 = 维度）。
///
/// 刻意不并进 [dataCenterOverviewProvider]：同年级上千人，把五个维度都塞进首屏
/// 等于每次进页面多打 5 个请求。名单只在「点人数看名单」与「AA 从数据中心导入」
/// 时取；刷新用 `ref.invalidate(dzjPeersProvider(维度))`。账号切换经
/// [currentAccountProvider] 自动重取。
final dzjPeersProvider =
    FutureProvider.family<List<DzjPeer>, DzjPeerDimension>((
      ref,
      dimension,
    ) async {
      final account = ref.watch(currentAccountProvider);
      if (account.isEmpty) {
        throw DzjApiException('请先登录后再查看个人数据中心');
      }
      final repository = await ref.watch(dataCenterRepositoryProvider.future);
      return repository.fetchPeers(account, dimension);
    });

/// 「相关人员」（学校第二个页面）**六个维度的人数**（按需拉取）。
///
/// 与 [dzjPeersProvider] 同理不进首屏：首屏 `_collect` 已有 20 个并发请求，再加 6 个
/// 只会让「数据一览」更慢，而这张卡是次级信息 —— 卡片先画「…」，值到了再填。
/// 键 = `DzjPeerDimension.key`（`relatedDorm` / `relatedCollege` / …）；
/// 单个维度失败时该键为 `-1`（界面当「没有数据」不画那一格）。
/// 刷新用 `ref.invalidate(dzjRelatedCountsProvider)`。
final dzjRelatedCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw DzjApiException('请先登录后再查看个人数据中心');
  }
  final repository = await ref.watch(dataCenterRepositoryProvider.future);
  return repository.fetchRelatedCounts(account);
});

/// 补充模块（本学期课程 / 图书馆座位预约 / 助学金与勤工助学）。
///
/// 同样按需拉取（3 个请求），不进首屏；单模块失败只让自己缺席
/// （`DzjExtraInfo.block(module)` 返回 null → 界面给空态而不是假数据）。
/// 刷新用 `ref.invalidate(dzjExtraProvider)`。
final dzjExtraProvider = FutureProvider<DzjExtraInfo>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw DzjApiException('请先登录后再查看个人数据中心');
  }
  final repository = await ref.watch(dataCenterRepositoryProvider.future);
  return repository.fetchExtra(account);
});

/// 个人数据中心的**子页面清单**（服务端页面树，App 不写死 pageKey）。
///
/// 一个请求，很轻 —— 数据中心的入口卡直接 watch 它。**「基本信息」已被
/// `dzjSubPagesOf` 剔除**（并入「我的」页，见 [dzjBasicInfoPageKey]）；
/// 刷新用 `ref.invalidate(dzjPageTreeProvider)`。
final dzjPageTreeProvider = FutureProvider<DzjPageTree>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) {
    throw DzjApiException('请先登录后再查看个人数据中心');
  }
  final repository = await ref.watch(dataCenterRepositoryProvider.future);
  return repository.fetchPageTree(account);
});

/// 某个子页面的**渲染数据**（family 参数 = pageKey）。
///
/// 每页若干块：kpi 走 `data/get`、明细走 `data/list`。**按需拉取**
/// （一页最多 24 块 × 2 次尝试），只在真正点进那个子页面时才取；刷新用
/// `ref.invalidate(dzjSubPageProvider(pageKey))`。
final dzjSubPageProvider =
    FutureProvider.family<DzjSubPageData, String>((ref, pageKey) async {
      final account = ref.watch(currentAccountProvider);
      if (account.isEmpty) {
        throw DzjApiException('请先登录后再查看个人数据中心');
      }
      final tree = await ref.watch(dzjPageTreeProvider.future);
      final node = tree.subPages.firstWhere(
        (n) => n.pageKey == pageKey,
        orElse: () => DzjPageNode(pageKey: pageKey, title: pageKey),
      );
      final repository = await ref.watch(dataCenterRepositoryProvider.future);
      return repository.fetchSubPage(account, node);
    });

/// 「我的」页要用的数据中心字段（姓名 / 一卡通号 / 院系 / 班主任 / 班主任电话 /
/// 宿舍评分）。
///
/// 键 = [DzjMyField.label]（也就是「我的」页那一行的标签），值 = 数据中心那一份。
/// **非 autoDispose**：值很稳定（姓名、班主任一学期不变），「我的」页反复进出
/// 不必重取；拿不到就回空表（页面照常显示学籍缓存），**不抛异常、不打扰用户**
/// —— 用户 2026-09-20 七轮要的是「多一份带颜色的来源」，不是又一个错误卡。
final dzjMyFieldsProvider = FutureProvider<Map<String, String>>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) return const <String, String>{};
  try {
    final repository = await ref.watch(dataCenterRepositoryProvider.future);
    return await repository.fetchMyFields(account);
  } catch (_) {
    return const <String, String>{};
  }
});

/// 「同年级同学院」人数 —— 数据中心那一枚胶囊 + 成绩页「年级」排名的分母。
///
/// 用户 2026-09-20 立项原话：「根据数据中心中同年级的学生列表，筛出计算机学院的同学，
/// 得到一个『同年级同学院』的项，并把此项的人数，用作成绩页里，第三项排名的基数
/// 取代掉硬编码的 7900」。服务端不需要新组件：`filterConfig` 认 SQL 谓词
/// （见 [dzjCollegeFilterSql]），一次请求 `data/search` 的 `total` 就是人数（实测 726）。
///
/// **非 autoDispose + 取不到回 null**：它是排名的分母，取不到时成绩页回退固定值、
/// 数据中心的胶囊不画 —— 但绝不该因此给用户弹一个错误卡。
final dzjGradeCollegeCountProvider = FutureProvider<int?>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) return null;
  try {
    final repository = await ref.watch(dataCenterRepositoryProvider.future);
    return await repository.fetchPeerCount(
      account,
      DzjPeerDimension.gradeCollege,
    );
  } catch (_) {
    return null;
  }
});

/// 「基本信息」页那 39 项字段（学工系统口径）——「我的」页的第二个数据中心字段源。
///
/// 与 [dzjMyFieldsProvider] 分开是因为**取数端点完全不同**（表单走 `tsa/getFormData`，
/// 那一小撮走 `data/get`），合在一个 provider 里会让任一端点失败拖垮另一份。页面侧
/// 把两份**合并**后交给 `dzjMergeFields`（后者按行标签对位，数据中心有值就上色）。
///
/// 同样**非 autoDispose + 失败回空表**：它是补充来源，取不到就只显示学籍缓存。
final dzjBasicInfoProvider = FutureProvider<Map<String, String>>((ref) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) return const <String, String>{};
  try {
    final repository = await ref.watch(dataCenterRepositoryProvider.future);
    return await repository.fetchBasicInfo(account);
  } catch (_) {
    return const <String, String>{};
  }
});
