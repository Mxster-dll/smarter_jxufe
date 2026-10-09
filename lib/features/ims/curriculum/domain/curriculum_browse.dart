/// 培养方案**浏览态**的纯逻辑：分组 / 搜索 / 快筛 / 汇总。
///
/// 页面（`presentation/curriculum_screen.dart`）只负责画，所有「哪些课进哪一组、
/// 合计多少学分」都在这里算 —— 无 IO、无 `BuildContext`，可以直接单测
/// （守卫 `test/curriculum_browse_test.dart`）。
///
/// 三种分组形态（用户 2026-10-09 要求「支持各种显示方式，例如按分类聚合、
/// 按开课时间聚合」）：
/// - [CurriculumGroupMode.category]：课程大类 → 二级分类（教务原顺序）；
/// - [CurriculumGroupMode.term]：开课学期（`学年学期` 列，按学年学期先后排，
///   认不出的排最后）；
/// - [CurriculumGroupMode.flat]：不分组，按教务表原顺序平铺。
///
/// 理论课程与实践环节（培养方案的第二张表）各有自己的浏览函数，因为两张表的
/// 字段完全不同（课程有学分/学时/修读性质；环节有周数/环节类别）。
library;

import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_requirement.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_terms.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';

/// 分组形态。
enum CurriculumGroupMode {
  /// 按课程大类 → 二级分类聚合。
  category,

  /// 按开课学期（`学年学期`）聚合。
  term,

  /// 平铺（不分组，教务表原顺序）。
  flat,
}

/// 分组形态的界面名（分段控件用）。
extension CurriculumGroupModeLabel on CurriculumGroupMode {
  String get label => switch (this) {
    CurriculumGroupMode.category => '按分类',
    CurriculumGroupMode.term => '按开课学期',
    CurriculumGroupMode.flat => '平铺',
  };
}

/// 快速筛选。
enum CurriculumQuickFilter { all, compulsory, elective, core }

/// 快速筛选的界面名。
extension CurriculumQuickFilterLabel on CurriculumQuickFilter {
  String get label => switch (this) {
    CurriculumQuickFilter.all => '全部',
    CurriculumQuickFilter.compulsory => '必修',
    CurriculumQuickFilter.elective => '选修 / 限选',
    CurriculumQuickFilter.core => '主干课程',
  };
}

/// 修读性质的短标签（徽标用）：`必修课` → `必修`，`限选课` → `限选`。
///
/// 只削掉结尾的「课」字，其余（`卓越型` / `专业方向` / `未知`…）原样显示 ——
/// 教务以后加了新性质也不会被这里吃掉。
String curriculumRequirementShort(CourseRequirement requirement) {
  final name = requirement.displayName;
  return name.endsWith('课') && name.length > 1
      ? name.substring(0, name.length - 1)
      : name;
}

/// 一门课 + 它在教务表里的行号与开课学期。
class CurriculumCourseItem {
  final Course course;

  /// 教务表行号（1 起）—— 搜索过滤后仍保留原行号，便于回教务核对。
  final int index;

  /// `学年学期` 原文（空 = 未排定）。
  final String rawSemester;

  const CurriculumCourseItem({
    required this.course,
    required this.index,
    this.rawSemester = '',
  });

  /// 界面标签（认不出 / 空 → [kCurriculumTermUnassigned]）。
  String get termLabel => curriculumTermLabel(rawSemester);

  /// 展开态的稳定键（行号 + 代码 + 课名；同一门课重复出现也不会串）。
  String get key => '$index|${course.code}|${course.name}';

  /// 学期短码（认不出 → 空串）。
  String get termCode => curriculumTermCode(rawSemester);

  /// 学期排序键。
  int get termSortKey => curriculumTermSortKey(rawSemester);

  /// 搜索命中判据：**课名 / 课程代码 / 课程大类 / 二级分类**（都忽略大小写与空白）。
  ///
  /// 带上类别是为了「搜『专业方向』就能把那一类挑出来」这种用法。
  bool matches(String q) {
    if (q.isEmpty) return true;
    return course.name.toLowerCase().contains(q) ||
        course.code.toLowerCase().contains(q) ||
        course.mainCategory.toLowerCase().contains(q) ||
        course.subCategory.toLowerCase().contains(q);
  }
}

/// 一组课（二级分类 / 开课学期里的一个大类 / 平铺时的唯一一组）。
class CurriculumGroup {
  final String title;
  final List<CurriculumCourseItem> items;

  const CurriculumGroup({required this.title, required this.items});

  int get count => items.length;

  double get credits =>
      items.fold<double>(0, (sum, item) => sum + item.course.credit);
}

/// 一个大节（课程大类 / 一个开课学期 / 平铺时的「全部课程」）。
class CurriculumSection {
  final String title;

  /// 学期短码（仅按开课学期聚合时有值）；界面画在标题旁边。
  final String? code;

  final List<CurriculumGroup> groups;

  const CurriculumSection({
    required this.title,
    required this.groups,
    this.code,
  });

  int get count => groups.fold<int>(0, (sum, g) => sum + g.count);

  double get credits => groups.fold<double>(0, (sum, g) => sum + g.credits);
}

/// 浏览结果（分组后的树 + 合计）。
class CurriculumBrowseResult {
  final List<CurriculumSection> sections;

  /// 整份方案的合计（**不受搜索 / 筛选影响**）。
  final int totalCount;
  final double totalCredits;

  /// 当前搜索 / 筛选命中的合计。
  final int matchedCount;
  final double matchedCredits;

  /// 是否有搜索词或非「全部」的筛选（界面据此决定要不要显示「命中 N 门」）。
  final bool filtered;

  const CurriculumBrowseResult({
    required this.sections,
    required this.totalCount,
    required this.totalCredits,
    required this.matchedCount,
    required this.matchedCredits,
    required this.filtered,
  });

  bool get isEmpty => matchedCount == 0;
}

/// 理论课程的浏览：分组 + 搜索 + 快筛。
///
/// [semesters] 与 [courses] **同序同长**（来自 `CurriculumTerms.semesters`）；
/// 缺失 / 长度对不上时按「全部未排定」处理（**不要**编学期）。
CurriculumBrowseResult browseCurriculum({
  required List<Course> courses,
  List<String> semesters = const [],
  CurriculumGroupMode mode = CurriculumGroupMode.category,
  String query = '',
  CurriculumQuickFilter filter = CurriculumQuickFilter.all,
}) {
  final items = [
    for (var i = 0; i < courses.length; i++)
      CurriculumCourseItem(
        course: courses[i],
        index: i + 1,
        rawSemester: i < semesters.length ? semesters[i] : '',
      ),
  ];

  final q = query.trim().toLowerCase();
  final matched = [
    for (final item in items)
      if (item.matches(q) && _keepByFilter(item.course, filter)) item,
  ];

  final sections = switch (mode) {
    CurriculumGroupMode.category => _groupByCategory(matched),
    CurriculumGroupMode.term => _groupByTerm(matched),
    CurriculumGroupMode.flat => [
      CurriculumSection(
        title: '全部课程',
        groups: [CurriculumGroup(title: '', items: matched)],
      ),
    ],
  };

  final totalCredits = items.fold<double>(
    0,
    (sum, item) => sum + item.course.credit,
  );
  final matchedCredits = matched.fold<double>(
    0,
    (sum, item) => sum + item.course.credit,
  );

  return CurriculumBrowseResult(
    sections: sections,
    totalCount: items.length,
    totalCredits: totalCredits,
    matchedCount: matched.length,
    matchedCredits: matchedCredits,
    filtered: q.isNotEmpty || filter != CurriculumQuickFilter.all,
  );
}

bool _keepByFilter(Course course, CurriculumQuickFilter filter) =>
    switch (filter) {
      CurriculumQuickFilter.all => true,
      CurriculumQuickFilter.compulsory =>
        course.requirement == CourseRequirement.compulsory,
      // 「选修 / 限选」= **非必修**（限选、任选、专业方向、卓越型…都算选修侧）
      CurriculumQuickFilter.elective =>
        course.requirement != CourseRequirement.compulsory,
      CurriculumQuickFilter.core =>
        course.importance == CourseImportance.core,
    };

/// 大类 → 二级分类（都按**首次出现**的顺序，与教务表一致）。
List<CurriculumSection> _groupByCategory(List<CurriculumCourseItem> items) {
  final order = <String>[];
  final byCategory = <String, List<CurriculumCourseItem>>{};
  for (final item in items) {
    final key = _orUnclassified(item.course.mainCategory);
    if (!byCategory.containsKey(key)) order.add(key);
    byCategory.putIfAbsent(key, () => []).add(item);
  }

  return [
    for (final category in order)
      CurriculumSection(
        title: category,
        groups: _subGroups(byCategory[category]!),
      ),
  ];
}

/// 在同一批课里按二级分类再分一层。
List<CurriculumGroup> _subGroups(List<CurriculumCourseItem> items) {
  final order = <String>[];
  final bySub = <String, List<CurriculumCourseItem>>{};
  for (final item in items) {
    final key = _orUnclassified(item.course.subCategory);
    if (!bySub.containsKey(key)) order.add(key);
    bySub.putIfAbsent(key, () => []).add(item);
  }
  return [
    for (final sub in order) CurriculumGroup(title: sub, items: bySub[sub]!),
  ];
}

/// 开课学期 → 课程大类（学期按学年学期先后排，认不出的排最后）。
///
/// 二级分类不再单独分层：行本身会把它写出来（`[代码] · 二级分类 · 考核方式`），
/// 这里用大类分一层，学期里「公共课 / 专业教育课 / 通识教育课」一眼可分。
List<CurriculumSection> _groupByTerm(List<CurriculumCourseItem> items) {
  final byTerm = <String, List<CurriculumCourseItem>>{};
  for (final item in items) {
    byTerm.putIfAbsent(item.termLabel, () => []).add(item);
  }

  final titles = byTerm.keys.toList()
    ..sort((a, b) {
      final ka = curriculumTermSortKey(
        byTerm[a]!.first.rawSemester,
      );
      final kb = curriculumTermSortKey(byTerm[b]!.first.rawSemester);
      if (ka != kb) return ka.compareTo(kb);
      // 同一学期键（含全部「未排定」）保持首次出现顺序，排序必须稳定。
      return items
          .indexWhere((i) => i.termLabel == a)
          .compareTo(items.indexWhere((i) => i.termLabel == b));
    });

  return [
    for (final title in titles)
      CurriculumSection(
        title: title,
        code: byTerm[title]!.first.termCode.isEmpty
            ? null
            : byTerm[title]!.first.termCode,
        groups: _groupsBy(byTerm[title]!, (c) => c.mainCategory),
      ),
  ];
}

/// 按某个键分组（保持首次出现顺序）。
List<CurriculumGroup> _groupsBy(
  List<CurriculumCourseItem> items,
  String Function(Course) keyOf,
) {
  final order = <String>[];
  final byKey = <String, List<CurriculumCourseItem>>{};
  for (final item in items) {
    final key = _orUnclassified(keyOf(item.course));
    if (!byKey.containsKey(key)) order.add(key);
    byKey.putIfAbsent(key, () => []).add(item);
  }
  return [
    for (final key in order) CurriculumGroup(title: key, items: byKey[key]!),
  ];
}

String _orUnclassified(String raw) =>
    raw.trim().isEmpty ? '未分类' : raw.trim();

/// 培养方案的总览数字（指标卡用）。
class CurriculumSummary {
  final int totalCount;
  final double totalCredits;

  /// 必修。
  final int compulsoryCount;
  final double compulsoryCredits;

  /// 非必修（选修 / 限选 / 任选…）—— 界面上写「选修 / 限选」。
  final int otherCount;
  final double otherCredits;

  /// 主干课程门数（`课程地位 = 主干课程`）。
  final int coreCount;

  /// 各大类的学分（按首次出现顺序，画占比条用）。
  final List<({String label, double credits})> categoryShares;

  const CurriculumSummary({
    required this.totalCount,
    required this.totalCredits,
    required this.compulsoryCount,
    required this.compulsoryCredits,
    required this.otherCount,
    required this.otherCredits,
    required this.coreCount,
    required this.categoryShares,
  });
}

/// 算总览：门数 / 学分 / 必修与非必修 / 主干 / 大类占比。
CurriculumSummary summarizeCurriculum(List<Course> courses) {
  var compulsoryCount = 0;
  var compulsoryCredits = 0.0;
  var otherCount = 0;
  var otherCredits = 0.0;
  var coreCount = 0;
  var totalCredits = 0.0;
  final order = <String>[];
  final shares = <String, double>{};

  for (final course in courses) {
    totalCredits += course.credit;
    if (course.requirement == CourseRequirement.compulsory) {
      compulsoryCount++;
      compulsoryCredits += course.credit;
    } else {
      otherCount++;
      otherCredits += course.credit;
    }
    if (course.importance == CourseImportance.core) coreCount++;

    final label = _orUnclassified(course.mainCategory);
    if (!shares.containsKey(label)) order.add(label);
    shares[label] = (shares[label] ?? 0) + course.credit;
  }

  return CurriculumSummary(
    totalCount: courses.length,
    totalCredits: totalCredits,
    compulsoryCount: compulsoryCount,
    compulsoryCredits: compulsoryCredits,
    otherCount: otherCount,
    otherCredits: otherCredits,
    coreCount: coreCount,
    categoryShares: [
      for (final label in order) (label: label, credits: shares[label]!),
    ],
  );
}

// ─── 实践环节（培养方案第二张表）─────────────────────────────────────

/// 两张表**都出现**的条目数（按环节代码、其次按名称对上理论课程）。
///
/// §13.6 记过口径：一门课若理论课程与实践环节都有，**不重复计入**、两张表各算各的。
/// 这里只统计「有几条重叠」，供页面脚注如实说明，不做去重。
int curriculumPracticeOverlap({
  required List<Course> courses,
  required PracticeCurriculum practice,
}) {
  final codes = practice.codes;
  final names = practice.names;
  var overlap = 0;
  for (final course in courses) {
    final hitByCode = course.code.isNotEmpty && codes.contains(course.code);
    final hitByName = course.name.isNotEmpty && names.contains(course.name);
    if (hitByCode || hitByName) overlap++;
  }
  return overlap;
}

/// 实践环节的一组（环节类别 / 开课学期 / 平铺时的唯一一组）。
class PracticeGroup {
  final String title;
  final List<PracticeStage> stages;

  const PracticeGroup({required this.title, required this.stages});

  int get count => stages.length;

  double get credits => stages.fold<double>(0, (sum, s) => sum + s.credit);
}

/// 实践环节的浏览结果。
class PracticeBrowseResult {
  final List<PracticeGroup> groups;
  final int totalCount;
  final double totalCredits;
  final int matchedCount;
  final double matchedCredits;
  final bool filtered;

  const PracticeBrowseResult({
    required this.groups,
    required this.totalCount,
    required this.totalCredits,
    required this.matchedCount,
    required this.matchedCredits,
    required this.filtered,
  });

  bool get isEmpty => matchedCount == 0;
}

/// 实践环节的浏览：分组 + 搜索 + 快筛。
///
/// ⚠ **快筛在实践环节上的语义**（有意为之，不是漏了）：
/// 实践环节整张表都是必修性质、也没有「课程地位」，所以
/// [CurriculumQuickFilter.compulsory] 保留全部、[CurriculumQuickFilter.elective]
/// 与 [CurriculumQuickFilter.core] 会把它**整个筛掉** —— 后者是实话：
/// 这些环节既不是选修、也不是主干课程。
PracticeBrowseResult browsePractice({
  required List<PracticeStage> stages,
  CurriculumGroupMode mode = CurriculumGroupMode.category,
  String query = '',
  CurriculumQuickFilter filter = CurriculumQuickFilter.all,
}) {
  final q = query.trim().toLowerCase();
  final matched = [
    for (final stage in stages)
      if (_keepPracticeByFilter(filter) && _practiceMatches(stage, q)) stage,
  ];

  final groups = switch (mode) {
    CurriculumGroupMode.category => _practiceGroupsBy(
      matched,
      (s) => _orUnclassified(s.category),
      sortByTerm: false,
    ),
    CurriculumGroupMode.term => _practiceGroupsBy(
      matched,
      (s) => curriculumTermLabel(s.semester),
      sortByTerm: true,
    ),
    CurriculumGroupMode.flat => [
      PracticeGroup(title: '', stages: matched),
    ],
  };

  return PracticeBrowseResult(
    groups: groups,
    totalCount: stages.length,
    totalCredits: stages.fold<double>(0, (sum, s) => sum + s.credit),
    matchedCount: matched.length,
    matchedCredits: matched.fold<double>(0, (sum, s) => sum + s.credit),
    filtered: q.isNotEmpty || filter != CurriculumQuickFilter.all,
  );
}

bool _keepPracticeByFilter(CurriculumQuickFilter filter) => switch (filter) {
  CurriculumQuickFilter.all || CurriculumQuickFilter.compulsory => true,
  CurriculumQuickFilter.elective || CurriculumQuickFilter.core => false,
};

bool _practiceMatches(PracticeStage stage, String q) {
  if (q.isEmpty) return true;
  return stage.name.toLowerCase().contains(q) ||
      stage.category.toLowerCase().contains(q) ||
      stage.semester.toLowerCase().contains(q);
}

List<PracticeGroup> _practiceGroupsBy(
  List<PracticeStage> stages,
  String Function(PracticeStage) keyOf, {
  required bool sortByTerm,
}) {
  final order = <String>[];
  final byKey = <String, List<PracticeStage>>{};
  for (final stage in stages) {
    final key = keyOf(stage);
    if (!byKey.containsKey(key)) order.add(key);
    byKey.putIfAbsent(key, () => []).add(stage);
  }

  if (sortByTerm) {
    order.sort((a, b) {
      final ka = curriculumTermSortKey(byKey[a]!.first.semester);
      final kb = curriculumTermSortKey(byKey[b]!.first.semester);
      if (ka != kb) return ka.compareTo(kb);
      return stages
          .indexWhere((s) => keyOf(s) == a)
          .compareTo(stages.indexWhere((s) => keyOf(s) == b));
    });
  }

  return [
    for (final key in order) PracticeGroup(title: key, stages: byKey[key]!),
  ];
}
