/// 学生个人数据中心 —— **任意子页面的通用解析与承载**。
///
/// 那九个（原十个）子页面里的卡片全是「竹简」中台的 amis 组件，App 不逐个硬编码，
/// 而是拿服务端下发的**页面定义**（`POST /api/page/searchBodyByVersion`
/// `{appId: 140, accessFlag: '1', pageKey, appUrl}`）现解析出现成可渲染的「数据块」：
///
/// - **kpi**：`zj-card` / `customkpi-card-renderer` / `card-info-renderer` /
///   `kpi-group-renderer` / `my-consumption-render` / `dynamic-title-text-renderer` …
///   → `POST /api/app/component/data/get`（`{datasourceID:'1', appId:140, componentId, index:0}`）
///   回一行聚合，如 `{"cs": 15}`、`{"fs": 79.4}`、`{"username": "同学甲"}`。
/// - **list**：`common-table-renderer` 与各种图表（柱/折/面积/饼）
///   → `POST /api/app/component/data/list`（同参数，无 `index`）回**整表行数组**
///   （实测「任课教师情况」37 行、「学业成绩表格」6 行、消费面积图 12 行）。
///
/// ⚠ **两个端点与两种块是交叉兜底的**：分类只作尝试顺序的提示 —— 先按 `kind`
/// 试，空就换另一个端点（实测有些卡片两种都能回、有些只认一种）。
///
/// ⚠ **占位符组件必须整块丢掉**：学校有若干组件的 SQL 是 `select * from t_sys_user`
/// （门禁记录本周 / 最近轨迹 / 基本信息表单…），真调会回**整张系统用户表**
/// （含 password 密文）；`dzjIsPlaceholderSql` 负责识别，识别到就不出现在块列表里。
library;

import 'dart:convert';

/// 数据块类型（只决定**先试哪个端点**，不是硬约束）。
enum DzjBlockKind {
  /// 一行聚合值（数字 / 文本）。
  kpi,

  /// 多行明细表（表格或图表背后的行集）。
  list,
}

/// 一个可渲染的数据块 = 页面定义里的一个数据组件。
class DzjBlock {
  const DzjBlock({
    required this.id,
    required this.title,
    required this.kind,
    this.labels = const <String, String>{},
    this.slot = -1,
    this.dataObjectId = '',
    this.filterSql = '',
    this.fieldList = const <Map<String, Object?>>[],
  });

  /// 组件 id（`u:xxxxxxxxxxxx`）——取数就靠它。
  final String id;

  /// 卡片标题（节点自己的 `title`，取不到则沿用最近的祖先标题）。
  final String title;

  final DzjBlockKind kind;

  /// 数据列 → 中文列名（来自 `commonTableFieldSet` 的 `fieldColumnName`、
  /// `firstColumns1` 的 `{字段: 中文}`、或 `dataField`/`aliasName` + `fieldName` 组合）；
  /// 取不到就退回原始列名。
  final Map<String, String> labels;

  /// 组件内的**指标位**（`index`）：`>= 0` 表示这块是同一个组件的第几路数据
  /// （名单类组件 `data-xiangguan-render` 的 `timeList[i]` 就是这种：
  /// 同一组件下六个维度，靠 `index` 区分），取数要带 `index` 且走 `data/search`；
  /// `-1` = 普通单路组件（表格走 `data/list`、KPI 走 `data/get`）。
  final int slot;

  /// **数据对象**取数三件套（走 `/api/app/component/data/dataList`）：
  ///
  /// 学校页面上所有 `common-table-renderer` 表格的明细都只能从这条端点取到
  /// （2026-09-20 实证：`data/list` 对表格一律返回 `[]`，`data/search` 恒
  /// `{pageInfo:[],total:0}`）。三件套 = 数据对象 id + 行过滤 SQL + 字段清单。
  ///
  /// ⚠ 节点里还有个 `objectselect` 长得也像数据对象 id，**那是坏的**（实测一律
  /// `50000 系统异常`），必须用 `modelChoose.dataObjectId`。
  final String dataObjectId;

  /// 行过滤谓词（节点的 `querySql`，形如 `userid=#{U_用户名}`）。**必须带**：
  /// 服务端会把它解析成本人；留空会回传全校几万行（端点无行级权限兜底）。
  final String filterSql;

  /// 原样回传的字段清单（节点的 `commonTableFieldSet` / `allTableOption`）。
  final List<Map<String, Object?>> fieldList;

  /// 该列是否可用**数据对象**路线取明细。
  bool get hasDataObject =>
      dataObjectId.isNotEmpty && filterSql.isNotEmpty && fieldList.isNotEmpty;

  /// 该列的展示名。
  ///
  /// ⚠ **大小写无关**：数据对象端点（`data/dataList`）回的是**小写**数据库列名
  /// （`bsmc`），而页面定义里的列名常常是大写（`BSMC`）—— 不忽略大小写的话，明细行
  /// 会退化成「bsmc / 蓝桥杯…」这种原始列名（用户看到的就是这个）。
  String labelOf(String key) {
    final v = labels[key] ??
        labels[key.toLowerCase()] ??
        labels[key.toUpperCase()] ??
        _labelIgnoreCase(key);
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return key;
  }

  String? _labelIgnoreCase(String key) {
    final lower = key.toLowerCase();
    for (final e in labels.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }

  /// 该列是否为**页面声明过**的列（用于把数据对象端点多回的审计列挡掉）。
  bool declares(String key) {
    if (labels.isEmpty) return true;
    return labelOf(key) != key;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'kind': kind.name,
    'labels': labels,
    'slot': slot,
  };
}

/// 单个块取到的**数据**（kpi 只有 fields，list 只有 rows）。
class DzjBlockData {
  const DzjBlockData({
    required this.block,
    this.fields = const <MapEntry<String, String>>[],
    this.rows = const <List<MapEntry<String, String>>>[],
    this.failed = false,
  });

  final DzjBlock block;

  /// kpi：标签 → 值（单字段时标签就是卡片标题）。
  final List<MapEntry<String, String>> fields;

  /// list：每行的 标签 → 值（列名已翻成中文）。
  final List<List<MapEntry<String, String>>> rows;

  /// 该块没取到数据（空表 / 请求失败）——界面画「暂无数据」而不是假装有值。
  final bool failed;

  bool get isEmpty => fields.isEmpty && rows.isEmpty;
}

/// 一个子页面的**完整可渲染数据**（页面定义已解析 + 每块数据已取回）。
class DzjSubPageData {
  const DzjSubPageData({
    required this.pageKey,
    required this.title,
    required this.blocks,
    this.skipped = 0,
    this.truncated = 0,
  });

  final String pageKey;

  /// 页面标题（来自页面树，比页面定义里可靠）。
  final String title;

  final List<DzjBlockData> blocks;

  /// 跳过的纯排版 / 占位符组件数。
  final int skipped;

  /// 超出上限没渲染的块数。
  final int truncated;

  /// 有数据的块（空块不占版面）。
  List<DzjBlockData> get shown =>
      blocks.where((b) => !b.isEmpty).toList(growable: false);

  int get valueCount => shown.where((b) => b.fields.isNotEmpty).length;

  int get tableCount => shown.where((b) => b.rows.isNotEmpty).length;

  bool get isEmpty => shown.isEmpty;
}

/// 一个子页面的页面定义解析结果。
class DzjPageBody {
  const DzjPageBody({
    required this.pageKey,
    required this.blocks,
    this.skipped = 0,
    this.truncated = 0,
  });

  final String pageKey;
  final List<DzjBlock> blocks;

  /// 被跳过的组件数（纯排版件 + 占位符组件）。
  final int skipped;

  /// 因为超出上限而没进列表的块数（界面给一句说明，不假装「就这些」）。
  final int truncated;

  bool get isEmpty => blocks.isEmpty;

  /// 一页最多渲染多少个数据块（页面组件动辄上百，全拉等于一次开一百个请求）。
  ///
  /// 用户 2026-09-20 七轮：「你很多页面就只显示几个数据项……而且每个页面都要大量的内容
  /// 没有做」—— 实测上限 24 会把**后面**的数据块整片砍掉（学业信息页正好卡在 24，
  /// 而该页真有 13 个节点有数据；被砍掉的正是靠后的选课表 / 成绩表 / 排名卡）。
  /// 现在放到 60：九个内容页里候选最多的一页是 54 个（校内活动），48 时仍会漏掉学业信息
  /// 第 49 个候选（一张 6 行成绩表），60 之后九页的候选**一个不落**。真正被丢掉的条数
  /// 如实记进 [DzjPageBody.truncated]，界面给一句「另有 N 个模块未展开」。
  static const int maxBlocks = 60;

  /// 纯排版 / 无数据的组件类型 —— 不取数、不渲染。
  static const Set<String> layoutLabels = <String>{
    'page',
    'grid',
    'container',
    'custom-tabs',
    'anchor-title-renderer',
    'custom-title-text-renderer',
    'background-img-renderer',
    'error-descript-renderer',
    'form-assembly-renderer',
    'custom-swiper-renderer',
    'iframerender',
    'text',
    'button',
    'image',
  };

  /// 解析页面定义。认不出（非 Map / 无 body）就回空页面。
  static DzjPageBody parse(String pageKey, Object? raw) {
    if (raw is! Map) {
      return DzjPageBody(pageKey: pageKey, blocks: const <DzjBlock>[]);
    }
    final found = <DzjBlock>[];
    final seen = <String>{};
    var skipped = 0;
    var dropped = 0;

    void walk(Object? node, String title) {
      if (node is List) {
        for (final v in node) {
          walk(v, title);
        }
        return;
      }
      if (node is! Map) return;

      final ownTitle = node['title']?.toString().trim() ?? '';
      final ctx = ownTitle.isNotEmpty ? ownTitle : title;
      final id = node['id']?.toString() ?? '';
      final label = (node['label'] ?? node['name'] ?? '').toString();

      if (id.startsWith('u:')) {
        if (layoutLabels.contains(label)) {
          skipped++;
        } else if (dzjNodeHasPlaceholderSql(node)) {
          // 学校自己的坏组件：真调会回整张系统用户表 —— 一律不渲染。
          skipped++;
        } else {
          // ① 名单类渲染件（`data-xiangguan-render`）：一个 `timeList` = 多路数据，
          //    每路一个块（`slot` = `timeList` 下标），标题用 `cardTitle`。
          final timeList = node['timeList'];
          if (timeList is List && timeList.isNotEmpty) {
            for (final (i, entry) in timeList.indexed) {
              if (entry is! Map) continue;
              final cardTitle = entry['cardTitle']?.toString().trim() ?? '';
              if (cardTitle.isEmpty) continue;
              final blockId = '$id#$i';
              if (!seen.add(blockId)) continue;
              if (found.length >= maxBlocks) {
                dropped++;
                continue;
              }
              found.add(
                DzjBlock(
                  id: id,
                  title: cardTitle,
                  kind: DzjBlockKind.list,
                  labels: dzjColumnLabels(entry),
                  slot: i,
                ),
              );
            }
          } else if ((dzjNodeHasData(node) || dzjLabelCarriesData(label)) &&
              seen.add(id)) {
            if (found.length < maxBlocks) {
              final obj = dzjDataObjectOf(node);
              found.add(
                DzjBlock(
                  id: id,
                  title: ctx,
                  kind: dzjBlockKindOf(node, label),
                  labels: dzjColumnLabels(node),
                  dataObjectId: obj.objectId,
                  filterSql: obj.filterSql,
                  fieldList: obj.fields,
                ),
              );
            } else {
              dropped++;
            }
          }
        }
      }

      for (final v in node.values) {
        walk(v, ctx);
      }
    }

    walk(raw['body'], '');
    return DzjPageBody(
      pageKey: pageKey,
      blocks: found,
      skipped: skipped,
      truncated: dropped,
    );
  }
}

/// 组件类型名本身是否**意味着带数据**（`zj-card` / `common-table-renderer` /
/// `m-rank-renderer` / `dvecustom-universalringchart-renderer` …）。
///
/// 用户 2026-09-20 七轮：实测有一批组件**自身字段里没有任何 SQL / 列配置**（取数口径
/// 全存在服务端的组件定义里），只按「字段里有没有 SQL」筛会整块漏掉 —— 学业信息页的
/// 排名卡 `m-rank-renderer`、学分卡 `stuCredits-renderer` 就是这样丢的。这里按类型名
/// 兜一层；纯排版件（[DzjPageBody.layoutLabels]）先被排除。
bool dzjLabelCarriesData(String label) {
  final l = label.toLowerCase().trim();
  if (l.isEmpty) return false;
  if (DzjPageBody.layoutLabels.contains(label)) return false;
  if (l.startsWith('dve')) return true;
  return l.contains('render') ||
      l.contains('card') ||
      l.contains('table') ||
      l.contains('chart') ||
      l.contains('kpi');
}

/// 该节点的**自身**字段里是否带取数配置（只在第一层看字符串与列表，避免把子节点的
/// SQL 误算成自己的）。
bool dzjNodeHasData(Map<dynamic, dynamic> node) {
  const keys = <String>{
    'selectArea',
    'tabeSelectArea',
    'selectArea1',
    'dataSql',
    'querySql',
    'querySqlText',
    'columns',
    'commonTableFieldSet',
    'allTableOption',
    'allEchartData',
    'yAxisInfoList',
    // 数据对象 / 分析模型路线（表格与图表都可能是这条）：组件自带 SQL 为空，取数口径
    // 存在服务端定义里 —— 从前这些键不算「有数据」，整块被漏掉。
    'modelChoose',
    'dimensionChoose',
    'indicatorChoose',
    'sqlFilter',
    'dataSourceRadios',
    'showDetailTable',
    'tableColumns',
  };
  for (final k in keys) {
    final v = node[k];
    if (v is String && v.trim().isNotEmpty) return true;
    if (v is List && v.isNotEmpty) return true;
    if (v is Map && v.isNotEmpty) return true;
  }
  return false;
}

/// 表格 / 图表节点上的**数据对象**取数三件套（`data/dataList` 端点要的就是它们）。
///
/// 用户 2026-09-20 八轮：「还是看不到详细参加了哪些竞赛，这些竞赛的分级、时间」——
/// 学科竞赛明细表 `u:f85c95577ecf` 的 15 条记录只能从这条端点取到：
///
/// ```text
/// POST /api/app/component/data/dataList
/// {dataObjectId, datasourceID:'1', dbType:'postgresql', schemaName:'usr_bsp',
///  fieldList:[…], filterConfig:[], dataFilterSql:'userid=#{U_用户名}',
///  componentId, appId:140}  →  行数组（列名是**小写**的数据库列名）
/// ```
///
/// 为什么 App 里那张表一直是空的：节点里有两个都像「数据对象 id」的字段 ——
/// `modelChoose.dataObjectId = 1215f9f0…`（对）与 `objectselect = 9000000026…`（错，
/// 一律 500 系统异常），前端把失败当空结果。本页 8 张表格全带这个坏 `objectselect`，
/// 所以「校内活动」整页的明细都打空了。
({String objectId, String filterSql, List<Map<String, Object?>> fields})
dzjDataObjectOf(Map<dynamic, dynamic> node) {
  var objectId = '';
  final mc = node['modelChoose'];
  if (mc is Map) objectId = '${mc['dataObjectId'] ?? ''}'.trim();
  if (objectId.isEmpty) objectId = '${node['dataObjectId'] ?? ''}'.trim();
  // `modelChoose.model_json` 是个 **JSON 字符串**，里面的 `tableId` 同样是数据对象 id
  // —— 奖助贷勤 / 学业信息那一批表格只在这里挂 id（`dataObjectId` 键根本没有）。
  if (objectId.isEmpty && mc is Map) {
    final mj = mc['model_json'];
    if (mj is String && mj.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(mj);
        if (parsed is List) {
          for (final e in parsed) {
            if (e is Map) {
              final t = '${e['tableId'] ?? ''}'.trim();
              if (t.isNotEmpty) {
                objectId = t;
                break;
              }
            }
          }
        }
      } catch (_) {
        // 脏/截断的 model_json 直接当没有，别让整页解析挂掉。
      }
    }
  }

  var filterSql = '';
  for (final k in const <String>['querySql', 'querySqlText', 'dataFilterSql']) {
    final v = node[k];
    if (v is String && v.trim().isNotEmpty) {
      filterSql = v.trim();
      break;
    }
  }
  final fields = <Map<String, Object?>>[];
  for (final k in const <String>['commonTableFieldSet', 'allTableOption']) {
    final list = node[k];
    if (list is! List) continue;
    for (final e in list) {
      if (e is! Map) continue;
      final dataField = '${e['dataField'] ?? ''}'.trim();
      if (dataField.isEmpty) continue;
      fields.add(<String, Object?>{
        'dataField': dataField,
        if (e['dataFieldId'] != null) 'dataFieldId': '${e['dataFieldId']}',
        if (e['fieldName'] != null) 'fieldName': '${e['fieldName']}',
        if (e['fieldType'] != null) 'fieldType': '${e['fieldType']}',
        if (e['isCode'] != null) 'isCode': e['isCode'],
        if (e['isKey'] != null) 'isKey': e['isKey'],
        if (e['isNullAble'] != null) 'isNullAble': e['isNullAble'],
      });
    }
    if (fields.isNotEmpty) break;
  }
  if (dzjIsPlaceholderSql(filterSql)) {
    return (objectId: '', filterSql: '', fields: const <Map<String, Object?>>[]);
  }
  return (objectId: objectId, filterSql: filterSql, fields: fields);
}

/// 该节点是否**绑着占位符 SQL**（`select * from t_sys_user` 之类）。
bool dzjNodeHasPlaceholderSql(Map<dynamic, dynamic> node) {
  var hit = false;
  void scan(Object? v, int depth) {
    if (hit || depth > 3) return;
    if (v is String) {
      if (dzjIsPlaceholderSql(v)) hit = true;
      return;
    }
    if (v is List) {
      for (final x in v) {
        scan(x, depth + 1);
      }
      return;
    }
    if (v is Map) {
      for (final x in v.values) {
        scan(x, depth + 1);
      }
    }
  }

  for (final k in const ['selectArea', 'tabeSelectArea', 'selectArea1', 'dataSql',
    'querySql', 'querySqlText']) {
    scan(node[k], 0);
  }
  return hit;
}

/// 占位符 SQL 判定：学校若干组件的 SQL 没写完，直接是 `select * from t_sys_user`。
bool dzjIsPlaceholderSql(String sql) {
  final s = sql.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return false;
  return s.contains('t_sys_user') ||
      s.endsWith('select * from') ||
      s == 'select';
}

/// 端点倾向：表格 / 图表先试 `data/list`，其余先试 `data/get`（两边都会兜底）。
DzjBlockKind dzjBlockKindOf(Map<dynamic, dynamic> node, String label) {
  final lower = label.toLowerCase();
  if (lower.contains('table') || lower.contains('chart')) return DzjBlockKind.list;
  final fset = node['commonTableFieldSet'] ?? node['allTableOption'];
  if (fset is List && fset.isNotEmpty) return DzjBlockKind.list;
  if (lower.contains('kpi') || lower.contains('card')) return DzjBlockKind.kpi;
  return DzjBlockKind.kpi;
}

/// 从节点的字段配置里抽出「数据列 → 中文列名」。
Map<String, String> dzjColumnLabels(Map<dynamic, dynamic> node) {
  final out = <String, String>{};

  /// `showData: false` 的列名（小写）—— 散落在**多个**配置键里（`commonTableFieldSet`
  /// 带这个标志、`allTableOption` / `tableColumns` 不带），所以先全收一遍，最后统一剔除：
  /// 否则「校内活动」那张表会从别的键里把 姓名 / 主键 / 一卡通号 重新捞回来，
  /// 明细行里就会多出三列用户不要的东西。
  final hidden = <String>{};

  void scan(Object? v, int depth) {
    if (depth > 4) return;
    if (v is List) {
      for (final x in v) {
        scan(x, depth + 1);
      }
      return;
    }
    if (v is! Map) return;
    final field = v['fieldName']?.toString().trim() ?? '';
    final alias = (v['dataField'] ?? v['alias'] ?? v['aliasName'] ?? '')
        .toString()
        .trim();
    // 中文列名的候选按可靠性排：`fieldColumnName` → `fieldName` → `aliasName` →
    // `fieldLabel`。⚠ **`fieldName` 常常直接就是中文列名**（表格字段清单里就是
    // `{"dataField":"BSMC","fieldName":"比赛名称"}`）—— 从前只认 `fieldColumnName`，
    // 于是「校内活动 › 学科竞赛」那张表的列名全是英文原样（bsmc / hdsj），用户要的
    // 「分级、时间」列名也就出不来。取**第一个含中文**的候选。
    var zh = '';
    for (final cand in <Object?>[
      v['fieldColumnName'],
      v['fieldName'],
      v['aliasName'],
      v['fieldLabel'],
    ]) {
      final t = cand?.toString().trim() ?? '';
      if (t.isNotEmpty && dzjHasCjk(t)) {
        zh = t;
        break;
      }
    }
    // `showData: false` = 这张表**不显示**这一列 —— wid / 主键 / 姓名 / 一卡通号 /
    // dke_op_* / clrq / czlx 这些平台审计列全是 false。不给它中文名，
    // `DzjBlock.declares` 就会在渲染时把整列挡掉（否则明细行里会多出一堆 dke_op_ts）。
    if (v['showData'] == false) {
      for (final k in <String>[field, alias]) {
        if (k.isNotEmpty) hidden.add(k.toLowerCase());
      }
    } else {
      for (final key in <String>[field, alias]) {
        if (key.isEmpty) continue;
        if (zh.isNotEmpty) out.putIfAbsent(key, () => zh);
      }
    }
    for (final x in v.values) {
      scan(x, depth + 1);
    }
  }

  for (final k in const ['commonTableFieldSet', 'allTableOption', 'columns',
    'tableColumns', 'firstColumns', 'firstColumns1', 'allEchartData']) {
    scan(node[k], 0);
  }
  // `firstColumns1` / `firstColumns` 是**扁平的** `{字段: 中文}` 映射
  // （如 `{"sex":"性别","username":"姓名","userid":"校园卡号","dept":"所属学院"}`），
  // 上面那套按 `fieldName`/`dataField` 找的规则认不出它，单独收一遍。
  for (final k in const ['firstColumns1', 'firstColumns']) {
    final v = node[k];
    if (v is Map) {
      for (final e in v.entries) {
        final zh = e.value?.toString().trim() ?? '';
        if (zh.isNotEmpty && dzjHasCjk(zh)) {
          out.putIfAbsent(e.key.toString(), () => zh);
        }
      }
    }
  }
  if (hidden.isNotEmpty) {
    out.removeWhere((k, _) => hidden.contains(k.toLowerCase()));
  }
  return out;
}

/// 是否含中日韩字符（用来判断某个配置项是不是「中文列名」）。
bool dzjHasCjk(String s) => RegExp(r'[\u4e00-\u9fa5]').hasMatch(s);

/// 值 → 展示文本（数字去掉多余的 `.0`，null/空 → 空串）。
String dzjValueText(Object? v) {
  if (v == null) return '';
  if (v is num) {
    if (v is int) return '$v';
    final d = v.toDouble();
    if (d.isNaN) return '';
    if (d == d.roundToDouble() && d.abs() < 1e15) return '${d.round()}';
    return d.toString();
  }
  if (v is bool) return v ? '是' : '否';
  final s = v.toString().trim();
  return s == 'null' ? '' : s;
}

/// 聚合结果 → 展示字段（**密码类键一律丢弃**，见 [dzjIsSensitiveKey]）。
List<MapEntry<String, String>> dzjFieldsOf(Object? data, {String title = ''}) {
  if (data is! Map) return const <MapEntry<String, String>>[];
  final out = <MapEntry<String, String>>[];
  for (final e in data.entries) {
    final key = e.key.toString();
    if (dzjIsSensitiveKey(key)) continue;
    final value = dzjValueText(e.value);
    if (value.isEmpty) continue;
    final zh = dzjHasCjk(key) ? key : '';
    out.add(
      MapEntry(
        zh.isNotEmpty
            ? zh
            : (out.isEmpty && title.isNotEmpty ? title : key),
        value,
      ),
    );
  }
  return out;
}

/// 敏感列名（占位符组件回来时可能夹带系统用户表的字段）。
bool dzjIsSensitiveKey(String key) {
  final k = key.toLowerCase();
  return k.contains('password') ||
      k.contains('passwd') ||
      k.contains('secret') ||
      k.contains('salt') ||
      k == 'pwd';
}

/// 行集 → 展示行（列名翻中文、空行丢弃）。
List<List<MapEntry<String, String>>> dzjRowsOf(
  Object? data,
  DzjBlock block, {
  int limit = 60,
}) {
  final raw = switch (data) {
    List() => data,
    Map() => switch (data['pageInfo'] ?? data['list'] ?? data['rows']) {
      List() => (data['pageInfo'] ?? data['list'] ?? data['rows']) as List,
      _ => const <Object?>[],
    },
    _ => const <Object?>[],
  };
  final rows = <List<MapEntry<String, String>>>[];
  for (final r in raw) {
    if (r is! Map) continue;
    final cells = <MapEntry<String, String>>[];
    for (final e in r.entries) {
      final key = e.key.toString();
      if (dzjIsSensitiveKey(key)) continue;
      // 数据对象端点会**顺带回审计列**（`dke_op_id` / `dke_op_ts` / `dke_op_type` /
      // `czlx` / `clrq`）以及行 id `wid`，页面定义里根本没声明它们 —— 一律挡掉，
      // 只留这张表自己要显示的列。
      if (key.toLowerCase() == 'wid') continue;
      if (!block.declares(key)) continue;
      final value = dzjValueText(e.value);
      if (value.isEmpty) continue;
      cells.add(MapEntry(block.labelOf(key), value));
    }
    if (cells.isEmpty) continue;
    rows.add(cells);
    if (rows.length >= limit) break;
  }
  return rows;
}
