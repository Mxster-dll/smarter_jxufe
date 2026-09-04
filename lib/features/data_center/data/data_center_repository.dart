import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/dzj_auth_repository.dart';
import 'package:smarter_jxufe/features/data_center/data/models/data_center_models.dart';

/// 学生个人数据中心业务仓库。
///
/// 职责：
/// 1. 经 [DzjAuthRepository] 获取当前账户会话（自动换取 / 缓存）；
/// 2. 并行拉取个人首页全部卡片数据组装 [DataCenterOverview]；
/// 3. 若整批失败（会话失效信号）则刷新会话后重试一次。
class DataCenterRepository {
  final DzjAuthRepository _authRepository;
  final DzjApiRemoteDataSource _remoteDataSource;

  DataCenterRepository({
    required DzjAuthRepository authRepository,
    required DzjApiRemoteDataSource remoteDataSource,
  }) : _authRepository = authRepository,
       _remoteDataSource = remoteDataSource;

  /// 拉取指定账户的全量概览。
  Future<DataCenterOverview> fetchOverview(String account) async {
    final session = await _authRepository.getSession(account);
    final first = await _collect(session);
    if (!first.$2) return first.$1;

    // 全部卡片均失败 → 大概率会话失效，刷新会话后重试一次
    final freshSession = await _authRepository.refreshSession(account);
    final retry = await _collect(freshSession);
    if (retry.$2) {
      throw Exception('个人数据中心数据加载失败，请稍后重试');
    }
    return retry.$1;
  }

  /// 并行收集所有卡片；返回 (概览, 是否全部失败)。
  Future<(DataCenterOverview, bool)> _collect(DzjSession session) async {
    final api = _remoteDataSource;

    final results = await Future.wait<Object?>([
      api.fetchWeightedScore(session),
      api.fetchGpa(session),
      api.fetchSemesterCredit(session),
      api.fetchEarnedCredit(session),
      api.fetchSpendYear(session),
      api.fetchSpendMonth(session),
      api.fetchSpendWeek(session),
      api.fetchGateToday(session),
      api.fetchCardBalance(session),
      api.fetchTodayLogin(session),
      api.fetchNetworkBalance(session),
      api.fetchTextbookFee(session),
      api.fetchTextbookCount(session),
      api.fetchBorrowCounts(session),
      api.fetchLoginTrendRows(session),
      api.fetchConsumeRecords(session),
      api.fetchAwards(session),
      api.fetchWeekDays(session),
      api.fetchTodayClassCount(session),
      api.fetchPeerCounts(session),
    ]);

    double asDouble(Object? v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }

    final weekDays = (results[17] as List<Map<String, dynamic>>?) ?? const [];
    String weekTitle = '';
    if (weekDays.isNotEmpty) {
      weekTitle = weekDays.first['title']?.toString() ?? '';
    }

    final trendRows = (results[14] as List<List<dynamic>>?) ?? const [];
    final loginDays = <DzjLoginDay>[];
    for (final row in trendRows) {
      if (row.length < 2) continue;
      final label = row[0].toString();
      if (label == 'product') continue;
      loginDays.add(
        DzjLoginDay(
          weekday: label,
          count: row[1] is num ? (row[1] as num).toInt() : 0,
        ),
      );
    }

    final records = (results[15] as List<Map<String, dynamic>>?) ?? const [];
    final consumeRecords = records
        .map(
          (r) => DzjConsumeRecord(
            shopName: r['shmc']?.toString() ?? '',
            time: r['jysj']?.toString() ?? '',
            amount: (r['jyje'] is num
                ? (r['jyje'] as num).toDouble()
                : double.tryParse(r['jyje']?.toString() ?? '') ?? 0),
          ),
        )
        .toList();

    final identity = await api.fetchIdentityTexts(session);

    final failedCount =
        results.where((r) => r == null).length + (identity.isEmpty ? 1 : 0);
    final allFailed =
        failedCount == results.length + (identity.isEmpty ? 1 : 0) &&
        results.isNotEmpty;

    final overview = DataCenterOverview(
      username: identity['username'] ?? '',
      userid: identity['userid'] ?? '',
      college: identity['ssdw'] ?? '',
      advisorName: identity['bzrxm'] ?? '',
      advisorPhone: identity['bzrsjh'] ?? '',
      weightedScore: asDouble(results[0]),
      gpa: asDouble(results[1]),
      semesterCredit: asDouble(results[2]),
      earnedCredit: asDouble(results[3]),
      spendYear: asDouble(results[4]),
      spendMonth: asDouble(results[5]),
      spendWeek: asDouble(results[6]),
      gateToday: asDouble(results[7]),
      cardBalance: asDouble(results[8]),
      todayLoginCount: asDouble(results[9]),
      networkBalance: asDouble(results[10]),
      textbookFee: asDouble(results[11]),
      textbookCount: asDouble(results[12]),
      borrowCounts: (results[13] as Map<String, int>?) ?? const {},
      consumeRecords: consumeRecords,
      awards: (results[16] as List<String>?) ?? const [],
      weekTitle: weekTitle,
      weekDays: weekDays
          .map(
            (w) => DzjWeekDay(
              date: w['rq']?.toString() ?? '',
              weekday: w['xqmc']?.toString() ?? '',
              title: w['title']?.toString() ?? '',
            ),
          )
          .toList(),
      todayClassCount: (results[18] as int?) ?? 0,
      loginTrend: loginDays,
      peerCounts: (results[19] as Map<String, int>?) ?? const {},
    );

    return (overview, allFailed);
  }
}
