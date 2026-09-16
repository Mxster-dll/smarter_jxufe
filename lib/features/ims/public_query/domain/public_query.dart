/// 公共查询（教务「公共查询」SB 菜单）的领域模型与纯函数。
///
/// 全部语义来自**实测**（2026-09-14，见 `reverse_engineering/公共查询接口.md`），
/// 尤其是下面这些「照直觉写必错」的点：
///
/// 1. **报告端点 `POST /kbbp/dykb.GS1.jsp?kblx=<kckb|jskb|bjkb|jsikb>` 是普通 JSP**，
///    只认 `application/x-www-form-urlencoded`；用 multipart（dio `FormData`）发，
///    `request.getParameter()` 一个都拿不到 → 报告恒返回「没有检索到记录！」。
/// 2. **学年学期码是逗号形式** `2026,0`（来源 `Ms_KBBP_FBXQLLJXAP`），
///    不是 `StMsXnxqDxDesc` 的 `2026-0`（后者只在 `menucode=="S"` 的老分支里用）。
/// 3. `hidFlag` 必须为空，**教师课表例外**（`ggcxjskb`）；`smxbjkb/smxjskb` 是
///    三门峡职业技术学院（`G_SCHOOL_CODE=="10842"`）专属，照抄会恒空。
/// 4. 表单里的 `menucode` 被页面 JS `substring(0,1)` 截成 **`S`**，不是 `SB03`。
/// 5. `pkts`（排课套数）必须先问 `KB_ExpTeacherSchedualAction.do?hidOption=getpkts`
///    拿到（江财当前 = `7`），留空也查不到。
library;

import 'dart:convert';

/// 公共查询功能类别（对应菜单码 SB01/SB02/SB03/SB04）。
enum PublicQueryKind {
  /// 课程课表（SB01）
  course('SB01', '课程课表', 'kckb', ''),

  /// 教师课表（SB02）
  teacher('SB02', '教师课表', 'jskb', 'ggcxjskb'),

  /// 班级课表（SB03）
  klass('SB03', '班级课表', 'bjkb', ''),

  /// 教室课表（SB04）
  classroom('SB04', '教室课表', 'jsikb', '');

  const PublicQueryKind(
    this.menuCode,
    this.title,
    this.reportType,
    this.hidFlag,
  );

  /// 教务菜单码（页面 URL 用；表单里只发首字母 `S`）。
  final String menuCode;

  /// 界面标题。
  final String title;

  /// 数据端点 `dykb.GS1.jsp?kblx=<reportType>` 的类型值。
  final String reportType;

  /// 表单 `hidFlag`（江财：仅教师课表非空）。
  final String hidFlag;

  /// 登录版页面路径。
  String get pagePath => '/kbbp/dykb.$reportType.html?menucode=$menuCode';

  /// 选择器（`/taglib/CombBoxServlet.jsp`）的 `className`。
  String get comboClassName => switch (this) {
    PublicQueryKind.course => 'jw_comb_coursename',
    PublicQueryKind.teacher => 'jbxx_EmployeeAndTeacher',
    PublicQueryKind.klass => 'kbbp_dykb_SpecialClassComb',
    PublicQueryKind.classroom => 'jxap_combbox_js',
  };

  /// 结果列表里「对象」的称呼（用于标题与对照列表）。
  String get ownerLabel => switch (this) {
    PublicQueryKind.course => '课程',
    PublicQueryKind.teacher => '教师',
    PublicQueryKind.klass => '班级',
    PublicQueryKind.classroom => '教室',
  };

  /// 分段按钮用的短标签（4 个一起放时「课程课表」会被裁剪）。
  String get shortTitle => ownerLabel;

  /// 按菜单码或报表类型定位类别（`SB03` / `bjkb` 都能认）；未知返回 null。
  static PublicQueryKind? kindOfMenu(String code) {
    final key = code.trim().toUpperCase();
    if (key.isEmpty) return null;
    for (final k in values) {
      if (k.menuCode.toUpperCase() == key ||
          k.reportType.toUpperCase() == key) {
        return k;
      }
    }
    return null;
  }
}

/// 一个选项（下拉 JSON 的 `{"code","name"}` 或选择器 XML 的 `value/name`）。
class PublicQueryOption {
  final String code;
  final String name;

  const PublicQueryOption({required this.code, required this.name});

  /// 名称里常带 `[2612020C11]` / `[007]` 这类前缀码，界面显示时剥掉。
  String get displayName =>
      name.replaceFirst(RegExp(r'^\[[^\]]*\]'), '').trim();

  /// 名称里方括号内的代码（如 `[2612020C11]会计学261` → `2612020C11`）。
  String get bracketCode =>
      RegExp(r'^\[([^\]]*)\]').firstMatch(name)?.group(1)?.trim() ?? '';

  @override
  String toString() => 'PublicQueryOption($code, $name)';
}

/// 学年学期（公共查询用的是**逗号**码，如 `2026,0`）。
class PublicQueryTerm {
  /// 学年，如 2026。
  final int xn;

  /// 学期码，0=第一学期 / 1=第二学期 / 2=第二学段。
  final int xqM;

  /// 教务给的显示名，如 `2026-2027学年第一学期`。
  final String name;

  const PublicQueryTerm({
    required this.xn,
    required this.xqM,
    required this.name,
  });

  /// 表单值 `xnxq`（**逗号**），如 `2026,0`。
  String get code => '$xn,$xqM';

  /// 便于与「当下学期」口径（`school_term.dart` 的 `(xn, xq)`）比较。
  bool matches(int otherXn, int otherXq) => xn == otherXn && xqM == otherXq;

  @override
  String toString() => 'PublicQueryTerm($code, $name)';
}

/// 解析学期码：逗号（`2026,0`）与连字符（`2026-0`）都吃；非法返回 null。
({int xn, int xqM})? parseTermCode(String code) {
  final parts = code.trim().split(RegExp(r'[,\-]'));
  if (parts.length != 2) return null;
  final xn = int.tryParse(parts[0]);
  final xqM = int.tryParse(parts[1]);
  if (xn == null || xqM == null) return null;
  if (xn < 2000 || xn > 2100 || xqM < 0 || xqM > 9) return null;
  return (xn: xn, xqM: xqM);
}

/// 解析下拉列表 JSON（`[{"code":…,"name":…}, …]`，UTF-8）。
///
/// 容错：非 JSON、非数组、缺字段一律跳过，绝不抛（教务偶发返回 HTML 错误页）。
List<PublicQueryOption> parseDropListOptions(String body) {
  final text = body.trim();
  if (text.isEmpty || !text.startsWith('[')) return const [];
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (_) {
    return const [];
  }
  if (raw is! List) return const [];
  final out = <PublicQueryOption>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final code = item['code'];
    final name = item['name'];
    if (code == null || name == null) continue;
    final c = '$code'.trim();
    final n = '$name'.trim();
    if (c.isEmpty || n.isEmpty) continue;
    out.add(PublicQueryOption(code: c, name: n));
  }
  return out;
}

/// 解析「发布课表的学年学期」下拉（`Ms_KBBP_FBXQLLJXAP`）为学期列表。
List<PublicQueryTerm> parseTermOptions(String body) {
  final out = <PublicQueryTerm>[];
  for (final o in parseDropListOptions(body)) {
    final parsed = parseTermCode(o.code);
    if (parsed == null) continue;
    out.add(PublicQueryTerm(xn: parsed.xn, xqM: parsed.xqM, name: o.name));
  }
  return out;
}

/// 解析选择器 XML（`/taglib/CombBoxServlet.jsp`，UTF-8）：
/// `<data><info><value>…</value><name>…</name></info>…</data>`。
List<PublicQueryOption> parseComboBoxXml(String body) {
  final text = body.trim();
  if (text.isEmpty || !text.contains('<info>')) return const [];
  final out = <PublicQueryOption>[];
  for (final m in RegExp(
    r'<info>(.*?)</info>',
    dotAll: true,
  ).allMatches(text)) {
    final seg = m.group(1)!;
    String pick(String tag) =>
        RegExp(
          '<$tag>(.*?)</$tag>',
          dotAll: true,
        ).firstMatch(seg)?.group(1)?.trim() ??
        '';
    // XML 里未转义的实体要还原，否则名称会带 &amp; 之类
    String unescape(String v) => v
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    final value = unescape(pick('value'));
    final name = unescape(pick('name'));
    if (value.isEmpty || name.isEmpty) continue;
    out.add(PublicQueryOption(code: value, name: name));
  }
  return out;
}

/// 教务的空结果页（两种文案都要认：`GS1.jsp` 与 `GS4.jsp` 用词不同）。
bool isEmptyReport(String html) =>
    html.contains('没有检索到记录') || html.contains('没有符合检索条件的记录');

/// 会话失效判定（547 字节的 alert 页）。
bool isExpiredSession(String html) =>
    html.contains('凭证已失效') || html.contains('请重新登录');

/// `KB_ExpTeacherSchedualAction.do?hidOption=getpkts` 的响应（纯文本数字）。
String parsePkts(String body) =>
    RegExp(r'\d+').firstMatch(body.trim())?.group(0) ?? '';

/// 一次公共查询请求的**全部输入**。
///
/// 各字段含义随 [kind] 变化（同一个输入框在不同类别下喂不同参数）：
/// - [campusCode]：四类通用（`selXQ`/`hidXQ`）；班级课表用它限定校区，
///   且**必须与所选班级所在校区一致**，否则报告恒空；
/// - [classCode]/[teacherCode]/[courseCode]/[roomCode]/[buildingCode]：对应类别的主过滤；
/// - [departmentCode]/[majorCode]：仅班级课表（分学院/分专业）用。
class PublicQueryRequest {
  final PublicQueryKind kind;
  final PublicQueryTerm term;
  final String pkts;
  final String campusCode;
  final String departmentCode;
  final String majorCode;
  final String classCode;
  final String teacherCode;
  final String courseCode;
  final String buildingCode;
  final String roomCode;

  /// 年级（`nj`）：班级课表的选择器与报告都用它；默认取学年。
  final String grade;

  /// 培养层次（`selPYCC`/`hidPYCC`，码集 `MsCodeset` + `DM-PYCC`）。
  ///
  /// 实测是**真过滤条件**：`05`=本科命中本科班级，`02`=统招本科对同一班级返回空，
  /// 空串 = 不限（与 `05` 对本科班级结果相同）。只影响班级课表。
  final String trainLevel;

  const PublicQueryRequest({
    required this.kind,
    required this.term,
    this.pkts = '',
    this.campusCode = '',
    this.departmentCode = '',
    this.majorCode = '',
    this.classCode = '',
    this.teacherCode = '',
    this.courseCode = '',
    this.buildingCode = '',
    this.roomCode = '',
    this.grade = '',
    this.trainLevel = '',
  });

  /// 选择器（CombBox）需要的附加参数，与页面 JS 的 `setCombBoxOtherParameter` 一致。
  Map<String, String> comboParams() {
    final nj = grade.isEmpty ? '${term.xn}' : grade;
    return switch (kind) {
      PublicQueryKind.klass => {
        'xn': '${term.xn}',
        'xq_m': '${term.xqM}',
        'nj': nj,
        'yxb': departmentCode,
        'zy': majorCode,
        'flag': kind.hidFlag,
        'xqdm': campusCode,
      },
      PublicQueryKind.teacher => {
        'xn': '${term.xn}',
        'xq_m': '${term.xqM}',
        'flag': kind.hidFlag,
        'jsbm': departmentCode,
      },
      PublicQueryKind.course => {
        'xn': '${term.xn}',
        'xq_m': '${term.xqM}',
        'selGS': '1',
        'sel_kcbq': '',
      },
      PublicQueryKind.classroom => {
        'xq_m': campusCode,
        'jslx_m': '',
        'lf_m': buildingCode,
        'flag': 'xkyjs',
      },
    };
  }

  /// 稳定缓存键（provider family 用；同时作为值语义的相等判据）。
  String get cacheKey => [
    kind.name,
    term.code,
    pkts,
    campusCode,
    departmentCode,
    majorCode,
    classCode,
    teacherCode,
    courseCode,
    buildingCode,
    roomCode,
    grade,
    trainLevel,
  ].join('|');

  @override
  bool operator ==(Object other) =>
      other is PublicQueryRequest && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;

  /// 该请求是否已具备「能查到东西」的最小过滤条件（界面据此决定按钮可用）。
  ///
  /// 班级课表四档实测都可用（分班级 / 分专业 / 分学院 / 分校区），任一非空即可查。
  bool get ready => switch (kind) {
    PublicQueryKind.course => courseCode.isNotEmpty,
    PublicQueryKind.teacher => teacherCode.isNotEmpty,
    PublicQueryKind.klass =>
      classCode.isNotEmpty ||
          majorCode.isNotEmpty ||
          departmentCode.isNotEmpty ||
          campusCode.isNotEmpty,
    PublicQueryKind.classroom => campusCode.isNotEmpty,
  };

  PublicQueryRequest copyWith({
    PublicQueryKind? kind,
    PublicQueryTerm? term,
    String? pkts,
    String? campusCode,
    String? departmentCode,
    String? majorCode,
    String? classCode,
    String? teacherCode,
    String? courseCode,
    String? buildingCode,
    String? roomCode,
    String? grade,
    String? trainLevel,
  }) => PublicQueryRequest(
    kind: kind ?? this.kind,
    term: term ?? this.term,
    pkts: pkts ?? this.pkts,
    campusCode: campusCode ?? this.campusCode,
    departmentCode: departmentCode ?? this.departmentCode,
    majorCode: majorCode ?? this.majorCode,
    classCode: classCode ?? this.classCode,
    teacherCode: teacherCode ?? this.teacherCode,
    courseCode: courseCode ?? this.courseCode,
    buildingCode: buildingCode ?? this.buildingCode,
    roomCode: roomCode ?? this.roomCode,
    grade: grade ?? this.grade,
    trainLevel: trainLevel ?? this.trainLevel,
  );
}

/// 生成报告端点的表单体（字段名逐条来自实测，**勿臆造**）。
///
/// 与页面 JS 一致：整张 `ActionForm` 序列化提交；未勾选的 checkbox 不发。
Map<String, String> buildReportFields(PublicQueryRequest request) {
  final term = request.term;
  final grade = request.grade.isEmpty ? '${term.xn}' : request.grade;
  final fields = <String, String>{
    'xnxq': term.code,
    'xn': '${term.xn}',
    'xn1': '',
    '_xq': '',
    'xq_m': '${term.xqM}',
    'nj': grade,
    'hidNJ': grade,
    'isNjQuery': 'on',
    'chkXsxxnr': 'on',
    'xsxxnr': '1',
    'hidBfy': '0',
    'hidZZLX': 'A4',
    'radiob': 'A4',
    'radiofx': 'hx',
    'orientation': 'L',
    'userType': 'STU',
    'sfxsym': 'xsym',
    'pkts': request.pkts,
    'xssj': 'xssj',
    'xsrq': 'xsrq',
    'chkXSDYRQ': 'on',
    'chkXSDYSJ': 'on',
    'chkXSYM': 'on',
    'selGS': '1',
    'chk_week6': '1',
    'chk_week7': '1',
    // 页面把 menucode 截成首字母后提交
    'menucode': 'S',
  };
  switch (request.kind) {
    case PublicQueryKind.klass:
      final byClass = request.classCode.isNotEmpty;
      final byMajor = request.majorCode.isNotEmpty;
      final byDepartment = request.departmentCode.isNotEmpty;
      final byCampus =
          request.campusCode.isNotEmpty &&
          !(byClass || byMajor || byDepartment);
      fields.addAll({
        'hidCXLX': byClass
            ? 'fbj'
            : byMajor
            ? 'fzy'
            : byDepartment
            ? 'fyxb'
            : byCampus
            ? 'fxq'
            : '',
        'radioa': byClass
            ? '5'
            : byMajor
            ? '4'
            : byDepartment
            ? '3'
            : byCampus
            ? '2'
            : '1',
        'selXQ': request.campusCode,
        'hidXQ': request.campusCode,
        'selYXB': request.departmentCode,
        'hidYXB': request.departmentCode,
        'selZY': request.majorCode,
        'hidZYDM': request.majorCode,
        'selBJ': request.classCode,
        'hidBJDM': request.classCode,
        // 培养层次：**原样提交**（实测 `05` 本科命中本科班级；`02` 统招本科对同一
        // 班级返回空；空串 = 不限，与 `05` 对本科班级等价）。界面默认 `05`。
        'selPYCC': request.trainLevel,
        'hidPYCC': request.trainLevel,
      });
    case PublicQueryKind.teacher:
      fields.addAll({
        'hidFlag': request.kind.hidFlag,
        'hidCXLX': 'fjs',
        'radio': '2',
        'selJS': request.teacherCode,
        'hidJSDM': request.teacherCode,
        'hid_kc': '',
        'selXQ': request.campusCode,
        'hidXQ': request.campusCode,
      });
    case PublicQueryKind.course:
      fields.addAll({'hidKCDM': request.courseCode, 'selectkc': ''});
    case PublicQueryKind.classroom:
      final byRoom = request.roomCode.isNotEmpty;
      fields.addAll({
        'hidCXLX': byRoom
            ? 'fjsi'
            : (request.buildingCode.isEmpty ? '' : 'flf'),
        'radioa': 'on',
        'hidFJBH': request.roomCode,
        'selXQ': request.campusCode,
        'hidXQ': request.campusCode,
        // 按教室时不再发楼房码（教室码自带唯一性；实测按教室 = 只回这一间）
        'selLF': byRoom ? '' : request.buildingCode,
        'hidLF': byRoom ? '' : request.buildingCode,
        'selJSLX': '',
        'hidJSLX': '',
        'hidSYDW': '',
        'jslx': '',
        'lx': '',
        'xkyjs': '1',
        // 页面把选择器的值同时写进 selJSMC 与 hidFJBH
        'selJSMC': request.roomCode,
        'skdd': '',
      });
  }
  return fields;
}
