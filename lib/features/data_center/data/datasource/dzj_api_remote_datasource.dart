import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_crypto.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_basic_info.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_extra.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';

/// 个人数据中心组件接口通用异常（业务失败，非会话过期）。
class DzjApiException extends AppException {
  DzjApiException(super.message);
}

/// 竹简数据中台个人首页组件接口数据源。
///
/// 每个首页卡片对应一个组件接口（data/get / dve/getSql /
/// dve/getChartSql / data/search / tsa/* / data/getDynamicTextData）。
/// 请求体与响应 data 均按 [DzjCrypto] 协议加密。
/// SQL 中的 `#{U_用户名}` 占位符**必须原样保留**，由服务端替换
/// （实测手动替换成字面值会导致 errorCode 50000）。
class DzjApiRemoteDataSource {
  final Dio _dio;

  /// 应用页面地址与首页 pageKey（请求 Referer 与加密无关，但服务端校验）。
  static const String appUrl = '66eef481a9a3';
  static const String homePageKey = '82e98baafb40';
  static const String _referer =
      'https://dzj.jxufe.edu.cn/app/66eef481a9a3/82e98baafb40';

  DzjApiRemoteDataSource(this._dio);

  // ---- 低层收发 ----

  /// 发送加密组件请求，返回解密后的 JSON 值（Map / List / 标量）。
  ///
  /// HTTP 非 200、success=false、或 data 解密失败时抛 [DzjApiException]。
  /// 会话类问题由上层（仓库）统一判定并刷新重试。
  Future<dynamic> _postComponent(
    String path,
    Map<String, dynamic> body,
    DzjSession session,
  ) async {
    final cipher = DzjCrypto.encrypt(jsonEncode(body), session.fixedSalt);
    try {
      final response = await _dio.post<dynamic>(
        path,
        data: cipher,
        options: Options(
          headers: {
            'Host': 'dzj.jxufe.edu.cn',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                ' (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36'
                ' Edg/150.0.0.0',
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/json',
            'From': 'dzj-pc',
            'Referer': _referer,
            'Cookie': _sessionCookieHeader(session),
          },
        ),
      );

      final status = response.statusCode ?? 0;
      if (status != 200) {
        throw DzjApiException('接口请求失败（status=$status）');
      }

      final raw = response.data;
      if (raw is! Map) {
        throw DzjApiException('接口响应格式异常');
      }
      final success = raw['success'] == true;
      final errCode = raw['errorCode'];
      if (!success || errCode != null && errCode != '10000') {
        throw DzjApiException(
          '接口调用失败（code=$errCode, msg=${raw['errorMessage']}）',
        );
      }
      final data = raw['data'];
      if (data == null) {
        return null;
      }
      if (data is String) {
        final plain = DzjCrypto.decrypt(data, session.fixedSalt);
        return jsonDecode(plain);
      }
      return data;
    } on DzjApiException {
      rethrow;
    } on DioException catch (e) {
      throw DzjApiException('网络错误：${e.message}');
    } catch (e) {
      throw DzjApiException('请求异常：$e');
    }
  }

  /// 把 [DzjSession] 里那两个具名 Cookie 拼成请求头。
  ///
  /// ⚠ **刻意不用 `HostCookieJar`**（2026-09-20 架构审查）：dzj 的会话是**类型化**的
  /// —— 它只认 `SESSION` / `fixedSalt` 两个名字，`fixedSalt` 还要拿去解密响应体，
  /// 塞进「host → 名字 → 值」的通用桶反而丢掉类型与用途。见 §33.3 反例表。
  static String _sessionCookieHeader(DzjSession session) {
    final parts = <String>[];
    session.cookieHeader.forEach((k, v) => parts.add('$k=$v'));
    return parts.join('; ');
  }

  // ---- 卡片数据源（每项返回 null 表示该项获取失败，可容忍） ----

  Future<double?> fetchWeightedScore(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent(
        '/api/app/component/data/get',
        _dataGet('u:9206d2e048b4', '''
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

  Future<double?> fetchGpa(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent('/api/app/component/dve/getSql', {
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

  Future<double?> fetchSemesterCredit(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent(
        '/api/app/component/data/get',
        _dataGet('u:34c28a5c0914', '''
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

  Future<double?> fetchEarnedCredit(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent(
        '/api/app/component/data/get',
        _dataGet(
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
  Future<double?> fetchSpendYear(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent(
        '/api/app/component/data/get',
        _spendBody(
          componentId: 'u:7cc0ae6bc8f8',
          substr: "SUBSTR(jysj, 1,4)=SUBSTR(CURRENT_DATE::VARCHAR, 1,4)",
        ),
        s,
      ),
      ['je'],
    ),
  );
  Future<double?> fetchSpendMonth(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent(
        '/api/app/component/data/get',
        _spendBody(
          componentId: 'u:fae9f53d2605',
          substr: "SUBSTR(jysj, 1,7)=SUBSTR(CURRENT_DATE::VARCHAR, 1,7)",
        ),
        s,
      ),
      ['je'],
    ),
  );
  Future<double?> fetchSpendWeek(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent(
        '/api/app/component/data/get',
        _spendBody(componentId: 'u:fb76fd4a332f', weekSql: true),
        s,
      ),
      ['je'],
    ),
  );

  static Map<String, dynamic> _spendBody({
    required String componentId,
    String? substr,
    bool weekSql = false,
  }) {
    String sql;
    if (weekSql) {
      sql = '''
SELECT 
  CASE 
    WHEN SUM(ABS(jyje)) IS NULL THEN 0 
    ELSE SUM(ABS(jyje)) 
  END AS je 
FROM t_ykt_bnjy  
WHERE 
  jyje < 0  
  AND jysj::TIMESTAMP >= date_trunc('week', CURRENT_DATE)
  AND jysj::TIMESTAMP < date_trunc('week', CURRENT_DATE) + INTERVAL '1 week'
  AND userid=#{U_用户名} and dke_op_type <>'d' ''';
    } else {
      sql =
          "select case when sum(abs(jyje))is null then 0 else sum(abs(jyje))"
          " end as je  from t_ykt_bnjy  where jyje <0  and $substr"
          "   and userid=#{U_用户名} and dke_op_type <>'d'";
    }
    return {
      'datasourceID': '1',
      'sql': sql,
      'appId': 140,
      'componentId': componentId,
    };
  }

  /// 今日进出校门总次数。
  Future<double?> fetchGateToday(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent('/api/app/component/dve/getSql', {
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
  Future<double?> fetchCardBalance(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent(
        '/api/app/component/dve/getSql',
        _indexSqlBody(
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
  Future<double?> fetchTodayLogin(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent('/api/app/component/dve/getSql', {
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
  Future<double?> fetchNetworkBalance(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent(
        '/api/app/component/dve/getSql',
        _indexSqlBody(
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
  Future<double?> fetchTextbookFee(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent(
        '/api/app/component/dve/getSql',
        _indexSqlBody(
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

  Future<double?> fetchTextbookCount(DzjSession s) => _guard(
    () async => _firstNum(
      await _postComponent(
        '/api/app/component/dve/getSql',
        _indexSqlBody(
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
  Future<Map<String, int>?> fetchBorrowCounts(DzjSession s) => _guard(
    () async => _chartRowsToMap(
      await _postComponent('/api/app/component/dve/getChartSql', {
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
  Future<List<List<dynamic>>?> fetchLoginTrendRows(DzjSession s) => _guard(
    () async {
      final data = await _postComponent('/api/app/component/dve/getChartSql', {
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
      // 须取外层 'data' 键（与借书数量 _chartRowsToMap 同一响应形状）。
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
  }) => _guard(() async {
    final data = await _postComponent('/api/app/component/data/search', {
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
    return _rowsOf(data);
  });

  /// 奖助贷勤（奖学金等）文本行。
  Future<List<String>?> fetchAwards(DzjSession s) => _guard(() async {
    final data = await _postComponent('/api/app/component/data/search', {
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
    final rows = _rowsOf(data) ?? const [];
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
  }) => _guard(() async {
    final data = await _postComponent('/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': <Object?>[],
      'pageNo': 1,
      'pageSize': limit,
      'sortConfig': <Object?>[],
      'appId': 140,
      'componentId': _courseComponentId,
      'index': 0,
    }, s);
    final rows = _rowsOf(data) ?? const <Map<String, dynamic>>[];
    final items = dzjItemsOf(rows, dzjCourseItem);
    return (total: _totalOf(data, items.length), items: items);
  });

  /// 补充模块：图书馆座位预约（本年）。
  ///
  /// 实测（2026-09-19）：组件 `u:9b48c5bf91ad` 的 `data/search`（`index: 0`）回 52 条
  /// `{khnd 时间段 '2026-08-07 12:03:03~22:00:00', ndkh '麦庐园图书馆-麦庐园-三楼东', mc '自动签到'}`；
  /// 同组件的 `data/get` 会 50000（该组件没有聚合位）。
  Future<({int total, List<DzjInfoItem> items})?> fetchSeatBookings(
    DzjSession s, {
    int limit = 30,
  }) => _guard(() async {
    final data = await _postComponent('/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': <Object?>[],
      'pageNo': 1,
      'pageSize': limit,
      'sortConfig': <Object?>[],
      'appId': 140,
      'componentId': _seatComponentId,
      'index': 0,
    }, s);
    final rows = _rowsOf(data) ?? const <Map<String, dynamic>>[];
    final items = dzjItemsOf(rows, dzjSeatItem);
    return (total: _totalOf(data, items.length), items: items);
  });

  /// 补充模块：助学金（`u:631a812c461d`）+ 勤工助学（`u:b54d6f93ff2e`）。
  ///
  /// 两个组件与**已实现的奖学金**（[fetchAwards]）同型（`card-info-renderer`）：
  /// `data/search` + `componentId`，**不带 `index`**（带 index 会回空，奖学金实测如此）。
  /// 单边失败不影响另一边（各自 _guard）。
  Future<({int total, List<DzjInfoItem> items})?> fetchAidRecords(
    DzjSession s, {
    int limit = 20,
  }) async {
    final grant = await _aidRows(s, _grantComponentId, limit);
    final work = await _aidRows(s, _workStudyComponentId, limit);
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
  ) => _guard(() async {
    final data = await _postComponent('/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': <Object?>[],
      'pageNo': 1,
      'pageSize': limit,
      'sortConfig': <Object?>[],
      'appId': 140,
      'componentId': componentId,
    }, s);
    return _rowsOf(data);
  });

  /// 组件 id（实测确认，见各方法注释）。
  static const String _courseComponentId = 'u:94cf8d7765b0';
  static const String _seatComponentId = 'u:9b48c5bf91ad';
  static const String _grantComponentId = 'u:631a812c461d';
  static const String _workStudyComponentId = 'u:b54d6f93ff2e';

  /// 行集总数：优先用响应里的 `total`，取不到时退回**已解析条数**。
  static int _totalOf(dynamic data, int fallback) {
    if (data is Map) {
      final t = data['total'];
      if (t is num) return t.toInt();
      if (t is String) return int.tryParse(t) ?? fallback;
    }
    return fallback;
  }

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

    final result = <String, int>{};
    var index = 0;
    for (final entry in sqls.entries) {
      try {
        final value = await _guard(
          () async => _firstNum(
            await _postComponent('/api/app/component/data/get', {
              'datasourceID': '1',
              'sql': entry.value,
              'appId': 140,
              'componentId': 'u:fcd2d17a9131',
              'index': index,
            }, s),
            ['sj', 'zs'],
          ),
        );
        result[entry.key] = value?.round() ?? -1;
      } catch (_) {
        result[entry.key] = -1;
      }
      index++;
    }
    // 全部维度均失败（会话失效等）→ 返回 null，视为整卡失败，
    // 以便上层正确触发会话刷新（否则非 null 会破坏 allFailed 判定）。
    if (result.values.every((v) => v == -1)) return null;
    return result;
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
  }) => _guard(() async {
    final size = limit ?? dimension.limit;
    final data = await _postComponent('/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': peerFilterOf(dimension),
      'pageNo': 1,
      'pageSize': size,
      'sortConfig': <Object?>[],
      'appId': 140,
      'componentId': dimension.source.componentId,
      'index': dimension.slot,
    }, s);
    return _peersOf(data, size);
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
  ) => _guard(() async {
    final data = await _postComponent('/api/app/component/data/search', {
      'datasourceID': '1',
      'filterConfig': peerFilterOf(dimension),
      'pageNo': 1,
      'pageSize': 1,
      'sortConfig': <Object?>[],
      'appId': 140,
      'componentId': dimension.source.componentId,
      'index': dimension.slot,
    }, s);
    final total = _totalOf(data, -1);
    return total < 0 ? null : total;
  });

  /// 维度的 `filterConfig`：没声明 [DzjPeerDimension.filterSql] 就是空表（原样行集）。
  ///
  /// 公开给测试（请求体形状 = 「点同班看舍友」这类事故的防线）；运行时只由
  /// [fetchPeers] / [fetchPeerCount] 调。
  @visibleForTesting
  static List<Object?> peerFilterOf(DzjPeerDimension dimension) {
    final sql = dimension.filterSql;
    if (sql == null || sql.isEmpty) return const <Object?>[];
    return <Object?>[
      <String, Object?>{
        'columnName': '',
        'filterType': 'sql',
        'tableName': '',
        'type': 'VARCHAR2',
        'values': <Object?>[sql],
      },
    ];
  }

  /// 「相关人员」六维的**人数**（`data/get` + index 0..5，六个请求并发）。
  ///
  /// 与 [fetchPeerCounts]（校内关系五维，已并进 `dataCenterOverviewProvider`）分开取：
  /// 首屏已经有 20 个请求，再加 6 个只会让「数据一览」更慢，而这张卡本身就是次级信息
  /// → 由 `dzjRelatedCountsProvider` 按需拉，卡片先显示「…」占位。
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
    final value = await _guard(
      () async => _firstNum(
        await _postComponent('/api/app/component/data/get', {
          'datasourceID': '1',
          'appId': 140,
          'componentId': d.source.componentId,
          'index': d.slot,
        }, s),
        _countKeys,
      ),
    );
    return value?.round() ?? -1;
  }

  /// 计数 SQL 的别名候选（`select count(*) as zs/sj/sl/…`，别名没人管得住）。
  static const List<String> _countKeys = [
    'zs',
    'sj',
    'sl',
    'rs',
    'num',
    'count',
    'total',
    'cnt',
  ];

  /// 响应 → 名单（去重、排序、上限 [limit]）。
  ///
  /// 兼容三种载荷：`{data:[{行}]}`（data/get）、`{pageInfo:[{行}]}`（data/search）、
  /// 裸行数组；认不出人名的行丢弃。返回 null = 载荷形状完全不像行集。
  static List<DzjPeer>? _peersOf(dynamic data, int limit) {
    final rows = <Map<String, dynamic>>[];
    if (data is Map && data['data'] is List) {
      for (final r in data['data'] as List) {
        if (r is Map) rows.add(r.map((k, v) => MapEntry(k.toString(), v)));
      }
    } else {
      final list = _rowsOf(data);
      if (list == null) return null;
      rows.addAll(list);
    }
    final seen = <String>{};
    final peers = <DzjPeer>[];
    for (final row in rows) {
      final peer = DzjPeer.fromRow(row);
      if (peer == null) continue;
      // 同一个人可能有多行（`dke_op_type` 软删标记留下的历史行）→ 去重
      if (!seen.add(peer.userId.isEmpty ? peer.name : peer.userId)) continue;
      peers.add(peer);
      if (peers.length >= limit) break;
    }
    return DzjPeer.sorted(peers);
  }

  /// 动态身份文本（姓名/学号/学院/班主任/班主任电话）。
  Future<Map<String, String>> fetchIdentityTexts(DzjSession s) async {
    const fields = <String, String>{
      'username': 'u:97019a44a735',
      'userid': 'u:6e8a5f94005d',
      'ssdw': 'u:a56e2d07cc33',
      'bzrxm': 'u:ee1581a17fe0',
      'bzrsjh': 'u:3acfa51c6b45',
    };
    final result = <String, String>{};
    for (final entry in fields.entries) {
      try {
        final data = await _postComponent(
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
          result[entry.key] = data[entry.key].toString();
        }
      } catch (_) {
        // 单项失败不影响其余
      }
    }
    return result;
  }

  /// 当前周次信息（weeks 数组：rq/zc/zcmc/xq/xqmc/title）与今日课程。
  Future<List<Map<String, dynamic>>?> fetchWeekDays(DzjSession s) =>
      _guard(() async {
        final today = _today();
        final data = await _postComponent('/api/app/component/tsa/getTodayZc', {
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
  Future<int?> fetchTodayClassCount(DzjSession s) => _guard(() async {
    final data = await _postComponent('/api/app/component/tsa/getWeekClass', {
      'sysdate': _today(),
    }, s);
    if (data is Map && data['weekClass'] is List) {
      return (data['weekClass'] as List).length;
    }
    return 0;
  });

  // ---- 子页面（页面树 / 页面定义 / 通用取数） ----

  /// 应用**页面树**（十个子页面的唯一出处）。
  ///
  /// `POST /api/page/manageTreeByVersion`
  /// `{"url": "66eef481a9a3", "accessFlag": 1, "type": "web"}` → `{"tree": [...]}`。
  /// ⚠ 入参抄自学校前端（`js_umi` 的 `o6`）：**「应用唯一标识」字段名是 `url`**，
  /// appId/appUrl/appUniqueId/appCode 一律被判「应用唯一标识不能为空」；
  /// `accessFlag` 传数字 1 或字符串 `"1"` 都行；`type` = `web`（`mobile` 回包相同）。
  /// 用 **ByVersion** 而不是 `manageTree`：后者回的是**全量**（含「（研）」「备份」
  /// 「纠错管理」等未发布页，实测 25 个节点），前者只回当前发布版（11 个节点）。
  Future<Object?> fetchPageTree(DzjSession s) =>
      _postComponent('/api/page/manageTreeByVersion', {
        'url': appUrl,
        'accessFlag': 1,
        'type': 'web',
      }, s);

  /// 任意子页面的**页面定义**（amis body），供通用渲染器解析。
  Future<Object?> fetchPageBody(DzjSession s, String pageKey) =>
      _postComponent('/api/page/searchBodyByVersion', {
        'appId': 140,
        'accessFlag': '1',
        'pageKey': pageKey,
        'appUrl': appUrl,
      }, s);

  /// 单个组件的**聚合值**（`data/get`，`index: 0`）—— kpi / 文本类卡片。
  ///
  /// 空结果返回 null（不回空 Map，方便上层换端点兜底）。
  Future<Map<String, dynamic>?> fetchBlockValue(
    DzjSession s,
    String componentId, {
    int index = 0,
  }) => _postComponent('/api/app/component/data/get', {
    'datasourceID': '1',
    'appId': 140,
    'componentId': componentId,
    'index': index,
  }, s).then((d) => d is Map && d.isNotEmpty ? d.cast<String, dynamic>() : null);

  /// 单个组件的**行集**。
  ///
  /// - `slot == null`（普通表格 / 图表）：走 `data/list` —— 表格类组件**只认它**
  ///   （同一个 componentId 打 `data/search` 恒回 `{"pageInfo": [], "total": 0}`，
  ///   实测「任课教师情况」；换 `data/list` 立刻回 37 行）。**不需要 `index`**，
  ///   回包是**裸数组**（不是 pageInfo 包装）。
  /// - `slot != null`（名单类组件的第几路，如 `data-xiangguan-render` 的 `timeList[i]`）：
  ///   走 `data/search` + `index: slot`（与 `fetchPeers` 同一姿势），回
  ///   `{pageInfo: [...], total}`。
  Future<List<Map<String, dynamic>>?> fetchBlockRows(
    DzjSession s,
    String componentId, {
    int pageSize = 60,
    int? slot,
  }) => _postComponent(
    slot == null ? '/api/app/component/data/list' : '/api/app/component/data/search',
    {
      'datasourceID': '1',
      'appId': 140,
      'componentId': componentId,
      'index': ?slot,
      'pageNo': 1,
      'pageSize': pageSize,
      'sortConfig': <Object?>[],
      'filterConfig': <Object?>[],
    },
    s,
  ).then((d) {
    final raw = switch (d) {
      List() => d,
      Map() => d['pageInfo'] ?? d['list'] ?? d['rows'],
      _ => null,
    };
    if (raw is! List) return null;
    final rows = raw.whereType<Map>().map((r) => r.cast<String, dynamic>()).toList();
    return rows.isEmpty ? null : rows;
  });

  /// **数据对象**行集 —— 学校页面上所有表格明细的唯一可用通道。
  ///
  /// 用户 2026-09-20 八轮：「还是看不到详细参加了哪些竞赛，这些竞赛的分级、时间」。
  /// 学科竞赛明细（`u:f85c95577ecf`）用 `data/list` 恒 `[]`、`data/search` 恒
  /// `{pageInfo:[],total:0}`，只有这条端点回 15 行真实记录：
  ///
  /// ```text
  /// POST /api/app/component/data/dataList
  /// {dataObjectId:'1215f9f0…', datasourceID:'1', dbType:'postgresql',
  ///  schemaName:'usr_bsp', fieldList:[…], filterConfig:[],
  ///  dataFilterSql:'userid=#{U_用户名}', componentId, appId:140}
  /// ```
  ///
  /// ⚠ `filterSql` **必须带**（形如 `userid=#{U_用户名}`，服务端解析成本人）：留空会
  /// 回传全校几万行 —— 端点没有行级权限兜底。
  /// 回包列名是**小写**的数据库列名（`bsmc` / `hdsj` …）。
  Future<List<Map<String, dynamic>>?> fetchDataObjectRows(
    DzjSession s, {
    required String componentId,
    required String dataObjectId,
    required String filterSql,
    required List<Map<String, Object?>> fieldList,
    int pageSize = 60,
  }) {
    if (dataObjectId.isEmpty || filterSql.isEmpty || fieldList.isEmpty) {
      return Future.value(null);
    }
    return _postComponent('/api/app/component/data/dataList', {
      'dataObjectId': dataObjectId,
      'datasourceID': '1',
      'dbType': 'postgresql',
      'schemaName': 'usr_bsp',
      'fieldList': fieldList,
      'filterConfig': <Object?>[],
      'dataFilterSql': filterSql,
      'componentId': componentId,
      'appId': 140,
      'pageNo': 1,
      'pageSize': pageSize,
    }, s).then((d) {
      final raw = switch (d) {
        List() => d,
        Map() => d['pageInfo'] ?? d['list'] ?? d['rows'] ?? d['data'],
        _ => null,
      };
      if (raw is! List) return null;
      final rows = raw
          .whereType<Map>()
          .map((r) => r.cast<String, dynamic>())
          .toList();
      return rows.isEmpty ? null : rows;
    });
  }

  /// 「基本信息」表单的 39 项字段值 —— 走 `tsa/getFormData`（见 [DzjBasicField]）。
  ///
  /// `account` 用于**串号校验**：这个端点在 `filterConfig` 缺失时会回别的学生的整份资料
  /// （实测回成留学生 留学生甲），`dzjBasicInfoFromJson` 会因此丢掉整份回包。
  Future<Map<String, String>?> fetchBasicInfo(
    DzjSession s, {
    required String account,
  }) => _postComponent('/api/app/component/tsa/getFormData',
              dzjBasicInfoRequest(), s)
          .then(
            (d) => d == null ? null : dzjBasicInfoFromJson(d, account: account),
          );

  // ---- 解析辅助 ----

  static String _today() {
    final now = DateTime.now();
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '${now.year}-$mm-$dd';
  }

  static Map<String, dynamic> _dataGet(String componentId, String sql) => {
    'sql': sql,
    'datasourceID': '1',
    'componentId': componentId,
    'appId': 140,
  };

  static Map<String, dynamic> _indexSqlBody({
    required int amId,
    required String componentId,
    required String filter,
    required String aliasName,
    required String dataField,
    required String dataObject,
    required String expression,
    required String fieldName,
  }) => {
    'amId': amId,
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
        'values': [filter],
      },
    ],
    'xAxisInfoList': <Object?>[],
    'yAxisInfoList': [
      {
        'aliasName': aliasName,
        'dataField': dataField,
        'dataObject': dataObject,
        'isIndex': 0,
        'sqlExpression': expression,
        'fieldName': fieldName,
      },
    ],
    'appId': 140,
    'componentId': componentId,
    'emptyConfig': {'displayType': '', 'customText': ''},
  };

  /// 单个取值卡片：从 map 或 {"data":[{...}]} 中取第一行指定字段的数值。
  static double? _firstNum(dynamic data, List<String> keys) {
    Map<String, dynamic> row;
    if (data is Map &&
        data['data'] is List &&
        (data['data'] as List).isNotEmpty) {
      final first = (data['data'] as List).first;
      if (first is Map) {
        row = first.map((k, v) => MapEntry(k.toString(), v));
      } else {
        return null;
      }
    } else if (data is Map) {
      row = data.map((k, v) => MapEntry(k.toString(), v));
    } else {
      return null;
    }
    for (final k in keys) {
      final v = row[k];
      if (v is num) return v.toDouble();
      if (v is String && v.isNotEmpty) {
        final n = double.tryParse(v);
        if (n != null) return n;
      }
    }
    return null;
  }

  /// data/search 响应：{"pageInfo":[...] , "total": n} 或直接行数组。
  static List<Map<String, dynamic>>? _rowsOf(dynamic data) {
    if (data is Map && data['pageInfo'] is List) {
      return (data['pageInfo'] as List)
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return null;
  }

  /// 图表矩阵（首行表头，后续行 label/value）→ `Map<String, int>`。
  static Map<String, int>? _chartRowsToMap(dynamic data) {
    if (data is! Map) return null;
    final rows = data['data'];
    if (rows is! List) return null;
    final result = <String, int>{};
    for (final row in rows) {
      if (row is! List || row.length < 2) continue;
      final label = row[0].toString();
      if (label == 'product') continue;
      final v = row[1];
      result[label] = v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0;
    }
    return result;
  }

  /// 包装单项请求，把任何异常转成 null（容忍单卡失败）。
  static Future<T?> _guard<T>(Future<T?> Function() fn) async {
    try {
      return await fn();
    } catch (_) {
      return null;
    }
  }
}
