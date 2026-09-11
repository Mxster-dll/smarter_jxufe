/// 分数估计 · 培养方案学分索引。
///
/// 用途：课程列表的学分加权平均需要每门课的学分。本模块的课程由课表导入
/// 或手工添加，学分可能缺失/不准；培养方案（本专业）是学分的权威来源，
/// 因此这里把培养方案里的课程做成「课程代码 / 课程名 → 学分」索引。
///
/// 注意：**同名的课在不同专业学分不同**（如「计算机网络」在软件工程方案里
/// 是 2.0、在计算机科学与技术方案里是 4.0），所以索引只能由**本专业**那一份
/// 培养方案构建（见 ge_providers.dart 的 geCurriculumIndexProvider）。
library;

import '../../ims/curriculum/domain/curriculum.dart';
import '../domain/ge_models.dart';

/// 培养方案里的一条课程条目（构建索引的最小输入）。
typedef GePlanCourse = ({String code, String name, double credits});

/// 培养方案学分索引（只读）。
class GeCurriculumIndex {
  /// 方案所属专业名（展示用，如「计算机科学与技术」）；空索引时为 ''。
  final String majorName;

  final Map<String, double> _byCode;
  final Map<String, double> _byName;

  const GeCurriculumIndex._({
    required this.majorName,
    required Map<String, double> byCode,
    required Map<String, double> byName,
  }) : _byCode = byCode,
       _byName = byName;

  /// 空索引：未登录 / 学籍缺失 / 专业未匹配 / 拉取失败时的兜底（不阻塞界面）。
  const GeCurriculumIndex.empty()
    : majorName = '',
      _byCode = const {},
      _byName = const {};

  /// 由课程条目构建（学分 ≤ 0 的条目忽略）。
  factory GeCurriculumIndex.fromCourses({
    required String majorName,
    required Iterable<GePlanCourse> courses,
  }) {
    final byCode = <String, double>{};
    final byName = <String, double>{};
    for (final course in courses) {
      final credit = course.credits;
      if (credit <= 0) continue;
      final code = course.code.trim();
      if (code.isNotEmpty) byCode[code] = credit;
      final name = _normalize(course.name);
      if (name.isNotEmpty) byName[name] = credit;
    }
    return GeCurriculumIndex._(
      majorName: majorName,
      byCode: byCode,
      byName: byName,
    );
  }

  /// 由培养方案模型构建。
  factory GeCurriculumIndex.fromCurriculum(Curriculum curriculum) =>
      GeCurriculumIndex.fromCourses(
        majorName: curriculum.majorName,
        courses: [
          for (final c in curriculum.courses)
            (code: c.code, name: c.name, credits: c.credit),
        ],
      );

  bool get isEmpty => _byCode.isEmpty && _byName.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// 可按课程代码命中的课程数。
  int get codeCount => _byCode.length;

  /// 可按课程名命中的课程数。
  int get nameCount => _byName.length;

  /// 取培养方案学分：优先课程代码精确匹配，其次课程名（忽略空白与大小写）。
  ///
  /// 返回 null 表示培养方案里没有这门课（如慕课/任选课），调用方应回退到
  /// 课程自身记录的学分。
  double? creditsOf({String code = '', required String name}) {
    final c = code.trim();
    if (c.isNotEmpty) {
      final hit = _byCode[c];
      if (hit != null && hit > 0) return hit;
    }
    final n = _normalize(name);
    if (n.isEmpty) return null;
    final hit = _byName[n];
    return (hit != null && hit > 0) ? hit : null;
  }

  static String _normalize(String s) =>
      s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

/// 课程的有效学分（加权平均用）：培养方案命中 → 用培养方案学分，否则用
/// 课程自身记录的学分。[fromCurriculum] 供界面标注学分来源。
({double credits, bool fromCurriculum}) geEffectiveCredits(
  GeCurriculumIndex index,
  GeCourse course,
) {
  final fromPlan = index.creditsOf(code: course.courseCode, name: course.name);
  if (fromPlan != null && fromPlan > 0) {
    return (credits: fromPlan, fromCurriculum: true);
  }
  return (credits: course.credits, fromCurriculum: false);
}
