/// 学习通（超星）课程 —— 「学生端」课程卡片。
///
/// 来源：`GET https://mooc1.chaoxing.com/visit/courses`（HTML，58233 B 量级）。
/// 每门课三个标识：`courseId`（课程）、`classId`（教学班）、`cpi`（本人的课程平台
/// 身份号，**全班同一个**）。作业页的 `enc` / `openc` 是**每门课各不相同**的签名，
/// 不在本模型里 —— 它属于「取数过程中的临时凭据」，见
/// `data/anti_corruption/chaoxing_work_parser.dart` 的 [chaoxingWorkEntryQuery]。
library;

/// 一门学习通课程。
class ChaoxingCourse {
  const ChaoxingCourse({
    required this.courseId,
    required this.classId,
    required this.cpi,
    required this.name,
  });

  /// 课程 id（形如 `266750349`）。
  final String courseId;

  /// 教学班 id（形如 `153775462`）。
  final String classId;

  /// 本人的课程平台身份号（形如 `487826070`，同一账号下所有课相同）。
  final String cpi;

  /// 原始课程名，**含学期前缀**（如 `261学期 计算机组成原理`）。
  final String name;

  /// 稳定键：`<courseId>/<classId>`（作业按它归属）。
  String get key => '$courseId/$classId';

  /// 学期前缀（`261学期`）；认不出时为空串。
  ///
  /// 口径 = 名称开头的连续 `\d{3}学期`（如 `261学期` = 26-27 学年第 1 学期）。
  /// ⚠ 大量课程**没有**前缀（`253程序设计实训`、`大学生国家安全教育`），
  /// 此时 [displayName] 原样返回，不要硬造学期。
  String get termLabel {
    final m = RegExp(r'^(\d{3}学期)').firstMatch(name.trim());
    return m?.group(1) ?? '';
  }

  /// 学期码（`261`）；认不出时为空串。
  ///
  /// 与 `school_term.dart` 的 [schoolTermCode] **同一口径**（`xxy`：xx = 学年起始年后
  /// 两位，y = 1 第一学期 / 2 第二学期 / 3 第二阶段）—— 所以它能直接和
  /// `currentSchoolTerm()` 的结果比对，用来判定「当下学期」（见 `chaoxing_scan.dart`）。
  String get termCode => termLabel.replaceAll('学期', '');

  /// 去掉学期前缀与首尾空白后的课程名（列表里显示这个）。
  String get displayName {
    final t = name.trim();
    final term = termLabel;
    if (term.isEmpty) return t;
    return t.substring(term.length).trim();
  }

  Map<String, dynamic> toJson() => {
    'courseId': courseId,
    'classId': classId,
    'cpi': cpi,
    'name': name,
  };

  /// 容错解析：缺字段/类型不对一律回落空串（旧缓存不能让页面崩）。
  factory ChaoxingCourse.fromJson(Map<String, dynamic> json) => ChaoxingCourse(
    courseId: _str(json['courseId']),
    classId: _str(json['classId']),
    cpi: _str(json['cpi']),
    name: _str(json['name']),
  );

  /// ⚠ 不要写 `as String?`：脏数据（数字/布尔）会抛 `type 'int' is not a subtype`。
  static String _str(Object? value) => value == null ? '' : value.toString().trim();

  @override
  bool operator ==(Object other) =>
      other is ChaoxingCourse &&
      other.courseId == courseId &&
      other.classId == classId &&
      other.cpi == cpi &&
      other.name == name;

  @override
  int get hashCode => Object.hash(courseId, classId, cpi, name);

  @override
  String toString() => 'ChaoxingCourse($key, $name)';
}
