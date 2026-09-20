import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/dzj_auth_repository.dart';
import 'package:smarter_jxufe/features/data_center/data/models/data_center_models.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_extra.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_my_fields.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_page_body.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_page_tree.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';

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
      throw DzjApiException('个人数据中心数据加载失败，请稍后重试');
    }
    return retry.$1;
  }

  /// 仅拉取指定账户的网费余额（轻量单卡查询，供仪表盘 / 网费页兜底）。
  ///
  /// 会话失效时刷新后重试一次；无数据显示 null（`fetchNetworkBalance`
  /// 内部 _guard 失败返回 null，不抛）。
  Future<double?> fetchNetworkBalanceOnly(String account) async {
    final session = await _authRepository.getSession(account);
    final first = await _remoteDataSource.fetchNetworkBalance(session);
    if (first != null) return first;
    final freshSession = await _authRepository.refreshSession(account);
    return _remoteDataSource.fetchNetworkBalance(freshSession);
  }

  /// 仅拉取指定账户的图书借阅册数（轻量单卡查询，供蛟湖阅读学分进度取实际值）。
  ///
  /// 键为 `本周 / 本月 / 本年`。会话失效时刷新后重试一次；
  /// 无数据显示 null（`fetchBorrowCounts` 内部 _guard 失败返回 null，不抛）。
  Future<Map<String, int>?> fetchBorrowCountsOnly(String account) async {
    final session = await _authRepository.getSession(account);
    final first = await _remoteDataSource.fetchBorrowCounts(session);
    if (first != null && first.isNotEmpty) return first;
    final freshSession = await _authRepository.refreshSession(account);
    return _remoteDataSource.fetchBorrowCounts(freshSession);
  }

  /// 拉取某个维度的校内关系**名单**（轻量单维度查询，供数据中心名单弹层与 AA 导入）。
  ///
  /// 名单**不进首屏概览**（`_collect`）：同年级上千人，五个维度一起取等于给首页
  /// 再挂 5 个请求。会话失效时刷新后重试一次；两次都失败则抛（界面给「重试」）。
  Future<List<DzjPeer>> fetchPeers(
    String account,
    DzjPeerDimension dimension,
  ) async {
    final session = await _authRepository.getSession(account);
    final first = await _remoteDataSource.fetchPeers(session, dimension);
    if (first != null) return first;
    final freshSession = await _authRepository.refreshSession(account);
    final retry = await _remoteDataSource.fetchPeers(freshSession, dimension);
    if (retry == null) {
      throw DzjApiException('「${dimension.label}」名单加载失败，请稍后重试');
    }
    return retry;
  }

  /// 某个维度（可带服务端过滤）的**人数**——只取 `total`，不把行拉回来。
  ///
  /// 用户 2026-09-20 立项：「同年级同学院」的人数 = 同年级行集按本人学院过滤后的
  /// `total`（实测 726）。同年级有 7905 行、`pageSize` 上限 500，自己翻页要 16 个请求，
  /// 而 `total` 本来就是过滤后的总数 → 一次请求即可。
  ///
  /// 返回 null = 取不到（成绩页据此回退固定值）；会话失效同样刷新后重试一次。
  Future<int?> fetchPeerCount(
    String account,
    DzjPeerDimension dimension,
  ) async {
    final session = await _authRepository.getSession(account);
    final first = await _remoteDataSource.fetchPeerCount(session, dimension);
    if (first != null) return first;
    final freshSession = await _authRepository.refreshSession(account);
    return _remoteDataSource.fetchPeerCount(freshSession, dimension);
  }

  /// 拉取「相关人员」（第二个页面）六个维度的**人数**（供数据中心「相关人员」卡）。
  ///
  /// 走 `DzjPeerDimension.relatedDims`（组件 `u:af43933a919c`）；与 [fetchPeers] 同理
  /// 按需拉取、不进首屏。会话失效时刷新后重试一次；两次都失败则抛。
  Future<Map<String, int>> fetchRelatedCounts(String account) async {
    final session = await _authRepository.getSession(account);
    final first = await _remoteDataSource.fetchRelatedCounts(session);
    if (first != null) return first;
    final freshSession = await _authRepository.refreshSession(account);
    final retry = await _remoteDataSource.fetchRelatedCounts(freshSession);
    if (retry == null) {
      throw DzjApiException('相关人员数据加载失败，请稍后重试');
    }
    return retry;
  }

  /// 拉取「补充模块」（本学期课程 / 图书馆座位预约 / 助学金与勤工助学）。
  ///
  /// 三个模块**并发**取，单模块失败只让自己缺席（不发假卡片），全失败才抛 —— 与 [fetchPeers]
  /// 同样按需调用、不进首屏 `_collect`（首屏已有 20 个请求）。
  Future<DzjExtraInfo> fetchExtra(String account) async {
    final session = await _authRepository.getSession(account);
    var first = await _collectExtra(session);
    if (first.isEmpty) {
      // 一块都没拿到 → 大概率会话失效
      final freshSession = await _authRepository.refreshSession(account);
      first = await _collectExtra(freshSession);
      if (first.isEmpty) {
        throw DzjApiException('补充信息加载失败，请稍后重试');
      }
    }
    return first;
  }

  Future<DzjExtraInfo> _collectExtra(DzjSession session) async {
    final api = _remoteDataSource;
    final results = await Future.wait<Object?>([
      api.fetchSemesterCourses(session),
      api.fetchSeatBookings(session),
      api.fetchAidRecords(session),
    ]);

    DzjExtraBlock? block(
      DzjExtraModule module,
      Object? value,
    ) {
      if (value is! ({int total, List<DzjInfoItem> items})) return null;
      return DzjExtraBlock(
        module: module,
        items: value.items,
        total: value.total,
      );
    }

    final blocks = <String, DzjExtraBlock>{};
    for (final (i, module) in DzjExtraModule.values.indexed) {
      final b = block(module, results[i]);
      if (b != null) blocks[module.key] = b;
    }
    return DzjExtraInfo(blocks: blocks);
  }

  /// 拉取**子页面清单**（页面树）。会话失效时刷新后重试一次；两次都失败则抛。
  ///
  /// 清单来自服务端（`manageTreeByVersion`），App 不写死 pageKey —— 学校加页面
  /// App 自动跟着出现。**首页与「基本信息」已在校验里剔除**（见 `DzjPageTree`）。
  Future<DzjPageTree> fetchPageTree(String account) async {
    final session = await _authRepository.getSession(account);
    var tree = DzjPageTree.parse(
      await _remoteDataSource.fetchPageTree(session),
    );
    if (tree.isEmpty) {
      final fresh = await _authRepository.refreshSession(account);
      tree = DzjPageTree.parse(await _remoteDataSource.fetchPageTree(fresh));
      if (tree.isEmpty) {
        throw DzjApiException('个人数据中心子页面清单加载失败，请稍后重试');
      }
    }
    return tree;
  }

  /// 拉取**一个子页面**：页面定义 → 通用解析 → 逐块并发取数。
  ///
  /// 单块失败只让自己变成空块（界面画「暂无数据」），整页一块都没拿到才算失败
  /// （大概率会话失效 → 刷新会话后整页重来一次）。
  Future<DzjSubPageData> fetchSubPage(
    String account,
    DzjPageNode node,
  ) async {
    final session = await _authRepository.getSession(account);
    var data = await _collectSubPage(session, node);
    if (data.blocks.every((b) => b.isEmpty)) {
      final fresh = await _authRepository.refreshSession(account);
      data = await _collectSubPage(fresh, node);
      if (data.blocks.every((b) => b.isEmpty)) {
        throw DzjApiException('「${node.title}」数据加载失败，请稍后重试');
      }
    }
    return data;
  }

  /// **「基本信息」表单的 39 项字段值**（学工系统登记口径）—— 「我的」页的字段源之一。
  ///
  /// 用户 2026-09-20 八轮：「基本信息页有大量的信息没有并入「我的」页」。这一份比
  /// 学籍缓存多出家庭住址 / 证件类型 / 证件号码 / 所属校区 / 学生身份 / 学生类型 /
  /// 通知书号 / 录取五项 / 预计毕业日期 / 毕业中学 / 当前状态 / 学籍状态 / 宿舍地址等。
  /// 端点独此一家（`tsa/getFormData`，见 [DzjBasicField]）：表单组件的 `data/search`
  /// 是占位符 SQL，恒 0 行。
  ///
  /// 失败一律回空表：这只是「我的」页的补充色块，取不到就退回学籍缓存。
  Future<Map<String, String>> fetchBasicInfo(String account) async {
    final session = await _authRepository.getSession(account);
    final out = await _collectBasicInfo(session, account);
    if (out.isNotEmpty) return out;
    final fresh = await _authRepository.refreshSession(account);
    return _collectBasicInfo(fresh, account);
  }

  Future<Map<String, String>> _collectBasicInfo(
    DzjSession session,
    String account,
  ) async {
    try {
      return await _remoteDataSource.fetchBasicInfo(session, account: account) ??
          const <String, String>{};
    } catch (_) {
      return const <String, String>{};
    }
  }

  /// 拉取**「我的」页要用的那一小撮数据中心字段**（姓名 / 一卡通号 / 院系 / 班主任 /
  /// 班主任电话 / 宿舍评分 —— 见 `DzjMyField`）。
  ///
  /// 用户 2026-09-20 七轮：「我的页不显示从数据中心添加的信息……」。这些值分别来自个人
  /// 首页与「住宿信息」子页上的**动态文本 / 指标组件**，一块一个请求、并发取；
  /// **单块失败只让它缺席**（该行回落到学籍缓存，或者干脆不显示），绝不因为一个组件挂了
  /// 就把整页拖成错误页。全部失败 → 回空表（「我的」页照常见人）。
  Future<Map<String, String>> fetchMyFields(String account) async {
    final session = await _authRepository.getSession(account);
    final out = await _collectMyFields(session);
    if (out.isNotEmpty) return out;
    // 一块都没取到，多半是会话刚失效 → 刷新后重试一次。
    final fresh = await _authRepository.refreshSession(account);
    return _collectMyFields(fresh);
  }

  Future<Map<String, String>> _collectMyFields(DzjSession session) async {
    final results = await Future.wait<Object?>([
      for (final f in DzjMyField.values)
        () async {
          try {
            final v = await _remoteDataSource.fetchBlockValue(
              session,
              f.componentId,
            );
            final raw = v?[f.valueKey];
            return raw == null ? null : dzjValueText(raw);
          } catch (_) {
            return null;
          }
        }(),
    ]);
    final out = <String, String>{};
    for (final (i, f) in DzjMyField.values.indexed) {
      final v = results[i];
      if (v is String && v.isNotEmpty) out[f.label] = v;
    }
    return out;
  }

  Future<DzjSubPageData> _collectSubPage(
    DzjSession session,
    DzjPageNode node,
  ) async {
    final body = DzjPageBody.parse(
      node.pageKey,
      await _remoteDataSource.fetchPageBody(session, node.pageKey),
    );
    if (body.blocks.isEmpty) {
      return DzjSubPageData(
        pageKey: node.pageKey,
        title: node.title,
        blocks: const <DzjBlockData>[],
        skipped: body.skipped,
        truncated: body.truncated,
      );
    }
    // 并发取数：每块最多 2 个请求（先按 kind 试，空了换另一个端点），
    // 分批 8 路。⚠ 上限从 24 提到 60、识别面也放宽之后，块数翻了两三倍（校内活动 54 个
    // 候选、学业信息 49 个），批次相应从 4 提到 8，否则一页要串行十几轮才出数。
    const batchSize = 8;
    final out = <DzjBlockData>[];
    for (var i = 0; i < body.blocks.length; i += batchSize) {
      final batch = body.blocks.skip(i).take(batchSize);
      final got = await Future.wait(batch.map((b) => _fetchBlock(session, b)));
      out.addAll(got);
    }
    return DzjSubPageData(
      pageKey: node.pageKey,
      title: node.title,
      blocks: out,
      skipped: body.skipped,
      truncated: body.truncated,
    );
  }

  /// 取一个块的数据：先按解析出的倾向试，空了换另一个端点；都空 → 空块。
  ///
  /// **带 `slot` 的块**（名单类组件的第几路）走 `data/search` + `index`：
  /// 先要行集，空了再要计数（`data/get` + 同 `index`）。
  Future<DzjBlockData> _fetchBlock(DzjSession session, DzjBlock block) async {
    Future<DzjBlockData?> asValue({int index = 0}) async {
      try {
        final v = await _remoteDataSource.fetchBlockValue(
          session,
          block.id,
          index: index,
        );
        if (v == null) return null;
        final fields = dzjFieldsOf(v, title: block.title);
        if (fields.isEmpty) return null;
        return DzjBlockData(block: block, fields: fields);
      } catch (_) {
        return null;
      }
    }

    Future<DzjBlockData?> asRows({int? slot}) async {
      try {
        final v = await _remoteDataSource.fetchBlockRows(
          session,
          block.id,
          slot: slot,
        );
        if (v == null) return null;
        final rows = dzjRowsOf(v, block);
        if (rows.isEmpty) return null;
        return DzjBlockData(block: block, rows: rows);
      } catch (_) {
        return null;
      }
    }

    Future<DzjBlockData?> asObjectRows() async {
      if (!block.hasDataObject) return null;
      try {
        final v = await _remoteDataSource.fetchDataObjectRows(
          session,
          componentId: block.id,
          dataObjectId: block.dataObjectId,
          filterSql: block.filterSql,
          fieldList: block.fieldList,
        );
        if (v == null) return null;
        final rows = dzjRowsOf(v, block);
        if (rows.isEmpty) return null;
        return DzjBlockData(block: block, rows: rows);
      } catch (_) {
        return null;
      }
    }

    if (block.slot >= 0) {
      for (final attempt in <Future<DzjBlockData?> Function()>[
        () => asRows(slot: block.slot),
        () => asValue(index: block.slot),
        () => asRows(),
      ]) {
        final r = await attempt();
        if (r != null && !r.isEmpty) return r;
      }
      return DzjBlockData(block: block, failed: true);
    }

    // 表格 / 图表的**明细行**优先走数据对象端点（唯一能出内容的通道，见
    // `dzjDataObjectOf` 的说明）；它没配数据对象时再按老顺序试。
    final order = block.kind == DzjBlockKind.list
        ? <Future<DzjBlockData?> Function()>[asObjectRows, asRows, asValue]
        : <Future<DzjBlockData?> Function()>[asObjectRows, asValue, asRows];
    for (final attempt in order) {
      final r = await attempt();
      if (r != null && !r.isEmpty) return r;
    }
    return DzjBlockData(block: block, failed: true);
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
