/// 竹简数据中台 · 同班 / 相关维度取数（extension）
///
/// 同班同学与「相关维度」两个维度的计数与名单（6 个方法）。`peerFilterOf` 是**公开 static、被 test/dzj_peer_test.dart 钉着**，故留在类上，这里用 `DzjApiRemoteDataSource.peerFilterOf(…)` 引。
///
/// 拆分自 `dzj_api_remote_datasource.dart`（2026-10-08 架构审计第三轮 · 第二阶段）：
/// 这类只有 `dio` 一个字段，所以整组方法**用 extension 搬走** —— 方法名一字不改、
/// 零 wrapper、调用点连 import 都不用动（本文件被 `dzj_api_remote_datasource.dart`
/// `export`，import 它就等于 import 这里）。口径见 AGENTS.md §33.4.4。
library;

import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_support.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_remote_datasource.dart';

extension DzjApiPeers on DzjApiRemoteDataSource {

  /// 同侪对比：同年级 / 同班级 / 同专业 / 同宿舍 / 同学院同生日人数
  /// （组件 u:fcd2d17a9131，同一 componentId 用 index 区分维度。
  /// 注意：该组件按 index 执行服务端内置 SQL，**忽略请求体内的 sql 字段**，
  /// 故只能取内置 5 维；自定义口径（如「同年级同学院」）走
  /// [DzjPeerDimension.filterSql] 的 `filterConfig` 谓词，不是在这里加 SQL。
  ///
  /// 返回 [DzjPeerCounts]；任一维度失败则该维度为 -1（不展示）。
  Future<Map<String, int>?> fetchPeerCounts(DzjSession s) async {
    const sqls = <String, String>{
      // index 0: 同年级
      'grade': '''
select count(distinct userid) sj from t_xssj_bzks
where dke_op_type<>'d' and sznj=(select sznj from t_xssj_bzks
  where dke_op_type<>'d' and userid=#{U_用户名}) and userid !=#{U_用户名}''',
      // index 1: 同班级
      'class': '''
select count(distinct userid)as sj from t_xssj_bzks
where dke_op_type<>'d' and ssbj=(select ssbj from t_xssj_bzks
  where dke_op_type<>'d' and userid=#{U_用户名}) and userid !=#{U_用户名}''',
      // index 2: 同专业（限同年级）
      'major': '''
select count(distinct userid)as sj from t_xssj_bzks
where dke_op_type<>'d' and sszy=(select sszy from t_xssj_bzks
  where dke_op_type<>'d' and userid=#{U_用户名})
  and sznj=(select sznj from t_xssj_bzks
  where dke_op_type<>'d' and userid=#{U_用户名}) and userid !=#{U_用户名}''',
      // index 3: 同宿舍（舍友）
      'dorm': '''
select count(*) as zs from t_xssj_bzks
where ssdz=(select ssdz from t_xssj_bzks
  where dke_op_type<>'d' and userid=#{U_用户名})
  and dke_op_type<>'d' and userid !=#{U_用户名}''',
      // index 4: 同学院同天生日
      'college': '''
select count(*) as zs from t_xssj_bzks
where csrq=(select csrq from t_xssj_bzks
  where dke_op_type<>'d' and userid=#{U_用户名})
  and ssdw=(select ssdw from t_xssj_bzks
  where dke_op_type<>'d' and userid=#{U_用户名})
  and userid !=#{U_用户名} and dke_op_type<>'d' ''',
    };

    // ⚠ **五维并发**（2026-10-01 改）：从前 `for + await` 逐个打，五个
    // `count(distinct …)` 关联子查询串成一条链 —— 它又是首屏 19 个并发里
    // 唯一的"串行长尾"，整页的完成时间被它一个人拖住（一个慢查询 × 5）。
    // 维度之间无依赖，index 就是各自的指标位，并发不影响服务端语义。
    final entries = sqls.entries.toList();
    final got = await Future.wait([
      for (final (i, entry) in entries.indexed) _peerCountOf(s, entry.value, i),
    ]);
    final result = <String, int>{
      for (final (i, entry) in entries.indexed) entry.key: got[i] ?? -1,
    };
    // 全部维度均失败（会话失效等）→ 返回 null，视为整卡失败，
    // 以便上层正确触发会话刷新（否则非 null 会破坏 allFailed 判定）。
    if (result.values.every((v) => v == -1)) return null;
    return result;
  }

  /// 一个维度的 `count(distinct …)`（`data/get` + `index`）。
  ///
  /// 返回 null = 这一维取不到（上层记 -1 = 不展示）；会话失效**照抛**
  /// （[probeSession] / 仓库那一层要用它判断"该换会话了"）。
  Future<int?> _peerCountOf(DzjSession s, String sql, int index) async {
    try {
      final value = await dzjGuard(
        () async => dzjFirstNum(
          await dzjPostComponent(dio, '/api/app/component/data/get', {
            'datasourceID': '1',
            'sql': sql,
            'appId': 140,
            'componentId': 'u:fcd2d17a9131',
            'index': index,
          }, s),
          ['sj', 'zs'],
        ),
      );
      return value?.round();
    } on DzjSessionExpiredException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// 同侪 / 相关人员**名单**：`data/search` + `componentId` + `index`，回**该维度的行集**。
  ///
  /// 实测（2026-09-19 · 真会话）——
  /// **这个端点是「组件绑定」的：请求体里的 `sql` 一律被忽略**，区别只在 endpoint 与 index：
  /// - `data/get` + `index` → 一行聚合值 `{sj/zs: N}`（[fetchPeerCounts] 用的就是它）；
  /// - `data/search` + `index` → **该指标的行集** + `total`，列随维度走：
  ///   组件 `u:fcd2d17a9131`（校内关系）index 0 同年级 7905 人（`ssdw` 学院）/ 1 同班级 48 人
  ///   （`ssbj`）/ 2 同年级同专业 201 人（`sszy`）/ 3 **同宿舍 3 人（`ssxq` 校区）** /
  ///   4 同学院同生日 0 人；全部带 `ykth`（学号）+ `username`（姓名）+ `sznj`（年级）+ `sex`。
  ///   组件 `u:af43933a919c`（相关人员）index 0 同宿舍 3 人 / 1 同学院 1897 人 / 2 同专业 746 人 /
  ///   3 同班级 48 人 / 4 同天入校 7716 人 / 5 同天生日 17 人（**姓名脱敏** `甲**`），
  ///   行只有 `username` / `sex` / `userid`|`kh` / `dept`（无班级年级学号列 → 学校页面
  ///   本来也只显示「姓名 + 学院」）。
  /// - `filterConfig` 也认：`filterType:'sql'` 的谓词会被原样拼进 WHERE
  ///   （`username='同学己'` → total 1；`ssdw='会计学院'` → total 1057），
  ///   且**可以用 `#{U_用户名}` 占位**（服务端按会话解析成本人）——
  ///   「同年级同学院」就是这么来的（[DzjPeerDimension.gradeCollege] 自带的
  ///   [DzjPeerDimension.filterSql]，实测一次请求回 total 726）。
  ///
  /// [DzjPeerDimension.limit] 是 `pageSize`；服务端上限 [dzjMaxPeerPageSize]，
  /// 超了直接报 `50000 分数数据量不能大于500`（同年级 7905 人 → 客户端只取前 500 行，
  /// 但要**人数**请走 [fetchPeerCount]，别翻页去数）。
  ///
  /// 返回 null = 该维度整体失败（会话失效等），上层据此刷新会话后重试一次；
  /// 返回 [] = 服务端确实没有这个人（如「同学院同生日」实测 0 人）。
  Future<List<DzjPeer>?> fetchPeers(
    DzjSession s,
    DzjPeerDimension dimension, {
    int? limit,
  }) => dzjGuard(() async {
    final size = limit ?? dimension.limit;
    final data = await dzjPostComponent(dio, '/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': DzjApiRemoteDataSource.peerFilterOf(dimension),
      'pageNo': 1,
      'pageSize': size,
      'sortConfig': <Object?>[],
      'appId': 140,
      'componentId': dimension.source.componentId,
      'index': dimension.slot,
    }, s);
    return dzjPeersOf(data, size);
  });

  /// 某个维度（可带服务端过滤）的**行数**：`data/search` + `pageSize: 1`，只读 `total`。
  ///
  /// 用来拿「同年级同学院」的人数：同年级行集 7905 行、`pageSize` 上限 500，
  /// 自己翻页要 16 个请求；而 `total` 本来就是过滤后的总数 → **一次请求**拿到。
  ///
  /// 返回 null = 取不到（网络 / 会话失效 / 回包形状不认识）——「取不到」与「真的是 0 人」
  /// 必须分开，故 **0 原样返回、异常才 null**（界面据此决定是回退固定值还是不显示）。
  Future<int?> fetchPeerCount(
    DzjSession s,
    DzjPeerDimension dimension,
  ) => dzjGuard(() async {
    final data = await dzjPostComponent(dio, '/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': DzjApiRemoteDataSource.peerFilterOf(dimension),
      'pageNo': 1,
      'pageSize': 1,
      'sortConfig': <Object?>[],
      'appId': 140,
      'componentId': dimension.source.componentId,
      'index': dimension.slot,
    }, s);
    final total = dzjTotalOf(data, -1);
    return total < 0 ? null : total;
  });

  /// 「相关人员」六维的**人数**（`data/get` + index 0..5，六个请求并发）。
  ///
  /// 与 [fetchPeerCounts]（校内关系五维，走 `dzjPeerCountsProvider`）**分开取**：
  /// 两者都是次级信息，各自按需拉、卡片先显示「…」占位 —— 谁也不挡首屏
  /// （2026-10-01 前五维曾并进 `dataCenterOverviewProvider`，那让"进页面先见人"
  /// 卡在 5 个 `count(distinct)` 上）。
  ///
  /// 返回 null = 六维**全部**失败（会话失效等，上层据此不画数）；单个维度失败记 `-1`
  /// （界面把它当「这格没有数据」而不是谎报 0 人）。
  Future<Map<String, int>?> fetchRelatedCounts(DzjSession s) async {
    final dims = DzjPeerDimension.relatedDims;
    final values = await Future.wait([
      for (final d in dims) _relatedCount(s, d),
    ]);
    final result = {
      for (var i = 0; i < dims.length; i++) dims[i].key: values[i],
    };
    if (result.values.every((v) => v == -1)) return null;
    return result;
  }

  Future<int> _relatedCount(DzjSession s, DzjPeerDimension d) async {
    final value = await dzjGuard(
      () async => dzjFirstNum(
        await dzjPostComponent(dio, '/api/app/component/data/get', {
          'datasourceID': '1',
          'appId': 140,
          'componentId': d.source.componentId,
          'index': d.slot,
        }, s),
        dzjCountKeys,
      ),
    );
    return value?.round() ?? -1;
  }
}
