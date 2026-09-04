import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_crypto.dart';

/// 个人数据中心组件接口通用异常（业务失败，非会话过期）。
class DzjApiException implements Exception {
  final String message;
  DzjApiException(this.message);

  @override
  String toString() => 'DzjApiException: $message';
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
            'Cookie': _cookieHeader(session),
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

  static String _cookieHeader(DzjSession session) {
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

  /// 同侪对比：同年级 / 同班级 / 同专业 / 同宿舍 / 同学院同生日人数
  /// （组件 u:fcd2d17a9131，同一 componentId 用 index 区分维度）。
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
    return result;
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
