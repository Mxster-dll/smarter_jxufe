/// 竹简数据中台 · 子页面与通用取数（extension）
///
/// 页面树 / 页面定义 / 数据块 / 通用对象行 / 基础信息 + 会话探针（7 个方法）。
///
/// 拆分自 `dzj_api_remote_datasource.dart`（2026-10-08 架构审计第三轮 · 第二阶段）：
/// 这类只有 `dio` 一个字段，所以整组方法**用 extension 搬走** —— 方法名一字不改、
/// 零 wrapper、调用点连 import 都不用动（本文件被 `dzj_api_remote_datasource.dart`
/// `export`，import 它就等于 import 这里）。口径见 AGENTS.md §33.4.4。
library;

import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_auth_remote_datasource.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_support.dart';
import 'package:smarter_jxufe/features/data_center/domain/dzj_basic_info.dart';
import 'package:smarter_jxufe/features/data_center/data/datasource/dzj_api_remote_datasource.dart';

extension DzjApiPages on DzjApiRemoteDataSource {

  // ---- 子页面（页面树 / 页面定义 / 通用取数） ----

  /// 应用**页面树**（十个子页面的唯一出处）。
  ///
  /// `POST /api/page/manageTreeByVersion`
  /// `{"url": "66eef481a9a3", "accessFlag": 1, "type": "web"}` → `{"tree": [...]}`。
  /// ⚠ 入参抄自学校前端（`js_umi` 的 `o6`）：**「应用唯一标识」字段名是 `url`**，
  /// appId/DzjApiRemoteDataSource.appUrl/appUniqueId/appCode 一律被判「应用唯一标识不能为空」；
  /// `accessFlag` 传数字 1 或字符串 `"1"` 都行；`type` = `web`（`mobile` 回包相同）。
  /// 用 **ByVersion** 而不是 `manageTree`：后者回的是**全量**（含「（研）」「备份」
  /// 「纠错管理」等未发布页，实测 25 个节点），前者只回当前发布版（11 个节点）。
  Future<Object?> fetchPageTree(DzjSession s) =>
      dzjPostComponent(dio, '/api/page/manageTreeByVersion', {
        'url': DzjApiRemoteDataSource.appUrl,
        'accessFlag': 1,
        'type': 'web',
      }, s);

  /// 任意子页面的**页面定义**（amis body），供通用渲染器解析。
  Future<Object?> fetchPageBody(DzjSession s, String pageKey) =>
      dzjPostComponent(dio, '/api/page/searchBodyByVersion', {
        'appId': 140,
        'accessFlag': '1',
        'pageKey': pageKey,
        'appUrl': DzjApiRemoteDataSource.appUrl,
      }, s);

  /// 单个组件的**聚合值**（`data/get`，`index: 0`）—— kpi / 文本类卡片。
  ///
  /// 空结果返回 null（不回空 Map，方便上层换端点兜底）。
  Future<Map<String, dynamic>?> fetchBlockValue(
    DzjSession s,
    String componentId, {
    int index = 0,
  }) => dzjPostComponent(dio, '/api/app/component/data/get', {
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
  }) => dzjPostComponent(
      dio,
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
    return dzjPostComponent(dio, '/api/app/component/data/dataList', {
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
  }) => dzjPostComponent(dio, '/api/app/component/tsa/getFormData',
              dzjBasicInfoRequest(), s)
          .then(
            (d) => d == null ? null : dzjBasicInfoFromJson(d, account: account),
          );

  /// **会话预检**：首屏那一大批请求之前，先用 1 个轻请求问一句「这会话还活着吗」。
  ///
  /// 为什么要有它（2026-10-01 实测）：dzj 的 SESSION 落在 Hive 里且**不看 TTL**
  /// （`dzj_auth_local_datasource.dart` 的 `getSession` 命中即用，`getUpdatedAt`
  /// 无人调用）。会话真过期时，首屏 20 并发 + 5 个身份文本**全部**返回
  /// `code=50002` → 仓库才刷新会话**再整批重打**：实测 6568ms（冷连接）对
  /// 537ms（同一批紧接着再跑）。预检把这次「白打」压成 1 个请求。
  ///
  /// 用 `manageTreeByVersion` 当探针：不带 SQL、不带 componentId（回包只有
  /// 页面树），实测死会话 22ms 回 50002、活会话 48-64ms 回正常树 ——
  /// 是全套端点里最便宜、且**本来就是真业务**（子页面清单卡要它）的那个。
  ///
  /// 返回值语义刻意保守：**只有确凿的会话失效才回 false**；网络抖动 / 超时等
  /// 一律回 true（当作"还活着"）—— 那种情况下批次自己会失败，再走老的
  /// 「全失败 → 换会话重来」那条路，不能因为一次抖动就白换一次会话。
  Future<bool> probeSession(DzjSession s) async {
    try {
      await dzjPostComponent(dio, '/api/page/manageTreeByVersion', {
        'url': DzjApiRemoteDataSource.appUrl,
        'accessFlag': 1,
        'type': 'web',
      }, s);
      return true;
    } on DzjSessionExpiredException {
      return false;
    } catch (_) {
      return true;
    }
  }
}
