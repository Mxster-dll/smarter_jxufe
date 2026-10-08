/// 竹简数据中台 · 本人数据卡取数（extension）
///
/// 学业 / 指标 / 一卡通 / 图书 / 登录趋势 / 扩展模块（本学期课程 · 座位预约 · 奖助勤）/ 身份文本 / 周次，共 24 个方法。
///
/// 拆分自 `dzj_api_remote_datasource.dart`（2026-10-08 架构审计第三轮 · 第二阶段）：
/// 这类只有 `dio` 一个字段，所以整组方法**用 extension 搬走** —— 方法名一字不改、
/// 零 wrapper、调用点连 import 都不用动（本文件被 `dzj_api_remote_datasource.dart`
/// `export`，import 它就等于 import 这里）。口径见 AGENTS.md §33.4.4。
library;

import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_support.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_extra.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_remote_datasource.dart';

extension DzjApiCards on DzjApiRemoteDataSource {

  // ---- 卡片数据源（每项返回 null 表示该项获取失败，可容忍） ----

  Future<double?> fetchWeightedScore(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(
      dio,
        '/api/app/component/data/get',
        dzjDataGet('u:9206d2e048b4', '''
SELECT 
  COALESCE(
    (
     select jqpjcj from t_bzks_zjqpjcj where  dke_op_type <> 'd' AND userid=#{U_用户名}
    ),
    0
  ) AS pm'''),
        s,
      ),
      ['pm'],
    ),
  );

  Future<double?> fetchGpa(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(dio, '/api/app/component/dve/getSql', {
        'amId': 11,
        'chartType': 'index',
        'dataRange': null,
        'orderInfoList': <Object?>[],
        'legendInfoList': <Object?>[],
        'filterInfoList': [
          {
            'columnName': '',
            'filterType': 'sql',
            'tableName': '',
            'type': 'VARCHAR2',
            'values': ['ykth=#{U_用户名}'],
          },
        ],
        'xAxisInfoList': <Object?>[],
        'yAxisInfoList': [
          {
            'aliasName': 'pjjd',
            'dataField': 'pjjd',
            'dataObject': 't_xssj_bkskscj',
            'isIndex': 0,
            'sqlExpression': 'round(avg(t_xssj_bkskscj.jd),2)',
            'fieldName': '平均绩点',
          },
        ],
        'appId': 140,
        'componentId': 'u:8cd524cf4802',
        'emptyConfig': {'displayType': '', 'customText': ''},
      }, s),
      ['pjjd'],
    ),
  );

  Future<double?> fetchSemesterCredit(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(
      dio,
        '/api/app/component/data/get',
        dzjDataGet('u:34c28a5c0914', '''
SELECT COALESCE(SUM(xf), 0) AS xf 
FROM (
    SELECT DISTINCT kcdm, xf 
    FROM t_bzks_xkxx 
    WHERE xn = (SELECT dqxn FROM v_dqxnxq) 
      AND ykth = #{U_用户名} and dke_op_type<>'d'
) AS temp'''),
        s,
      ),
      ['xf'],
    ),
  );

  Future<double?> fetchEarnedCredit(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(
      dio,
        '/api/app/component/data/get',
        dzjDataGet(
          'u:ae2ea25db391',
          '''
select coalesce(sum(a.hdxf),0) xf from t_xssj_bkskscj a  
inner join usr_data.v_adm_xsjbxx xs on xs.ykth=a.ykth
where a.dke_op_type<>'d' and a.qdfs='初修取得' and xs.ykth=#{U_用户名} and a.qdxn=(select dqxn from v_dqxnxq)''',
        ),
        s,
      ),
      ['xf'],
    ),
  );

  /// 本年 / 当月 / 本周 校园卡消费金额（元）。
  Future<double?> fetchSpendYear(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(
      dio,
        '/api/app/component/data/get',
        dzjSpendBody(
          componentId: 'u:7cc0ae6bc8f8',
          substr: "SUBSTR(jysj, 1,4)=SUBSTR(CURRENT_DATE::VARCHAR, 1,4)",
        ),
        s,
      ),
      ['je'],
    ),
  );

  Future<double?> fetchSpendMonth(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(
      dio,
        '/api/app/component/data/get',
        dzjSpendBody(
          componentId: 'u:fae9f53d2605',
          substr: "SUBSTR(jysj, 1,7)=SUBSTR(CURRENT_DATE::VARCHAR, 1,7)",
        ),
        s,
      ),
      ['je'],
    ),
  );

  Future<double?> fetchSpendWeek(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(
      dio,
        '/api/app/component/data/get',
        dzjSpendBody(componentId: 'u:fb76fd4a332f', weekSql: true),
        s,
      ),
      ['je'],
    ),
  );

  /// 今日进出校门总次数。
  Future<double?> fetchGateToday(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(dio, '/api/app/component/dve/getSql', {
        'amId': 21,
        'chartType': 'index',
        'dataRange': null,
        'orderInfoList': <Object?>[],
        'legendInfoList': <Object?>[],
        'filterInfoList': [
          {
            'columnName': '',
            'filterType': 'sql',
            'tableName': '',
            'type': 'VARCHAR2',
            'values': [
              'userid=#{U_用户名} and SUBSTR(jcsj, 1,10)=SUBSTR(CURRENT_DATE::varchar, 1,10)',
            ],
          },
        ],
        'xAxisInfoList': <Object?>[],
        'yAxisInfoList': [
          {
            'aliasName': 'jcxm',
            'dataField': 'id',
            'dataObject': 't_ry_mjjl',
            'isIndex': 0,
            'sqlExpression': 'count(t_ry_mjjl.id)',
            'fieldName': '进出校门总次数',
          },
        ],
        'appId': 140,
        'componentId': 'u:b7ddc67eeb78',
        'emptyConfig': {'displayType': '', 'customText': ''},
      }, s),
      ['jcxm'],
    ),
  );

  /// 校园卡余额。
  Future<double?> fetchCardBalance(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(
      dio,
        '/api/app/component/dve/getSql',
        dzjIndexSqlBody(
          amId: 19,
          componentId: 'u:7240e9b0bce6',
          filter: 'userid=#{U_用户名}',
          aliasName: 'kye',
          dataField: 'kye',
          dataObject: 'v_ykt_zhyecx',
          expression: 'max(v_ykt_zhyecx.kye)',
          fieldName: 'kye',
        ),
        s,
      ),
      ['kye'],
    ),
  );

  /// 今日登录门户次数。
  Future<double?> fetchTodayLogin(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(dio, '/api/app/component/dve/getSql', {
        'amId': 17,
        'chartType': 'index',
        'dataRange': null,
        'orderInfoList': <Object?>[],
        'legendInfoList': <Object?>[],
        'filterInfoList': [
          {
            'columnName': '',
            'filterType': 'sql',
            'tableName': '',
            'type': 'VARCHAR2',
            'values': [
              "dke_op_type<>'d' and DATE(dlsj) = CURRENT_DATE and zt='登入' and userid=#{U_用户名}",
            ],
          },
        ],
        'xAxisInfoList': <Object?>[],
        'yAxisInfoList': [
          {
            'aliasName': 'drdlmhcs',
            'dataField': '',
            'dataObject': '',
            'isIndex': 0,
            'sqlExpression': 'count(*)',
            'fieldName': '当日登录门户次数',
          },
        ],
        'appId': 140,
        'componentId': 'u:4d41e9058e33',
        'emptyConfig': {'displayType': '', 'customText': ''},
      }, s),
      ['drdlmhcs'],
    ),
  );

  /// 网费余额。
  Future<double?> fetchNetworkBalance(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(
      dio,
        '/api/app/component/dve/getSql',
        dzjIndexSqlBody(
          amId: 22,
          componentId: 'u:5ce6a52208a0',
          filter: 'userid=#{U_用户名}',
          aliasName: 'wfye',
          dataField: 'wfye',
          dataObject: 't_ry_wf',
          expression: 'max(t_ry_wf.wfye)',
          fieldName: '网费余额',
        ),
        s,
      ),
      ['wfye'],
    ),
  );

  /// 教材费用 / 教材总数。
  Future<double?> fetchTextbookFee(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(
      dio,
        '/api/app/component/dve/getSql',
        dzjIndexSqlBody(
          amId: 80,
          componentId: 'u:943627a9c9c8',
          filter:
              'userid = #{U_用户名}\n  AND  gmsq = (select xnxqmc from v_dqxnxq  )',
          aliasName: 'jcfy',
          dataField: 'dj',
          dataObject: 't_xssj_jcgmjl',
          expression: 'sum(t_xssj_jcgmjl.dj::numeric)',
          fieldName: '教材费用',
        ),
        s,
      ),
      ['jcfy'],
    ),
  );

  Future<double?> fetchTextbookCount(DzjSession s) => dzjGuard(
    () async => dzjFirstNum(
      await dzjPostComponent(
      dio,
        '/api/app/component/dve/getSql',
        dzjIndexSqlBody(
          amId: 80,
          componentId: 'u:a79070bed6f4',
          filter:
              'userid = #{U_用户名}\n  AND  gmsq = (select xnxqmc from v_dqxnxq  )',
          aliasName: 'jczs',
          dataField: 'id',
          dataObject: 't_xssj_jcgmjl',
          expression: 'count(distinct t_xssj_jcgmjl.id)',
          fieldName: '教材总数',
        ),
        s,
      ),
      ['jczs'],
    ),
  );

  /// 借书数量矩阵（本周/本月/本年），返回 label→数量的映射。
  Future<Map<String, int>?> fetchBorrowCounts(DzjSession s) => dzjGuard(
    () async => dzjChartRowsToMap(
      await dzjPostComponent(dio, '/api/app/component/dve/getChartSql', {
        'sql': '''
SELECT
  UNNEST(ARRAY['本周', '本月', '本年']) AS tj,
  UNNEST(ARRAY[
    COUNT(CASE WHEN jcrq >= date_trunc('week', CURRENT_DATE)::date AND jcrq < date_trunc('week', CURRENT_DATE)::date + INTERVAL '7 days' THEN 1 END),
    COUNT(CASE WHEN EXTRACT(YEAR FROM jcrq) = EXTRACT(YEAR FROM CURRENT_DATE) AND EXTRACT(MONTH FROM jcrq) = EXTRACT(MONTH FROM CURRENT_DATE) THEN 1 END),
    COUNT(CASE WHEN EXTRACT(YEAR FROM jcrq) = EXTRACT(YEAR FROM CURRENT_DATE) THEN 1 END)
  ]) AS sl
FROM t_ry_zjts 
WHERE userid = #{U_用户名}''',
        'datasourceID': '1',
        'chartType': 'column',
        'filterInfoList': <Object?>[],
        'xAxisInfoList': [
          {'dataField': 'tj'},
        ],
        'yAxisInfoList': [
          {'dataField': 'sl', 'indexType': 'sum', 'fieldName': '借书数量'},
        ],
        'legendInfoList': <Object?>[],
        'dataRange': null,
        'orderInfoList': <Object?>[],
        'appId': 140,
        'componentId': 'u:ce9ef7f9bc46',
      }, s),
    ),
  );

  /// 门户登录趋势（本周每日），返回 星期一~星期日 次数列表。
  Future<List<List<dynamic>>?> fetchLoginTrendRows(DzjSession s) => dzjGuard(
    () async {
      final data = await dzjPostComponent(dio, '/api/app/component/dve/getChartSql', {
        'sql': '''
WITH week_dates AS (
  SELECT
    generate_series(
      date_trunc('week', CURRENT_TIMESTAMP)::timestamp, 
      date_trunc('week', CURRENT_TIMESTAMP)::timestamp + INTERVAL '6 days', 
      INTERVAL '1 day'
    ) AS day_date,
    unnest(ARRAY['星期一','星期二','星期三','星期四','星期五','星期六','星期日']) AS week_name
)
SELECT
  w.week_name AS xqj,
  COALESCE(COUNT(t.dlsj), 0) AS dlcs  
FROM week_dates w
LEFT JOIN t_mh_dljl t ON
  t.userid = #{U_用户名}
  AND to_timestamp(t.dlsj, 'YYYY-MM-DD HH24:MI:SS') >= w.day_date
  AND to_timestamp(t.dlsj, 'YYYY-MM-DD HH24:MI:SS') < w.day_date + INTERVAL '1 day'
GROUP BY w.week_name, w.day_date
ORDER BY w.day_date''',
        'datasourceID': '1',
        'chartType': 'line',
        'filterInfoList': <Object?>[],
        'xAxisInfoList': [
          {'dataField': 'xqj'},
        ],
        'yAxisInfoList': [
          {'dataField': 'dlcs', 'indexType': 'sum', 'fieldName': '门户登录次数'},
        ],
        'legendInfoList': <Object?>[],
        'dataRange': null,
        'orderInfoList': <Object?>[],
        'appId': 140,
        'componentId': 'u:2727e266508a',
      }, s);
      // getChartSql 解密结果为 {"data": [["product", ...], [星期一, n], ...]}，
      // 须取外层 'data' 键（与借书数量 dzjChartRowsToMap 同一响应形状）。
      if (data is Map && data['data'] is List) {
        final rows = (data['data'] as List)
            .whereType<List>()
            .map((r) => r.cast<dynamic>())
            .toList();
        return rows.isEmpty ? null : rows;
      }
      return null;
    },
  );

  /// 本年消费明细（店铺/时间/金额），最多 [limit] 条。
  Future<List<Map<String, dynamic>>?> fetchConsumeRecords(
    DzjSession s, {
    int limit = 20,
  }) => dzjGuard(() async {
    final data = await dzjPostComponent(dio, '/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': <Object?>[],
      'pageNo': 1,
      'pageSize': limit,
      'sortConfig': <Object?>[],
      'sql':
          'select shmc,SUBSTR(jysj, 1,19) as jysj,abs(jyje)  as jyje'
          " from t_ykt_bnjy  where jyje <0  and   userid=#{U_用户名}  and dke_op_type <>'d'"
          ' ORDER BY jysj desc',
      'appId': 140,
      'componentId': 'u:66549841d896',
    }, s);
    return dzjRowsOf(data);
  });

  /// 奖助贷勤（奖学金等）文本行。
  Future<List<String>?> fetchAwards(DzjSession s) => dzjGuard(() async {
    final data = await dzjPostComponent(dio, '/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': <Object?>[],
      'pageNo': 1,
      'pageSize': 10,
      'sortConfig': <Object?>[],
      'sql':
          """select   jxjlb,  '申请年份：'||SUBSTR(sqsj, 1,4) ||'年'||'                     '||'获得年份：'||COALESCE(SUBSTR(xgcspsj, 1,4)||'年', '暂无数据') as sqsj,shzt||'('||hjje||'元)' as shzt from  t_xssj_jxj   where  userid=#{U_用户名}   AND dke_op_type <>'d'""",
      'appId': 140,
      'componentId': 'u:2573d62e3214',
    }, s);
    final rows = dzjRowsOf(data) ?? const [];
    return rows.map((r) {
      final lb = r['jxjlb']?.toString() ?? '';
      final t = r['sqsj']?.toString() ?? '';
      final st = r['shzt']?.toString() ?? '';
      return [lb, t, st].where((x) => x.isNotEmpty).join('  ');
    }).toList();
  });

  /// 补充模块：本学期选修课程（门数 + 课程清单）。
  ///
  /// 实测（2026-09-19）：组件 `u:94cf8d7765b0` 的 `data/get` 回 `{ms: 21}`（门数），
  /// 同一个 componentId 的 `data/search`（**带 `index: 0`**）回课程行集
  /// `{kcmc 课程名, kclb 类别, khfs 考核方式, xdxz 修读性质, kcxf 学分}` + `total`。
  /// 该组件内嵌 SQL 里写死过一个旧学号（`ykth='2202300001'`），但**请求体里的 sql 会被
  /// 服务端忽略**（组件绑定），所以取回来的是当前登录人自己的课 —— 实测 21 门。
  Future<({int total, List<DzjInfoItem> items})?> fetchSemesterCourses(
    DzjSession s, {
    int limit = 50,
  }) => dzjGuard(() async {
    final data = await dzjPostComponent(dio, '/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': <Object?>[],
      'pageNo': 1,
      'pageSize': limit,
      'sortConfig': <Object?>[],
      'appId': 140,
      'componentId': dzjCourseComponentId,
      'index': 0,
    }, s);
    final rows = dzjRowsOf(data) ?? const <Map<String, dynamic>>[];
    final items = dzjItemsOf(rows, dzjCourseItem);
    return (total: dzjTotalOf(data, items.length), items: items);
  });

  /// 补充模块：图书馆座位预约（本年）。
  ///
  /// 实测（2026-09-19）：组件 `u:9b48c5bf91ad` 的 `data/search`（`index: 0`）回 52 条
  /// `{khnd 时间段 '2026-08-07 12:03:03~22:00:00', ndkh '麦庐园图书馆-麦庐园-三楼东', mc '自动签到'}`；
  /// 同组件的 `data/get` 会 50000（该组件没有聚合位）。
  Future<({int total, List<DzjInfoItem> items})?> fetchSeatBookings(
    DzjSession s, {
    int limit = 30,
  }) => dzjGuard(() async {
    final data = await dzjPostComponent(dio, '/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': <Object?>[],
      'pageNo': 1,
      'pageSize': limit,
      'sortConfig': <Object?>[],
      'appId': 140,
      'componentId': dzjSeatComponentId,
      'index': 0,
    }, s);
    final rows = dzjRowsOf(data) ?? const <Map<String, dynamic>>[];
    final items = dzjItemsOf(rows, dzjSeatItem);
    return (total: dzjTotalOf(data, items.length), items: items);
  });

  /// 补充模块：助学金（`u:631a812c461d`）+ 勤工助学（`u:b54d6f93ff2e`）。
  ///
  /// 两个组件与**已实现的奖学金**（[fetchAwards]）同型（`card-info-renderer`）：
  /// `data/search` + `componentId`，**不带 `index`**（带 index 会回空，奖学金实测如此）。
  /// 单边失败不影响另一边（各自 dzjGuard）。
  Future<({int total, List<DzjInfoItem> items})?> fetchAidRecords(
    DzjSession s, {
    int limit = 20,
  }) async {
    // 两个组件互不依赖 → 并发（从前是两次串行 await，白等一个往返）。
    final both = await Future.wait([
      _aidRows(s, dzjGrantComponentId, limit),
      _aidRows(s, dzjWorkStudyComponentId, limit),
    ]);
    final grant = both[0];
    final work = both[1];
    if (grant == null && work == null) return null;
    final items = [
      ...dzjItemsOf(grant ?? const [], dzjGrantItem),
      ...dzjItemsOf(work ?? const [], dzjWorkStudyItem),
    ];
    return (total: items.length, items: items);
  }

  Future<List<Map<String, dynamic>>?> _aidRows(
    DzjSession s,
    String componentId,
    int limit,
  ) => dzjGuard(() async {
    final data = await dzjPostComponent(dio, '/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': <Object?>[],
      'pageNo': 1,
      'pageSize': limit,
      'sortConfig': <Object?>[],
      'appId': 140,
      'componentId': componentId,
    }, s);
    return dzjRowsOf(data);
  });

  /// 动态身份文本（姓名/学号/学院/班主任/班主任电话）。
  ///
  /// ⚠ **5 条并发**（2026-10-01 改）：从前是 `for + await` 一条条打，而它又在
  /// [DataCenterRepository] 的首屏批次**之后**才被调用 → 成了整页唯一一段
  /// 纯串行尾巴（5 次往返，实测 64ms @ 热连接、冷连接更贵）。五个字段之间
  /// 没有任何先后依赖，白等 4 个往返。
  Future<Map<String, String>> fetchIdentityTexts(DzjSession s) async {
    const fields = <String, String>{
      'username': 'u:97019a44a735',
      'userid': 'u:6e8a5f94005d',
      'ssdw': 'u:a56e2d07cc33',
      'bzrxm': 'u:ee1581a17fe0',
      'bzrsjh': 'u:3acfa51c6b45',
    };

    Future<(String, String)?> one(MapEntry<String, String> entry) async {
      try {
        final data = await dzjPostComponent(
      dio,
          '/api/app/component/data/getDynamicTextData',
          {
            'dataObjectId': 'fd7fac78acd54660b7405fb515a0fc96',
            'datasourceID': '1',
            'filterConfig': <Object?>[],
            'componentId': entry.value,
            'dynamicParamConfig': {
              'dynamicField': 'userid',
              'dynamicParam': '#{U_用户名}',
            },
            'appId': 140,
            'textField': entry.key,
          },
          s,
        );
        if (data is Map && data[entry.key] != null) {
          return (entry.key, data[entry.key].toString());
        }
      } on DzjSessionExpiredException {
        rethrow; // 会话失效不参与「单项失败不影响其余」
      } catch (_) {
        // 单项失败不影响其余
      }
      return null;
    }

    final got = await Future.wait(fields.entries.map(one));
    return {
      for (final e in got)
        if (e != null) e.$1: e.$2,
    };
  }

  /// 当前周次信息（weeks 数组：rq/zc/zcmc/xq/xqmc/title）与今日课程。
  Future<List<Map<String, dynamic>>?> fetchWeekDays(DzjSession s) =>
      dzjGuard(() async {
        final today = dzjToday();
        final data = await dzjPostComponent(dio, '/api/app/component/tsa/getTodayZc', {
          'sysdate': today,
          'datasourceID': 0,
        }, s);
        if (data is Map && data['weeks'] is List) {
          return (data['weeks'] as List)
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        }
        return null;
      });

  /// 今日课程数（weekClass 列表长度）。
  Future<int?> fetchTodayClassCount(DzjSession s) => dzjGuard(() async {
    final data = await dzjPostComponent(dio, '/api/app/component/tsa/getWeekClass', {
      'sysdate': dzjToday(),
    }, s);
    if (data is Map && data['weekClass'] is List) {
      return (data['weekClass'] as List).length;
    }
    return 0;
  });
}
