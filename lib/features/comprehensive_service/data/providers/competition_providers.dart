import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/anti_corruption/competition_parser.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/competition_repository.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/datasource/competition_remote_datasource.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/ssp_auth_providers.dart';

/// 学科竞赛数据源（复用综合管理平台的 Dio）。
final competitionDataSourceProvider = Provider<CompetitionRemoteDataSource>((
  ref,
) {
  return CompetitionRemoteDataSource(ref.watch(sspDioProvider));
});

/// 学科竞赛业务仓库（内含会话缓存 / 刷新逻辑）。
final competitionRepositoryProvider = FutureProvider<CompetitionRepository>((
  ref,
) async {
  final sspAuthRepository = await ref.watch(sspAuthRepositoryProvider.future);
  return CompetitionRepository(
    sspAuthRepository: sspAuthRepository,
    remoteDataSource: ref.watch(competitionDataSourceProvider),
  );
});

/// 未登录时统一抛这个错误（页面显示「请先登录」）。
Exception _notLoggedIn() => Exception('请先登录后再使用学科竞赛功能');

/// 我的申请列表的查询条件（页码 + 筛选）。
class CompetitionApplyQuery {
  final int page;

  /// 比赛年份（官网 `search_eq_parent.year`）。
  final String year;

  /// 比赛名称（官网 `search_like_parent.gameName`）。
  final String gameName;

  const CompetitionApplyQuery({
    this.page = 1,
    this.year = '',
    this.gameName = '',
  });

  CompetitionApplyQuery copyWith({int? page, String? year, String? gameName}) =>
      CompetitionApplyQuery(
        page: page ?? this.page,
        year: year ?? this.year,
        gameName: gameName ?? this.gameName,
      );

  @override
  bool operator ==(Object other) =>
      other is CompetitionApplyQuery &&
      other.page == page &&
      other.year == year &&
      other.gameName == gameName;

  @override
  int get hashCode => Object.hash(page, year, gameName);
}

/// 竞赛公示列表的查询条件（页码 + 搜索）。
class CompetitionPublicityQuery {
  final int page;
  final String studentId;
  final String name;
  final String className;

  const CompetitionPublicityQuery({
    this.page = 1,
    this.studentId = '',
    this.name = '',
    this.className = '',
  });

  CompetitionPublicityQuery copyWith({
    int? page,
    String? studentId,
    String? name,
    String? className,
  }) => CompetitionPublicityQuery(
    page: page ?? this.page,
    studentId: studentId ?? this.studentId,
    name: name ?? this.name,
    className: className ?? this.className,
  );

  @override
  bool operator ==(Object other) =>
      other is CompetitionPublicityQuery &&
      other.page == page &&
      other.studentId == studentId &&
      other.name == name &&
      other.className == className;

  @override
  int get hashCode => Object.hash(page, studentId, name, className);
}

/// 比赛目录的查询条件。
class CompetitionGameQuery {
  final int page;
  final String year;
  final String name;

  const CompetitionGameQuery({this.page = 1, this.year = '', this.name = ''});

  CompetitionGameQuery copyWith({int? page, String? year, String? name}) =>
      CompetitionGameQuery(
        page: page ?? this.page,
        year: year ?? this.year,
        name: name ?? this.name,
      );

  @override
  bool operator ==(Object other) =>
      other is CompetitionGameQuery &&
      other.page == page &&
      other.year == year &&
      other.name == name;

  @override
  int get hashCode => Object.hash(page, year, name);
}

/// 学生检索的查询条件。
class CompetitionStudentQuery {
  final int page;
  final String name;
  final String studentId;

  const CompetitionStudentQuery({
    this.page = 1,
    this.name = '',
    this.studentId = '',
  });

  CompetitionStudentQuery copyWith({
    int? page,
    String? name,
    String? studentId,
  }) => CompetitionStudentQuery(
    page: page ?? this.page,
    name: name ?? this.name,
    studentId: studentId ?? this.studentId,
  );

  @override
  bool operator ==(Object other) =>
      other is CompetitionStudentQuery &&
      other.page == page &&
      other.name == name &&
      other.studentId == studentId;

  @override
  int get hashCode => Object.hash(page, name, studentId);
}

/// 我的申请列表。
final competitionApplyListProvider = FutureProvider.autoDispose
    .family<CompetitionPage<CompetitionApply>, CompetitionApplyQuery>((
      ref,
      query,
    ) async {
      final account = ref.watch(currentAccountProvider);
      if (account.isEmpty) throw _notLoggedIn();
      final repository = await ref.watch(competitionRepositoryProvider.future);
      return repository.fetchApplyList(
        account,
        page: query.page,
        year: query.year,
        gameName: query.gameName,
      );
    });

/// 竞赛公示列表（全校）。
final competitionPublicityListProvider = FutureProvider.autoDispose
    .family<CompetitionPage<CompetitionPublicity>, CompetitionPublicityQuery>((
      ref,
      query,
    ) async {
      final account = ref.watch(currentAccountProvider);
      if (account.isEmpty) throw _notLoggedIn();
      final repository = await ref.watch(competitionRepositoryProvider.future);
      return repository.fetchPublicityList(
        account,
        page: query.page,
        studentId: query.studentId,
        name: query.name,
        className: query.className,
      );
    });

/// 比赛目录（选择比赛用）。
final competitionGameListProvider = FutureProvider.autoDispose
    .family<CompetitionPage<CompetitionGame>, CompetitionGameQuery>((
      ref,
      query,
    ) async {
      final account = ref.watch(currentAccountProvider);
      if (account.isEmpty) throw _notLoggedIn();
      final repository = await ref.watch(competitionRepositoryProvider.future);
      return repository.fetchGames(
        account,
        page: query.page,
        year: query.year,
        gameName: query.name,
      );
    });

/// 学生检索（团队申请加成员用）。
final competitionStudentListProvider = FutureProvider.autoDispose
    .family<CompetitionPage<CompetitionStudent>, CompetitionStudentQuery>((
      ref,
      query,
    ) async {
      final account = ref.watch(currentAccountProvider);
      if (account.isEmpty) throw _notLoggedIn();
      final repository = await ref.watch(competitionRepositoryProvider.future);
      return repository.fetchStudents(
        account,
        page: query.page,
        name: query.name,
        studentId: query.studentId,
      );
    });

/// 公示记录的获奖等级。
///
/// 公示列表（`gs_list.html`）**没有等级列** → 等级只能逐行拉详情取（
/// `competitionAwardLevelOf`）。做成 `autoDispose.family` 是刻意的：
/// 卡片是 `ListView.builder` 懒构建的，只有真正进入视口的行才会发起请求
/// （一屏约 8 行），滚走的行随 autoDispose 释放，不必为一个列表页灌 20 个请求。
final competitionPublicityAwardProvider = FutureProvider.autoDispose
    .family<CompetitionAwardLevel, ({int id, CompetitionType type})>((
      ref,
      key,
    ) async {
      final account = ref.watch(currentAccountProvider);
      if (account.isEmpty) throw _notLoggedIn();
      final repository = await ref.watch(competitionRepositoryProvider.future);
      final detail = await repository.fetchPublicityDetail(
        account,
        id: key.id,
        type: key.type,
      );
      return competitionAwardLevelOf(detail);
    });

/// 一条申请记录的**加分**（申报奖项 / 最终奖项 / 个人得分 / 该赛别分值表）。
///
/// 用户 2026-09-18 原话：「我希望学科竞赛申请页面，要在每个申请条目右侧显示此项加分」。
/// 申请列表本身没有奖项与分值列，加分只能按行拉详情（`xd_detail.html`）→ 做成
/// `autoDispose.family`：卡片进视口才请求，滚走即释放（与公示的等级 provider 同一套路）。
final competitionApplyAwardProvider = FutureProvider.autoDispose
    .family<CompetitionApplyAward, ({int id, CompetitionType type})>((
      ref,
      key,
    ) async {
      final account = ref.watch(currentAccountProvider);
      if (account.isEmpty) throw _notLoggedIn();
      final repository = await ref.watch(competitionRepositoryProvider.future);
      return repository.fetchApplyAward(
        account,
        id: key.id,
        type: key.type,
      );
    });

/// 某比赛的可选奖项（按比赛 id 缓存）。
final competitionAwardsProvider = FutureProvider.autoDispose
    .family<List<CompetitionAward>, int>((ref, gameId) async {
      final account = ref.watch(currentAccountProvider);
      if (account.isEmpty) throw _notLoggedIn();
      final repository = await ref.watch(competitionRepositoryProvider.future);
      return repository.fetchAwards(account, gameId: gameId);
    });
