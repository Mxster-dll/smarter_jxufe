/// 培养方案「开课学期」**侧表**（理论课程表第 2 列 `学年学期`）。
///
/// ## 为什么是侧表、而不是给 `Course` 加个字段
/// 教务「查看教学计划表」（`pyfa.llkc.html` / `tableId=2508`）每行除了课程本身，
/// 还带着**这一门课排在第几学年学期**（原文如 `2025-2026学年第一学期`）。
/// 但 `Course` 是 **Hive 对象类型**（`@HiveType`），加字段 = schema 变更 +
/// 重跑 build_runner + 旧缓存兼容；而这张侧表只在**培养方案页**用得上。
/// 口径与「实践环节」（`practice_stage.dart`）一致：**另开一个 `Box<String>`
/// 单 key JSON**，旧缓存不受影响、坏了也不影响主表。
///
/// ## 对齐方式（重要）
/// 侧表与 `Curriculum.courses` **按行序一一对应**（同一次 HTML 解析出来的），
/// 读的时候必须核对**条数相等**（[alignsWith]），不等就当作「没取到」——
/// 宁可不显示开课学期，也不能把学期错配到别的课上。
///
/// ## 学期标识的归一
/// 文本 → `(xn, xq)` 一律走 `lib/features/school_calendar/domain/school_time.dart`
/// 的 [schoolTermOfText]（§3「学校时间唯一出处」），本文件只做「认不出怎么办」。
library;

import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart'
    show schoolTermCode, schoolTermLabel;
import 'package:smarter_jxufe/features/school_calendar/domain/school_time.dart'
    show schoolTermOfText;

/// 「教务没排定开课学期」在界面上的统一文案（表里这一列常为空）。
const String kCurriculumTermUnassigned = '开课学期未排定';

/// 一门课的排定开课学期。
class CurriculumTermEntry {
  /// 课程代码（可能为空 —— 真实表里确有代码为空的行）。
  final String code;

  /// 课程名称（对不上代码时按名兜底核对）。
  final String name;

  /// `学年学期` 原文，如 `2025-2026学年第一学期`；空串 = 教务未排定。
  final String semester;

  const CurriculumTermEntry({
    required this.code,
    required this.name,
    this.semester = '',
  });

  Map<String, dynamic> toMap() => {
    'code': code,
    'name': name,
    'semester': semester,
  };

  factory CurriculumTermEntry.fromMap(Map<String, dynamic> m) =>
      CurriculumTermEntry(
        code: _asString(m['code']),
        name: _asString(m['name']),
        semester: _asString(m['semester']),
      );
}

/// 一个专业培养方案的**全部**开课学期（与 `Curriculum.courses` 同序）。
class CurriculumTerms {
  final int year;
  final String collegeName;
  final String majorName;
  final List<CurriculumTermEntry> entries;
  final DateTime? lastUpdated;

  const CurriculumTerms({
    required this.year,
    required this.collegeName,
    required this.majorName,
    required this.entries,
    this.lastUpdated,
  });

  /// 与 [courses] 同序的学期原文列表。
  List<String> get semesters => [for (final e in entries) e.semester];

  /// 是否有任何一行真的排了学期（全空 = 这份方案没排课表，界面要说清）。
  bool get hasAnySemester => entries.any((e) => e.semester.trim().isNotEmpty);

  /// 条数是否与课程表对得上（对齐判据）。
  bool alignsWith(int courseCount) => entries.length == courseCount;

  Map<String, dynamic> toMap() => {
    'year': year,
    'collegeName': collegeName,
    'majorName': majorName,
    'lastUpdated': lastUpdated?.toIso8601String(),
    'entries': [for (final e in entries) e.toMap()],
  };

  /// 容错解析：缺字段 / 类型不对一律退到默认值（§3「模型」），不让旧缓存打崩页面。
  factory CurriculumTerms.fromMap(Map<String, dynamic> m) => CurriculumTerms(
    year: _asInt(m['year']),
    collegeName: _asString(m['collegeName']),
    majorName: _asString(m['majorName']),
    lastUpdated: DateTime.tryParse(_asString(m['lastUpdated'])),
    entries: _entries(m['entries']),
  );
}

/// 容错取条目列表：不是 List 就当空表（`as List?` 会在脏数据上抛，别那么写）。
List<CurriculumTermEntry> _entries(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is Map) CurriculumTermEntry.fromMap(Map<String, dynamic>.from(e)),
  ];
}

/// 单行学期原文 → 界面标签（`2025-2026 学年第一学期`）；认不出 / 空 → [kCurriculumTermUnassigned]。
String curriculumTermLabel(String raw) {
  final term = schoolTermOfText(raw);
  if (term == null) return kCurriculumTermUnassigned;
  return schoolTermLabel(term.xn, term.xq);
}

/// 单行学期原文 → 短码（`251`）；认不出 / 空 → 空串。
String curriculumTermCode(String raw) {
  final term = schoolTermOfText(raw);
  if (term == null) return '';
  return schoolTermCode(term.xn, term.xq);
}

/// 排序键：`学年 × 10 + 学段`（先学年后学期）；认不出 / 空 → 排在**最后**（[termSortKeyUnknown]）。
///
/// ⚠ 不能拿中文标签直接比大小（那会按字符串排，`2025-2026` 与 `2026-2027` 恰好能排，
/// 但一旦格式变体混进来就乱），也不能把认不出的当 0（会跑到最前面冒充第一学期）。
int curriculumTermSortKey(String raw) {
  final term = schoolTermOfText(raw);
  if (term == null) return termSortKeyUnknown;
  return term.xn * 10 + term.xq;
}

/// 认不出学期时的排序键（比任何真实学年都大）。
const int termSortKeyUnknown = 1 << 20;

int _asInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

/// 容错取字符串：非字符串（旧版本可能把数字写进来）转成文本，`null` → 空串。
String _asString(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num || v is bool) return '$v';
  return '';
}
