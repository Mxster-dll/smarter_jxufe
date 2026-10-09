/// 培养方案 · **实践环节**（页 `pyfa.sjhj.html`，表 `tableId=2509`）。
///
/// 2026-10-08 立。此前 App 只接了「理论课程」（`pyfa.llkc.html` / `tableId=2508`），
/// 于是**军事训练**这类只挂在实践环节里的课在毕业学分页落进了「未归类」——
/// 用户当场指出：「我们当前的培养方案查询接口只是『理论课程』的培养方案，
/// 但实际上培养方案还有『实践环节』，而军事训练就属于这一部分」。
///
/// 两张表**互有重叠**：实测 2025 级计算机科学与技术，理论课程里有
/// `2024实践教育课/劳动教育`、`职业生涯规划`，实践环节里有
/// `军事训练 / 创新创业实践活动 / 毕业实习 / 毕业设计` —— 本专业不重叠，
/// 但别的专业可能重叠，所以统计口径里两者**分开列**（见 §13.4）。
///
/// 数据形状（2026-10-08 实测抓包，fixture 见
/// `test/fixtures/curriculum_practice_2509.html`）：
/// `序号 | 学年学期 | 环节 | 学分 | 环节类别 | 考核方式 | 周数 | 标识 | (隐藏 hjdm)`，
/// 每个 `<td>` 都带 `name=` 属性，**按 name 解析**（不按下标，下标里夹着隐藏列）。
library;

/// 一条实践环节。
class PracticeStage {
  /// 序号（1 起）。
  final int index;

  /// 学年学期原文，如 `2025-2026学年第一学期`；表里常为空（表示未排定）。
  final String semester;

  /// 环节代码，如 `1305002302`。
  final String code;

  /// 环节名称，如 `军事训练`。
  final String name;

  /// 学分。
  final double credit;

  /// 环节类别，如 `军训` / `科研创新实践` / `实习实训` / `论文设计`。
  final String category;

  /// 考核方式（实测这一列恒为「考查」）。
  final String assessment;

  /// 周数。
  final double weeks;

  /// 「标识」列（实测为空）。
  final String identification;

  /// 隐藏列 `hjdm`（环节代码的内部标识，点详情用）。
  final String detailId;

  const PracticeStage({
    required this.index,
    required this.code,
    required this.name,
    required this.credit,
    this.semester = '',
    this.category = '',
    this.assessment = '',
    this.weeks = 0,
    this.identification = '',
    this.detailId = '',
  });

  Map<String, dynamic> toMap() => {
    'index': index,
    'semester': semester,
    'code': code,
    'name': name,
    'credit': credit,
    'category': category,
    'assessment': assessment,
    'weeks': weeks,
    'identification': identification,
    'detailId': detailId,
  };

  factory PracticeStage.fromMap(Map<String, dynamic> m) => PracticeStage(
    index: _asInt(m['index']),
    semester: m['semester'] as String? ?? '',
    code: m['code'] as String? ?? '',
    name: m['name'] as String? ?? '',
    credit: _asDouble(m['credit']),
    category: m['category'] as String? ?? '',
    assessment: m['assessment'] as String? ?? '',
    weeks: _asDouble(m['weeks']),
    identification: m['identification'] as String? ?? '',
    detailId: m['detailId'] as String? ?? '',
  );
}

/// 容错取数：旧缓存里这些字段可能是字符串（写过 JSON 的人都知道），
/// **不许 `as num?` 直接炸** —— §3「模型」的硬口径。
double _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? 0;
  return 0;
}

int _asInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

/// 一个专业的实践环节全表。
class PracticeCurriculum {
  final int year;
  final String collegeName;
  final String majorName;
  final List<PracticeStage> stages;
  final DateTime? lastUpdated;

  const PracticeCurriculum({
    required this.year,
    required this.collegeName,
    required this.majorName,
    required this.stages,
    this.lastUpdated,
  });

  /// 实践环节要求学分 = 表内各项学分之和（**以本专业表为准**，不套用文件里的
  /// 「理工类不少于 19 学分」那种区间 —— 那是修订指导意见，各专业表才是准的）。
  double get totalCredits =>
      stages.fold<double>(0, (sum, s) => sum + s.credit);

  /// 表里出现的全部环节代码（用于「实践类课程不计入加权」的判定）。
  Set<String> get codes => {
    for (final s in stages)
      if (s.code.isNotEmpty) s.code,
  };

  /// 表里出现的全部环节名称。
  Set<String> get names => {
    for (final s in stages)
      if (s.name.isNotEmpty) s.name,
  };

  Map<String, dynamic> toMap() => {
    'year': year,
    'collegeName': collegeName,
    'majorName': majorName,
    'lastUpdated': lastUpdated?.toIso8601String(),
    'stages': [for (final s in stages) s.toMap()],
  };

  factory PracticeCurriculum.fromMap(Map<String, dynamic> m) =>
      PracticeCurriculum(
        year: _asInt(m['year']),
        collegeName: m['collegeName'] as String? ?? '',
        majorName: m['majorName'] as String? ?? '',
        lastUpdated: DateTime.tryParse(m['lastUpdated'] as String? ?? ''),
        stages: [
          for (final e in (m['stages'] as List? ?? const []))
            if (e is Map) PracticeStage.fromMap(Map<String, dynamic>.from(e)),
        ],
      );
}
