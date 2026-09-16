/// 教务「选课」领域模型（纯数据，无 Flutter 依赖）。
///
/// 数据来源与字段口径全部来自 2026-09-14 的实测抓包，见
/// `reverse_engineering/选课接口.md`。
library;

import 'dart:convert';

import 'data_table_page.dart';

/// 是否为「有效」的教务布尔值（`"1"` / `"true"`）。
bool _flag(String? value) {
  final v = (value ?? '').trim().toLowerCase();
  return v == '1' || v == 'true' || v == 'on' || v == 'yes';
}

double? _num(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return null;
  return double.tryParse(v);
}

/// 选课会话元信息 —— `GET jw/common/getWsxkTimeRange.action?xktype=<2|88>`。
///
/// 教务页面靠这一个接口拿到「学年/学期/轮次 id/开放时间/课程范围/学籍年级专业」，
/// 我们的**每次**选课相关请求都必须带它给出的 `lcid`、`xn`、`xqM`。
class SelectionSession {
  const SelectionSession({
    required this.xktype,
    required this.xn,
    required this.xqM,
    required this.xqName,
    required this.xnxqDesc,
    required this.status,
    required this.message,
    this.xh = '',
    this.lcmc = '',
    this.lcid = '',
    this.qssj = '',
    this.jssj = '',
    this.rxksjqs = '',
    this.rxksjjs = '',
    this.isValidTimerange = false,
    this.isValidRxksj = false,
    this.nj = '',
    this.zydm = '',
    this.zymc = '',
    this.yxbdm = '',
    this.zysx = '',
    this.sfbd = '',
    this.djs = '',
    this.isXjls = '',
    this.xxkckzfs = '',
    this.yxkzyfxxk = '',
    this.yxsjct = '',
    this.kcfw = '',
    this.kcfwmc = '',
  });

  /// 2 = 正选（网上选课），88 = 外年级/专业选课。
  final int xktype;
  final String xn;
  final String xqM;
  final String xqName;
  final String xnxqDesc;

  /// **教务选课模块自己给的学生学号**（同一个响应里的 `xh`）。
  ///
  /// ⚠ 选课的所有请求都必须回传这个值（见 `selectionStudentIdProvider`）：
  /// 2026-09-15 实测，写操作 `saveElectiveCourse.action` 会拿表单里的 `xh`
  /// 与「本人」比对，传别的值（如学籍 `<yhxh>`）会被拒：
  /// 「当前选课操作的用户不是选课学生本人！」。只读端点则对此不敏感。
  final String xh;

  /// 教务返回的业务状态码（`"200"` = 成功）。
  final String status;
  final String message;

  /// 选课轮次名，如「第一轮退改选」。
  final String lcmc;

  /// 轮次 id —— 后续查询/提交必须回传。
  final String lcid;

  /// 整轮开放时间与每日可选时段（教务原文，可能是 `undefined`）。
  final String qssj;
  final String jssj;
  final String rxksjqs;
  final String rxksjjs;
  final bool isValidTimerange;
  final bool isValidRxksj;

  final String nj;
  final String zydm;
  final String zymc;
  final String yxbdm;

  /// 专业筛选 / 是否绑定 / 冻结 / 学籍流水等教务开关，原样回传。
  final String zysx;
  final String sfbd;
  final String djs;
  final String isXjls;
  final String xxkckzfs;
  final String yxkzyfxxk;
  final String yxsjct;

  /// 允许的课程范围码，逗号分隔（如 `zxbnj,zxggrx,fx,zxknj`）。
  final String kcfw;

  /// 课程范围中文名，逗号分隔。
  final String kcfwmc;

  bool get ok => status == '200';

  /// 当前是否处于有效的选课时间区段（教务页面同款判据）。
  bool get open => ok && isValidTimerange;

  List<String> get scopeCodes => kcfw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  List<String> get scopeNames => kcfwmc
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  /// 时间区段文案，如「2026-09-14 09:00 → 2026-09-16 17:00」。
  String get windowLabel =>
      (qssj.isEmpty || jssj.isEmpty) ? '' : '$qssj → $jssj';

  /// 每日可选时段文案，如「09:00 → 17:00」。
  String get dailyLabel =>
      (rxksjqs.isEmpty || rxksjjs.isEmpty) ? '' : '$rxksjqs → $rxksjjs';

  static const SelectionSession unknown = SelectionSession(
    xktype: 2,
    xn: '',
    xqM: '',
    xqName: '',
    xnxqDesc: '',
    status: '',
    message: '',
  );

  /// 解析 `getWsxkTimeRange.action` 的响应（`result` 是**字符串化的 JSON**）。
  static SelectionSession fromEnvelope(
    Map<String, dynamic> envelope, {
    required int xktype,
  }) {
    final raw = envelope['result'];
    Map<String, dynamic> result = const {};
    if (raw is Map<String, dynamic>) {
      result = raw;
    } else if (raw is String && raw.trim().isNotEmpty) {
      final decoded = tryJsonMap(raw);
      result = decoded ?? const {};
    }
    String str(String key) {
      final value = result[key];
      if (value == null) return '';
      final text = '$value';
      return text == 'undefined' ? '' : text;
    }

    return SelectionSession(
      xktype: xktype,
      xn: str('xn'),
      xqM: str('xqM'),
      xqName: str('xqName'),
      xnxqDesc: str('xnxqDesc'),
      status: '${envelope['status'] ?? ''}',
      message: '${envelope['message'] ?? ''}',
      xh: str('xh'),
      lcmc: str('lcmc'),
      lcid: str('lcid'),
      qssj: str('qssj'),
      jssj: str('jssj'),
      rxksjqs: str('rxksjqs'),
      rxksjjs: str('rxksjjs'),
      isValidTimerange: _flag(str('isValidTimerange')),
      isValidRxksj: _flag(str('isValidRxksj')),
      nj: str('nj'),
      zydm: str('zydm'),
      zymc: str('zymc'),
      yxbdm: str('yxbdm'),
      zysx: str('zysx'),
      sfbd: str('sfbd'),
      djs: str('djs'),
      isXjls: str('isXjls'),
      xxkckzfs: str('xxkckzfs'),
      yxkzyfxxk: str('yxkzyfxxk'),
      yxsjct: str('yxsjct'),
      kcfw: str('kcfw'),
      kcfwmc: str('kcfwmc'),
    );
  }
}

/// 把 `{"a":1}` 这样的字符串安全地解成 Map（教务常把 JSON 再套一层字符串）。
Map<String, dynamic>? tryJsonMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return null;
}

/// 选课学分/门数额度 —— `GET jw/common/getSelectLessonScoreKcsInfo.action`。
class SelectionQuota {
  const SelectionQuota({
    this.specifiedCredits,
    this.specifiedCount,
    this.usedCredits,
    this.usedCount,
    this.totalCredits,
    this.totalCount,
    this.feeText = '',
  });

  /// 指定学分 / 指定门数（培养方案要求，教务文案「指定」）。
  final double? specifiedCredits;
  final double? specifiedCount;

  /// 已选学分 / 已选门数。
  final double? usedCredits;
  final double? usedCount;

  /// 总学分 / 总门数。
  final double? totalCredits;
  final double? totalCount;

  /// 费用说明原文（如「课程学分费用预算总额：1530.0元」）。
  final String feeText;

  static const SelectionQuota empty = SelectionQuota();

  static SelectionQuota fromEnvelope(Map<String, dynamic> envelope) {
    final raw = envelope['result'];
    Map<String, dynamic> result = const {};
    if (raw is Map<String, dynamic>) {
      result = raw;
    } else if (raw is String && raw.trim().isNotEmpty) {
      result = tryJsonMap(raw) ?? const {};
    }
    String str(String key) => '${result[key] ?? ''}';
    return SelectionQuota(
      specifiedCredits: _num(str('zdxf')),
      specifiedCount: _num(str('zdms')),
      usedCredits: _num(str('yxxf')),
      usedCount: _num(str('yxms')),
      totalCredits: _num(str('zxf')),
      totalCount: _num(str('zms')),
      feeText: str('feetotal'),
    );
  }
}

/// 学籍年级/专业 —— `GET jw/common/getStuGradeSpeciatyInfo.action?xh=<学号>`。
class StudentGradeMajor {
  const StudentGradeMajor({
    this.nj = '',
    this.zydm = '',
    this.zymc = '',
    this.pycc = '',
    this.dwh = '',
    this.yxdm = '',
  });

  final String nj;
  final String zydm;
  final String zymc;
  final String pycc;
  final String dwh;
  final String yxdm;

  static const StudentGradeMajor empty = StudentGradeMajor();

  static StudentGradeMajor fromEnvelope(Map<String, dynamic> envelope) {
    final raw = envelope['result'];
    Map<String, dynamic> result = const {};
    if (raw is Map<String, dynamic>) {
      result = raw;
    } else if (raw is String && raw.trim().isNotEmpty) {
      result = tryJsonMap(raw) ?? const {};
    }
    String str(String key) => '${result[key] ?? ''}';
    return StudentGradeMajor(
      nj: str('nj'),
      zydm: str('zydm'),
      zymc: str('zymc'),
      pycc: str('pycc'),
      dwh: str('dwh'),
      yxdm: str('yxdm'),
    );
  }
}

/// 课程范围下拉项 —— `POST frame/droplist/getDropLists.action`（`comboBoxName=MsKcfw`）。
class CourseScope {
  const CourseScope({required this.code, required this.name});

  final String code;
  final String name;
}

/// 「网上选课」列表行（`taglib/DataTable.jsp?tableId=2568`）。
///
/// 列表是**课程级**的：任课教师/上课班号/时间地点在这一层为空，
/// 选定课程后才在选课确认页拉教学班列表（`tableId=6142`）。
class OptionalCourse {
  const OptionalCourse({
    required this.name,
    this.courseCode = '',
    this.internalCode = '',
    this.credits,
    this.totalHours,
    this.category = '',
    this.attribute = '',
    this.classCode = '',
    this.className = '',
    this.teacher = '',
    this.selectionMethod = '',
    this.status = '',
    this.kclb1 = '',
    this.kclb2 = '',
    this.kclb3 = '',
    this.examMode = '',
    this.skbzdm = '',
    this.skbjdm = '',
    this.points,
    this.buyBook = false,
    this.isCx = false,
    this.isYxtj = false,
    this.selectable = true,
  });

  /// `[1004001943]会计学` 里的课程代码。
  final String courseCode;

  /// 课程名。
  final String name;

  /// 教务内部课程代码（隐藏格 `kcdm`，如 `000160`）—— 后续请求全部用它。
  final String internalCode;

  final double? credits;
  final int? totalHours;

  /// 课程类别（`lb`，列表里多为空，由课程类别二 `kclb2` 映射）。
  final String category;

  /// 课程属性（`kcsx`，如「理论课」）。
  final String attribute;

  /// 上课班号 / 上课班级名称（课程级列表里为空）。
  final String classCode;
  final String className;

  /// 任课教师（课程级列表里为空，教学班里才有）。
  final String teacher;

  /// 选课方式（`管理人员选` / `学生网上选`）。
  final String selectionMethod;

  /// 选课状态（已选/未选）。
  final String status;

  final String kclb1;
  final String kclb2;
  final String kclb3;
  final String examMode;

  /// 上课班组代码 / 上课班级代码（用于提交选课）。
  final String skbzdm;
  final String skbjdm;

  /// 投入选课币。
  final double? points;
  final bool buyBook;
  final bool isCx;
  final bool isYxtj;

  /// 是否可选（`isSelectableSkbjdm.action` 结果，默认按可选展示）。
  final bool selectable;

  bool get alreadySelected => status.contains('已选') || status.contains('选中');

  OptionalCourse copyWith({bool? selectable}) => OptionalCourse(
    name: name,
    courseCode: courseCode,
    internalCode: internalCode,
    credits: credits,
    totalHours: totalHours,
    category: category,
    attribute: attribute,
    classCode: classCode,
    className: className,
    teacher: teacher,
    selectionMethod: selectionMethod,
    status: status,
    kclb1: kclb1,
    kclb2: kclb2,
    kclb3: kclb3,
    examMode: examMode,
    skbzdm: skbzdm,
    skbjdm: skbjdm,
    points: points,
    buyBook: buyBook,
    isCx: isCx,
    isYxtj: isYxtj,
    selectable: selectable ?? this.selectable,
  );

  /// 从 DataTable 的一行（`td name` → 文本）构造。
  static OptionalCourse fromRow(Map<String, String> row) {
    final coded = splitCodedName(row['kc'] ?? '');
    return OptionalCourse(
      name: coded.name,
      courseCode: coded.code,
      internalCode: (row['kcdm'] ?? '').trim(),
      credits: _num(row['xf']),
      totalHours: _num(row['zxs'])?.round(),
      category: (row['lb'] ?? '').trim(),
      attribute: (row['kcsx'] ?? '').trim(),
      classCode: (row['skbh'] ?? '').trim(),
      className: (row['skbjmc'] ?? '').trim(),
      teacher: (row['rkjs'] ?? '').trim(),
      selectionMethod: (row['xkfs'] ?? '').trim(),
      status: (row['xk_status'] ?? '').trim(),
      kclb1: (row['kclb1'] ?? '').trim(),
      kclb2: (row['kclb2'] ?? '').trim(),
      kclb3: (row['kclb3'] ?? '').trim(),
      examMode: (row['khfs'] ?? '').trim(),
      skbzdm: (row['skbzdm'] ?? '').trim(),
      skbjdm: (row['skbjdm'] ?? '').trim(),
      points: _num(row['xk_points']),
      buyBook: _flag(row['is_buy_book']),
      isCx: _flag(row['is_cx']),
      isYxtj: _flag(row['is_yxtj']),
    );
  }
}

/// 选课结果里的一门已选课程（`student/wsxk.zxjg.jsp` 的 `reportArea` 表）。
class SelectedCourse {
  const SelectedCourse({
    required this.name,
    required this.cells,
    this.courseCode = '',
    this.credits,
    this.category = '',
    this.teacher = '',
    this.classCode = '',
    this.className = '',
    this.selectionMethod = '',
    this.crossGrade = '',
    this.status = '',
    this.enrolled = '',
    this.campus = '',
    this.timePlace = '',
    this.itemCode = '',
  });

  final String courseCode;
  final String name;
  final double? credits;
  final String category;
  final String teacher;
  final String classCode;
  final String className;
  final String selectionMethod;
  final String crossGrade;
  final String status;
  final String enrolled;
  final String campus;
  final String timePlace;

  /// 退选用的 `items` 值（表格末格：上课班组代码，如 `1004606732-066`）。
  final String itemCode;

  /// 原始格子，界面上按需兜底显示。
  final List<String> cells;

  bool get dropped => status.contains('退') || status.contains('取消');

  Map<String, dynamic> toJson() => {
    'courseCode': courseCode,
    'name': name,
    'credits': credits,
    'category': category,
    'teacher': teacher,
    'classCode': classCode,
    'className': className,
    'selectionMethod': selectionMethod,
    'crossGrade': crossGrade,
    'status': status,
    'enrolled': enrolled,
    'campus': campus,
    'timePlace': timePlace,
    'itemCode': itemCode,
  };

  static SelectedCourse fromJson(Map<String, dynamic> json) => SelectedCourse(
    name: '${json['name'] ?? ''}',
    cells: const [],
    courseCode: '${json['courseCode'] ?? ''}',
    credits: _num('${json['credits'] ?? ''}'),
    category: '${json['category'] ?? ''}',
    teacher: '${json['teacher'] ?? ''}',
    classCode: '${json['classCode'] ?? ''}',
    className: '${json['className'] ?? ''}',
    selectionMethod: '${json['selectionMethod'] ?? ''}',
    crossGrade: '${json['crossGrade'] ?? ''}',
    status: '${json['status'] ?? ''}',
    enrolled: '${json['enrolled'] ?? ''}',
    campus: '${json['campus'] ?? ''}',
    timePlace: '${json['timePlace'] ?? ''}',
    itemCode: '${json['itemCode'] ?? ''}',
  );
}

/// 「选课结果」整页数据（含统计与课程列表）。
class SelectionResult {
  const SelectionResult({
    this.termLabel = '',
    this.creditLimit,
    this.totalCredits,
    this.totalCount,
    this.categoryCredits = const {},
    this.categoryCounts = const {},
    this.courses = const [],
    this.fromCache = false,
  });

  final String termLabel;
  final double? creditLimit;
  final double? totalCredits;
  final int? totalCount;

  /// 分类统计：如 `{'已选': 25.5, '限选': 26.0, '可选': 0.5}`。
  final Map<String, double> categoryCredits;
  final Map<String, int> categoryCounts;

  final List<SelectedCourse> courses;

  /// 是否来自本地缓存（离线展示）。
  final bool fromCache;

  static const SelectionResult empty = SelectionResult();

  double get selectedCredits => totalCredits ?? 0;

  /// 剩余可选学分（学分上限 − 已选）。
  double? get remainingCredits {
    final limit = creditLimit;
    if (limit == null) return null;
    return limit - selectedCredits;
  }

  SelectionResult copyWith({bool? fromCache}) => SelectionResult(
    termLabel: termLabel,
    creditLimit: creditLimit,
    totalCredits: totalCredits,
    totalCount: totalCount,
    categoryCredits: categoryCredits,
    categoryCounts: categoryCounts,
    courses: courses,
    fromCache: fromCache ?? this.fromCache,
  );

  Map<String, dynamic> toJson() => {
    'termLabel': termLabel,
    'creditLimit': creditLimit,
    'totalCredits': totalCredits,
    'totalCount': totalCount,
    'categoryCredits': categoryCredits,
    'categoryCounts': categoryCounts,
    'courses': courses.map((e) => e.toJson()).toList(),
  };

  static SelectionResult fromJson(Map<String, dynamic> json) => SelectionResult(
    termLabel: '${json['termLabel'] ?? ''}',
    creditLimit: _num('${json['creditLimit'] ?? ''}'),
    totalCredits: _num('${json['totalCredits'] ?? ''}'),
    totalCount: (_num('${json['totalCount'] ?? ''}'))?.round(),
    categoryCredits: _doubleMap(json['categoryCredits']),
    categoryCounts: _intMap(json['categoryCounts']),
    courses: (json['courses'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SelectedCourse.fromJson)
        .toList(growable: false),
    fromCache: true,
  );

  static Map<String, double> _doubleMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, double>{};
    raw.forEach((key, value) {
      final parsed = _num('$value');
      if (parsed != null) out['$key'] = parsed;
    });
    return out;
  }

  static Map<String, int> _intMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((key, value) {
      final parsed = _num('$value');
      if (parsed != null) out['$key'] = parsed.round();
    });
    return out;
  }
}

/// 被取消的选课记录（`student/wsxk.qxbxkc.jsp`）。
class CancelledCourse {
  const CancelledCourse({
    required this.name,
    this.courseCode = '',
    this.credits,
    this.teacher = '',
    this.classCode = '',
    this.reason = '',
    this.term = '',
    this.cells = const [],
  });

  final String courseCode;
  final String name;
  final double? credits;
  final String teacher;
  final String classCode;
  final String reason;
  final String term;
  final List<String> cells;

  static CancelledCourse fromCells(List<String> cells) {
    final joined = cells.join(' ').trim();
    final coded = splitCodedName(cells.isNotEmpty ? cells.first : '');
    return CancelledCourse(
      name: coded.name.isEmpty ? joined : coded.name,
      courseCode: coded.code,
      credits: cells.length > 1 ? _num(cells[1]) : null,
      teacher: cells.length > 2 ? cells[2] : '',
      classCode: cells.length > 3 ? cells[3] : '',
      reason: cells.length > 4 ? cells[4] : '',
      cells: cells,
    );
  }
}

/// 选课写入类操作的结果（教务返回 `{status, message}`）。
class SelectionWriteResult {
  const SelectionWriteResult({required this.ok, required this.message});

  final bool ok;
  final String message;

  static SelectionWriteResult fromEnvelope(Map<String, dynamic> envelope) {
    final status = '${envelope['status'] ?? ''}';
    return SelectionWriteResult(
      ok: status == '200',
      message: '${envelope['message'] ?? ''}',
    );
  }

  static const SelectionWriteResult networkFailure = SelectionWriteResult(
    ok: false,
    message: '网络异常，请稍后重试',
  );
}
