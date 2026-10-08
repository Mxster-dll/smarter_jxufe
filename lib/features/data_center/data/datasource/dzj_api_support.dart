/// 竹简数据中台 API 的**低层收发与解析辅助**（顶层函数）。
///
/// 拆分自 `dzj_api_remote_datasource.dart`（2026-10-08 架构审计第三轮 · 第一阶段）：
/// 那个类原本 1311 行、66 个成员，但**只有一个实例字段 `_dio`** —— 于是所有
/// `static` 辅助（加密收发 / SQL 体拼装 / 响应解析 / 组件 id 常量）都能整块搬成
/// **顶端函数**，类里只留 `fetch*` 业务方法与 `Dio`。类**不改公开 API**、
/// 不加 wrapper，调用点只换了函数名前缀（口径见 AGENTS.md §33.4.4 ①）。
///
/// ⚠ 唯一带 `Dio` 参数的是 [dzjPostComponent]（它原来是实例方法，只用到 `_dio`）。
library;

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_crypto.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_peer.dart';

/// 个人数据中心组件接口通用异常（业务失败，非会话过期）。
class DzjApiException extends AppException {
  DzjApiException(super.message);
}

const String dzjReferer =
    'https://dzj.jxufe.edu.cn/app/66eef481a9a3/82e98baafb40';

// ---- 低层收发 ----

/// 发送加密组件请求，返回解密后的 JSON 值（Map / List / 标量）。
///
/// HTTP 非 200、success=false、或 data 解密失败时抛 [DzjApiException]。
/// 会话类问题由上层（仓库）统一判定并刷新重试。
Future<dynamic> dzjPostComponent(
  Dio dio,
  String path,
  Map<String, dynamic> body,
  DzjSession session,
) async {
  final cipher = DzjCrypto.encrypt(jsonEncode(body), session.fixedSalt);
  try {
    final response = await dio.post<dynamic>(
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
          'Referer': dzjReferer,
          'Cookie': dzjSessionCookieHeader(session),
        },
      ),
    );

    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw DzjSessionExpiredException();
    }
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
      // 会话失效**按类型抛**（见 [dzjIsSessionInvalid]）：[dzjGuard] 不吞它，
      // 仓库据此换会话后重来、界面据此给「重新登录」——而不是像从前那样
      // 被吞成 null，用户只看到「转了很久」。
      if (dzjIsSessionInvalid(errCode)) {
        throw DzjSessionExpiredException();
      }
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
  } on DzjSessionExpiredException {
    // 必须先于下面的兜底 catch：否则会被包成 DzjApiException，
    // 「会话失效」这个语义就丢了（[DzjSessionExpiredException] 不是
    // [DzjApiException] 的子类 —— 它走的是全仓统一的会话失效侧）。
    rethrow;
  } on DioException catch (e) {
    throw DzjApiException('网络错误：${e.message}');
  } catch (e) {
    throw DzjApiException('请求异常：$e');
  }
}

/// 响应是不是「会话失效」而不是「这一张卡没数据」。
///
/// 实测（2026-10-01 · 真机会话对照，会话换取时间距今 472 小时）：
/// 组件接口统一回 `success=false` + `errorCode=50002`。命中即
/// [DzjSessionExpiredException]。
///
/// ⚠ **只认错误码，不认文案**：`test/core_conventions_test.dart` 的
/// 「数据层 / core 不许拿文案当类型判失效」是源码守卫 —— 文案是服务端随时
/// 能改的东西，拿它当类型既脆、又会把「这张卡本来就没数据」误判成会话失效
/// （于是整页被拖去换会话重来）。判据要**窄**：只认实测到的那一个码，
/// 不认泛化的 5xxxx；真认不出来还有仓库那层「全都空 → 换会话重来一次」兜底。
bool dzjIsSessionInvalid(dynamic errorCode) =>
    errorCode?.toString() == '50002';

/// 把 [DzjSession] 里那两个具名 Cookie 拼成请求头。
///
/// ⚠ **刻意不用 `HostCookieJar`**（2026-09-20 架构审查）：dzj 的会话是**类型化**的
/// —— 它只认 `SESSION` / `fixedSalt` 两个名字，`fixedSalt` 还要拿去解密响应体，
/// 塞进「host → 名字 → 值」的通用桶反而丢掉类型与用途。见 §33.3 反例表。
String dzjSessionCookieHeader(DzjSession session) {
  final parts = <String>[];
  session.cookieHeader.forEach((k, v) => parts.add('$k=$v'));
  return parts.join('; ');
}

Map<String, dynamic> dzjSpendBody({
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

/// 组件 id（实测确认，见各方法注释）。
const String dzjCourseComponentId = 'u:94cf8d7765b0';

const String dzjSeatComponentId = 'u:9b48c5bf91ad';

const String dzjGrantComponentId = 'u:631a812c461d';

const String dzjWorkStudyComponentId = 'u:b54d6f93ff2e';

/// 行集总数：优先用响应里的 `total`，取不到时退回**已解析条数**。
int dzjTotalOf(dynamic data, int fallback) {
  if (data is Map) {
    final t = data['total'];
    if (t is num) return t.toInt();
    if (t is String) return int.tryParse(t) ?? fallback;
  }
  return fallback;
}

/// 计数 SQL 的别名候选（`select count(*) as zs/sj/sl/…`，别名没人管得住）。
const List<String> dzjCountKeys = [
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
List<DzjPeer>? dzjPeersOf(dynamic data, int limit) {
  final rows = <Map<String, dynamic>>[];
  if (data is Map && data['data'] is List) {
    for (final r in data['data'] as List) {
      if (r is Map) rows.add(r.map((k, v) => MapEntry(k.toString(), v)));
    }
  } else {
    final list = dzjRowsOf(data);
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

// ---- 解析辅助 ----

String dzjToday() {
  final now = DateTime.now();
  final mm = now.month.toString().padLeft(2, '0');
  final dd = now.day.toString().padLeft(2, '0');
  return '${now.year}-$mm-$dd';
}

Map<String, dynamic> dzjDataGet(String componentId, String sql) => {
  'sql': sql,
  'datasourceID': '1',
  'componentId': componentId,
  'appId': 140,
};

Map<String, dynamic> dzjIndexSqlBody({
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
double? dzjFirstNum(dynamic data, List<String> keys) {
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
List<Map<String, dynamic>>? dzjRowsOf(dynamic data) {
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
Map<String, int>? dzjChartRowsToMap(dynamic data) {
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
///
/// ⚠ **会话失效是唯一例外**：它必须冒出去。被吞成 null 的后果是 20 张卡
/// 全"空"，仓库只能靠「全都 null」的启发式猜会话没了 —— 实测那一路要多打
/// 一整轮请求（约 6.5 秒）才反应过来（见 [probeSession]）。
Future<T?> dzjGuard<T>(Future<T?> Function() fn) async {
  try {
    return await fn();
  } on DzjSessionExpiredException {
    rethrow;
  } catch (_) {
    return null;
  }
}
