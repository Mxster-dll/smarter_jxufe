/// 竹简「基本信息」子页面（pageKey `13ba9ece95a8`）的表单数据。
///
/// **这一页在 App 里不单独做子页面**（用户 2026-09-20 裁定：基本信息并入「我的」页），
/// 但它是「我的」页最权威的一份字段源：学工系统登记在册的 39 项，其中相当一部分
/// 本地学籍缓存里没有 —— 家庭住址、证件类型/号码、所属校区、学生身份/类型、
/// 通知书号、录取批次/时间/成绩/志愿、预计毕业日期、毕业中学、当前状态、学籍状态、
/// 宿舍地址（用户八轮：「基本信息页有大量的信息没有并入「我的」页」）。
///
/// 取数口径（2026-09-20 用 CDP 抓浏览器真实请求确定，`%TEMP%\dzjprobe\cdp.py`）：
///
/// ```text
/// POST /api/app/component/tsa/getFormData
/// {dataObjectId:'fd7fac78acd54660b7405fb515a0fc96', datasourceID:'1',
///  dbType:'postgresql', schemaName:'usr_bsp', componentId:'u:73ab7f26af38',
///  filterConfig:[], sortConfig:[],
///  fieldList:[{dataFieldId, dataField, fieldName} …39 项…]}
/// → {"data":[{"fieldName":"姓名","value":"同学甲","key":"USERNAME"}, …]}
/// ```
///
/// ⚠ 该组件在页面定义里的 `selectArea` 是占位符 `select * from t_sys_user`，
/// `data/search` / `data/list` / `data/get` 全都取不到 —— 表单数据**只能**走这个端点。
/// ⚠ 回包里多一项 `wid`（表单实例 id），不是学生字段，解析时丢掉。
library;

/// 一项表单字段：中文列名 ↔ 数据库列名 ↔ 字段 id（三者都要回传给服务端）。
class DzjBasicField {
  const DzjBasicField(this.label, this.dataField, this.dataFieldId);

  /// 中文列名（界面直接用它当行标题）。
  final String label;

  /// 数据库列名（`USERID` / `SJHM` …）。
  final String dataField;

  /// 字段 id（服务端按它拼 select 列表）。
  final String dataFieldId;

  Map<String, Object?> toJson() => <String, Object?>{
    'dataFieldId': dataFieldId,
    'dataField': dataField,
    'fieldName': label,
  };
}

const String dzjBasicInfoComponentId = 'u:73ab7f26af38';
const String dzjBasicInfoPageKey = '13ba9ece95a8';
const String dzjBasicInfoDataObjectId = 'fd7fac78acd54660b7405fb515a0fc96';

/// 数据来源标注（页面右上角写的就是「数据来源：学工系统」）。
const String dzjBasicInfoSource = '学工系统';

/// 表单项 → 界面归属卡片的建议（「我的」页把它们并进既有卡片，不新开卡片）。
///
/// 键 = 卡片名（与 `student_info_screen.dart` 的既有卡片一致）。
const List<DzjBasicField> dzjBasicFields = <DzjBasicField>[
  DzjBasicField('一卡通号', 'USERID', '365866254930058'),
  DzjBasicField('学号', 'XH', '5340394436587843'),
  DzjBasicField('姓名', 'USERNAME', '744381245249965'),
  DzjBasicField('性别', 'XB', '594679173032965'),
  DzjBasicField('出生日期', 'CSRQ', '4672305779547834'),
  DzjBasicField('民族', 'MZ', '2142417829824126'),
  DzjBasicField('政治面貌', 'ZZMM', '9082990932476314'),
  DzjBasicField('籍贯', 'JG', '13724827289147612'),
  DzjBasicField('家庭住址', 'JTZZ', '732766125004094'),
  DzjBasicField('证件类型', 'ZJLX', '6106412729856316'),
  DzjBasicField('证件号码', 'ZJHM', '8726963982996594'),
  DzjBasicField('所属校区', 'SSXQ', '18378737608963291'),
  DzjBasicField('所属单位', 'SSDW', '257637118913582'),
  DzjBasicField('所属专业', 'SSZY', '8586732066932257'),
  DzjBasicField('所属班级', 'SSBJ', '8719664562057226'),
  DzjBasicField('所在年级', 'SZNJ', '7428250842338713'),
  DzjBasicField('学制', 'XZ', '6094495883364921'),
  DzjBasicField('培养层次', 'PYCC', '1598521286563681'),
  DzjBasicField('学生身份', 'XSSF', '9982441723150508'),
  DzjBasicField('学生类型', 'XSLX', '6291974744535977'),
  DzjBasicField('是否预科生', 'SFYKS', '1665293232832461'),
  DzjBasicField('手机号码', 'SJHM', '9500813903416088'),
  DzjBasicField('电子邮箱', 'DZYX', '7934368646624357'),
  DzjBasicField('银行账号', 'YHZH', '6690483441565576'),
  DzjBasicField('考生号', 'KSH', '7355473249055429'),
  DzjBasicField('考生类别', 'KSLB', '8996444487840591'),
  DzjBasicField('通知书号', 'TZSH', '552478605943346'),
  DzjBasicField('录取批次', 'LQPC', '5957373866299775'),
  DzjBasicField('录取时间', 'LQSJ', '3639564355144138'),
  DzjBasicField('录取成绩', 'LQCJ', '4697507360346833'),
  DzjBasicField('录取志愿', 'LQZHIY', '5456933816197917'),
  DzjBasicField('录取专业', 'LQZY', '5685862822883294'),
  DzjBasicField('预计毕业日期', 'YJBYRQ', '42446507237044173'),
  DzjBasicField('毕业中学', 'BYZX', '9431396947538673'),
  DzjBasicField('担任职务', 'DRZW', '5274722985644438'),
  DzjBasicField('获得奖励', 'HDJL', '1815868343947713'),
  DzjBasicField('当前状态', 'DQZT', '8563492146144291'),
  DzjBasicField('学籍状态', 'XJZT', '901243065781955'),
  DzjBasicField('宿舍地址', 'SSDZ', '5545060648699227'),
];

/// `tsa/getFormData` 的请求体（与浏览器抓到的形状一致）。
///
/// ⚠ **`filterConfig` 才是「查谁」的开关**（2026-09-20 八轮实测，`formdata4/5.py`）：
/// 同一条会话、同一个 `fieldList`，只要 `filterConfig` 为空或不带用户谓词，服务端就会
/// 回**任意一个学生**（实测回的是留学生 留学生甲 / 2202400001）；带上
/// `filterType:'sql'` + `values:['userid=#{U_用户名}']` 才稳定回本人。
/// ⚠ 因此 `fieldList[i].filter`、`dataFilterSql` 都**不管用**（试过，照旧串号）。
Map<String, Object?> dzjBasicInfoRequest() => <String, Object?>{
  'dataObjectId': dzjBasicInfoDataObjectId,
  'datasourceID': '1',
  'dbType': 'postgresql',
  'schemaName': 'usr_bsp',
  'componentId': dzjBasicInfoComponentId,
  'filterConfig': <Object?>[
    <String, Object?>{
      'columnName': '',
      'filterType': 'sql',
      'tableName': '',
      'type': 'VARCHAR2',
      'values': <Object?>['userid=#{U_用户名}'],
    },
  ],
  'sortConfig': <Object?>[],
  'fieldList': <Object?>[for (final f in dzjBasicFields) f.toJson()],
};

/// 解析回包 → `{中文列名: 值}`。
///
/// 脏数据一律容错：非 Map / 无 fieldName 的行丢掉；`value` 为 null 或空白丢掉；
/// `wid`（表单实例 id）丢掉；值统一 trim。
/// 只保留 [dzjBasicFields] 里登记过的列名（服务端若多回字段也不会污染界面）。
///
/// ⚠ **串号防线**：`account` 非空时校验回包里的「一卡通号」——不一致就整份丢弃。
/// 这个端点在 `filterConfig` 缺失时会回别的学生的整份基本信息（见 [dzjBasicInfoRequest]
/// 的实测记录），宁可什么都不显示，也不能把别人的姓名/证件号/家庭住址画到用户的「我的」页。
Map<String, String> dzjBasicInfoFromJson(Object? raw, {String account = ''}) {
  final src = switch (raw) {
    Map() => raw['data'] ?? raw,
    _ => null,
  };
  if (src is! List) return const <String, String>{};
  final known = <String>{for (final f in dzjBasicFields) f.label};
  final out = <String, String>{};
  for (final e in src) {
    if (e is! Map) continue;
    final label = '${e['fieldName'] ?? ''}'.trim();
    if (label.isEmpty || !known.contains(label)) continue;
    final v = '${e['value'] ?? ''}'.trim();
    if (v.isEmpty || v == 'null') continue;
    out[label] = v;
  }
  final me = account.trim();
  final card = out['一卡通号'] ?? '';
  if (me.isNotEmpty && card.isNotEmpty && card != me) {
    return const <String, String>{};
  }
  return out;
}
