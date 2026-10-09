/// 「已修学分 vs 毕业要求」的推算口径 —— 毕业学分页的唯一算法。
///
/// 三条链路拼起来：
/// 1. **必修进度** = 本专业培养方案里 `requirement == 必修课` 的全部课程，
///    要求学分 = 这些课的学分之和，已修 = 成绩里匹配上的那些课的获得学分之和。
/// 2. **选修进度** = 教务「毕业学分要求」表（`DataTable.jsp?tableId=6033`）逐项算，
///    每一项自己去培养方案 / 通识课程库里找「哪些课能顶这一项」：
///    - `公共外语选修课` → 培养方案 `公共外语课` **且为选修**的课
///    - `学科开放选修课` → 培养方案 `学科开放课`
///    - `专业方向选修课` → 培养方案 `专业方向课`
///    - `美育 / 科学、技术与方法 / 历史、政治与社会 / 哲学、思维与语言`
///      → **通识课程库**里的同名模块（培养方案在这四项上只有占位课）
/// 3. **未归类** = 上面两条都没算进去的课，照实列出来并说明原因，**不硬塞**。
///
/// ⚠ 四条硬口径：
/// - **只认「获得学分」**（成绩表的 `earnedCredit`）：不及格记 0，重修同码多条
///   取获得学分最高的那条，再按学期取新。
/// - **培养方案里的必修课不再计入任何选修项**（`写作与沟通 I` 在培养方案里
///   属「哲学、思维与语言」但性质是必修，它顶的是必修进度，不是那 2 学分通识选修）。
/// - **各项溢出互不抵扣**：教务表把每一项列成独立要求，专业方向多修 5 学分
///   不能顶美育的 2 学分。合计「还差」= 各项 `max(0, 要求 - 已修)` 之和。
/// - **认不出就不猜**：要求项名归一化后仍对不上任何规则的，只显示要求学分；
///   课程归不到任何被要求的类别的，进「未归类」并写明理由。
///
/// 真实数据对拍见 `test/graduation_credit_progress_test.dart` 的台账用例。
library;

import 'package:smarter_jxufe/features/ims/course/data/models/course.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_requirement.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/general_education_catalog.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/graduation_requirement.dart';

/// 浮点比较容差（学分是 .5 的倍数，1e-6 足够）。
const double _eps = 1e-6;

/// **明确不计入总学分**的课程 —— 学校文件白纸黑字规定的。
///
/// 出处（`assets/rules/text/r03a.md`，2024 版本科人才培养方案修订指导意见）：
/// > 大学生安全教育**不计入总学分**，但安排 16 学时必修课，作为毕业资格审核的依据
/// 又见同文件的总学分要求表脚注：「大学生安全教育作为所有专业第一学期必修课，
/// 不计入总学分。」
///
/// 实测后果：它不在任何专业的培养方案里（既非理论课程也非实践环节），
/// 成绩里却有 1 学分 —— 从前它落进「未归类」并显示成因「两边都没有」，
/// 那个理由是**不完整**的：不是数据缺失，是学校规定不算。
const kNotCountedCreditCourses = <String>{'大学生安全教育'};

/// 这门课是否「学校规定不计入总学分」（先按名，再按码兜底）。
bool isNotCountedCreditCourse({String code = '', String name = ''}) {
  if (kNotCountedCreditCourses.contains(name.trim())) return true;
  // 该课在教务里的稳定代码（实测 1003000011，通识库与培养方案里都没有它）
  return code.trim() == '1003000011';
}

/// 一门「已修课程」——进算法的输入（成绩页的 `Grade` 在数据层映射成它）。
class TakenCourse {
  /// 课程代码（可能为空 —— 成绩表偶有缺码的行）。
  final String code;

  /// 课程名称。
  final String name;

  /// 课程学分。
  final double credit;

  /// **获得学分**（不及格为 0；解析不出来按 0）。
  final double earned;

  /// 学期码，如 `251`（字典序即时间序）。
  final String semester;

  /// 成绩分值（`优秀`/`良好` 这类等级制解析不出来 → null）。
  final double? score;

  const TakenCourse({
    required this.code,
    required this.name,
    required this.credit,
    required this.earned,
    this.semester = '',
    this.score,
  });

  /// **挂科**：成绩单上有这门课（已考核），但一分学分都没拿到。
  ///
  /// 2026-10-08 加（用户原话：「不及格的话即使已修也算未获得学分，并且我希望有
  /// UI 提示」）。判据 = `学分 > 0 且 获得学分 = 0` —— 成绩表里出现的行都是
  /// **已考核**的，所以这不会把「还在修、没出分」误判成挂科（那些走课表那条路，
  /// 根本不在这里）。
  bool get failed => credit > _eps && earned <= _eps;
}

/// 进度里出现的一门课。
class CreditProgressCourse {
  final String code;
  final String name;
  final double credit;
  final double earned;
  final String semester;

  /// 成绩分值（等级制解析不出来为 null）—— 挂科行上屏「58 分」用。
  final double? score;

  const CreditProgressCourse({
    required this.code,
    required this.name,
    required this.credit,
    required this.earned,
    this.semester = '',
    this.score,
  });

  bool get passed => earned > _eps;

  /// 挂科（见 [TakenCourse.failed]）。
  bool get failed => credit > _eps && earned <= _eps;

  /// 分值的上屏文本（`58` / `58.5` / `—`）。
  String get scoreText => score == null ? '—' : creditTextOf(score!);
}

/// 学分数值的上屏文本（整数不留小数位：`2.00 → 2`、`1.25 → 1.25`）。
///
/// 放在 domain 里是因为**两个模块都要用**（进度文本与挂科分值），
/// 界面的 `creditText` 转发到这里，免得两处各写一套取整规则。
String creditTextOf(double value) =>
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// 没被算进任何要求项的一门课 + **为什么**。
class UnmatchedCourse {
  final CreditProgressCourse course;

  /// 给用户看的一句话原因。
  final String reason;

  const UnmatchedCourse({required this.course, required this.reason});
}

/// 教务「毕业学分要求」表里的一项，配上算出来的已修 / 还差。
class CreditProgressItem {
  /// 显示名（教务表里的项目名原文）。
  final String title;

  /// 教务要求的学分。
  final double required;

  /// 计入本项的**真实**获得学分（可能超出 [required]，不截顶）。
  final double earned;

  /// **已选未考**的学分（本学期课表里有、成绩还没出）。
  ///
  /// 2026-10-08 加（用户原话：「用更更浅一点的红色，标识已选但是未考试的学分部分」）。
  /// 它**不计入** [counted]，也**不冲抵** [remaining] —— [remaining] 仍旧只按
  /// 「已拿到手的学分」算缺口，界面另外标一条「另有 N 学分在修」。
  final double inProgress;

  /// 计入本项的课程。
  final List<CreditProgressCourse> courses;

  /// 已选未考的课程。
  final List<CreditProgressCourse> inProgressCourses;

  /// 本项的判定口径说明（一句话，上屏用）。
  final String rule;

  /// 培养方案里能顶这一项的课程总数 / 总学分（0 表示没有可用课程池）。
  final int poolCount;
  final double poolCredits;

  /// 要求项是否被识别出口径；false = 只能显示要求值。
  final bool recognized;

  const CreditProgressItem({
    required this.title,
    required this.required,
    required this.earned,
    required this.courses,
    required this.rule,
    this.inProgress = 0,
    this.inProgressCourses = const [],
    this.poolCount = 0,
    this.poolCredits = 0,
    this.recognized = true,
  });

  /// 计入本项、用于算「还差」的学分（截顶到 [required]）。
  double get counted => earned > required + _eps ? required : earned;

  /// 在修学分里**本项还装得下**的那部分（截顶到 要求 − 已修）。
  double get inProgressCounted {
    final room = required - counted;
    if (room <= _eps) return 0;
    return inProgress > room ? room : inProgress;
  }

  /// 还差多少学分（已满足为 0）。
  double get remaining {
    final gap = required - earned;
    return gap > _eps ? gap : 0;
  }

  /// 超出要求、且**不能**抵扣其它项的学分。
  double get overflow {
    final over = earned - required;
    return over > _eps ? over : 0;
  }

  bool get satisfied => remaining <= _eps;

  /// 0~1 的完成度（无要求时为 0）。
  double get ratio {
    if (required <= _eps) return satisfied ? 1 : 0;
    final r = counted / required;
    if (r < 0) return 0;
    if (r > 1) return 1;
    return r;
  }

  /// 0~1 的「在修」占比（画在进度条 [ratio] 之后那一段）。
  double get inProgressRatio {
    if (required <= _eps) return 0;
    final r = inProgressCounted / required;
    if (r < 0) return 0;
    if (r > 1) return 1;
    return r;
  }
}

/// 一门必修课的状态。
class CompulsoryCourseState {
  final String code;
  final String name;
  final double credit;
  final double earned;

  /// 已选未考（本学期在修，还没出成绩）。
  final bool inProgress;

  /// 培养方案里的二级分类（公共外语课 / 学科基础课 / …）。
  final String category;
  final String semester;

  /// 成绩分值（等级制为 null）。
  final double? score;

  /// **考核过**没有（成绩单上有这门课）。
  ///
  /// ⚠ 这是「挂科」与「还没修」的分水岭：两者 `earned` 都是 0，
  /// 只看 `earned` 会把整张培养方案里所有没修的课都判成挂科
  /// （2026-10-08 实测踩过：50 门必修课全变「挂科」）。
  final bool attempted;

  const CompulsoryCourseState({
    required this.code,
    required this.name,
    required this.credit,
    required this.earned,
    required this.category,
    this.inProgress = false,
    this.semester = '',
    this.score,
    this.attempted = false,
  });

  bool get done => earned > _eps;

  /// 挂科：**考核过**但一分没拿到（见 [TakenCourse.failed]）。
  bool get failed => attempted && credit > _eps && earned <= _eps;

  /// 分值的上屏文本。
  String get scoreText => score == null ? '—' : creditTextOf(score!);
}

/// 必修课进度。
class CompulsoryCreditProgress {
  /// 培养方案里必修课的学分之和。
  final double required;

  /// 已修到的学分。
  final double earned;

  /// 已选未考（本学期在修）的学分。
  final double inProgress;

  /// 全部必修课（含未修的），按培养方案原顺序。
  final List<CompulsoryCourseState> courses;

  const CompulsoryCreditProgress({
    required this.required,
    required this.earned,
    required this.courses,
    this.inProgress = 0,
  });

  static const CompulsoryCreditProgress none = CompulsoryCreditProgress(
    required: 0,
    earned: 0,
    courses: [],
  );

  /// 是否拿到了培养方案（false 时 [required] 为 0，界面要说「拿不到」而不是「已修满」）。
  bool get available => courses.isNotEmpty;

  int get totalCount => courses.length;

  int get doneCount {
    var n = 0;
    for (final c in courses) {
      if (c.done) n++;
    }
    return n;
  }

  List<CompulsoryCourseState> get doneCourses =>
      [for (final c in courses) if (c.done) c];

  List<CompulsoryCourseState> get pendingCourses =>
      [for (final c in courses) if (!c.done) c];

  double get remaining {
    final gap = required - earned;
    return gap > _eps ? gap : 0;
  }

  bool get satisfied => available && remaining <= _eps;

  double get ratio {
    if (required <= _eps) return available && satisfied ? 1 : 0;
    final r = earned / required;
    if (r < 0) return 0;
    if (r > 1) return 1;
    return r;
  }

  /// 「在修」占比（截顶到 要求 − 已修）。
  double get inProgressRatio {
    if (required <= _eps) return 0;
    final room = required - earned;
    final v = room <= _eps ? 0.0 : (inProgress > room ? room : inProgress);
    return (v / required).clamp(0.0, 1.0);
  }
}

/// 一条实践环节的状态（培养方案第二张表：`pyfa.sjhj.html` / `tableId=2509`）。
class PracticeStageState {
  final String code;
  final String name;

  /// 环节类别（军训 / 科研创新实践 / 实习实训 / 论文设计）。
  final String category;
  final double credit;
  final double earned;

  /// 已选未考（本学期在修，还没出成绩）。
  final bool inProgress;

  /// **考核过**没有（见 [CompulsoryCourseState.attempted]）。
  final bool attempted;
  final String semester;

  const PracticeStageState({
    required this.code,
    required this.name,
    required this.credit,
    required this.earned,
    this.category = '',
    this.inProgress = false,
    this.semester = '',
    this.attempted = false,
  });

  bool get done => earned > _eps;

  /// 挂科：考核过但一分没拿到（见 [TakenCourse.failed]）。
  bool get failed => attempted && credit > _eps && earned <= _eps;
}

/// 实践环节进度。
///
/// 2026-10-08 加：此前只接了「理论课程」那张表，于是 **军事训练**（只挂在实践
/// 环节里）落进了「未归类」。用户原话：「培养方案还有『实践环节』，而军事训练
/// 就属于这一部分」。
class PracticeCreditProgress {
  /// 表内各项学分之和（本专业表为准）。
  final double required;
  final double earned;

  /// 已选未考（本学期在修）的学分。
  final double inProgress;
  final List<PracticeStageState> stages;

  /// 培养方案标识；拿不到表时为 null。
  final String? label;

  const PracticeCreditProgress({
    required this.required,
    required this.earned,
    required this.stages,
    this.inProgress = 0,
    this.label,
  });

  static const PracticeCreditProgress none = PracticeCreditProgress(
    required: 0,
    earned: 0,
    stages: [],
  );

  bool get available => stages.isNotEmpty;

  int get totalCount => stages.length;

  int get doneCount {
    var n = 0;
    for (final s in stages) {
      if (s.done) n++;
    }
    return n;
  }

  List<PracticeStageState> get doneStages =>
      [for (final s in stages) if (s.done) s];

  List<PracticeStageState> get pendingStages =>
      [for (final s in stages) if (!s.done) s];

  double get remaining {
    final gap = required - earned;
    return gap > _eps ? gap : 0;
  }

  bool get satisfied => available && remaining <= _eps;

  double get ratio {
    if (required <= _eps) return available && satisfied ? 1 : 0;
    final r = earned / required;
    if (r < 0) return 0;
    if (r > 1) return 1;
    return r;
  }

  /// 「在修」占比（截顶到 要求 − 已修）。
  double get inProgressRatio {
    if (required <= _eps) return 0;
    final room = required - earned;
    final v = room <= _eps ? 0.0 : (inProgress > room ? room : inProgress);
    return (v / required).clamp(0.0, 1.0);
  }
}

/// 整页的推算结果。
class GraduationCreditProgress {
  final CompulsoryCreditProgress compulsory;

  /// 实践环节（培养方案第二张表）。
  final PracticeCreditProgress practice;

  /// 教务要求表的各项（不含「合计」行），按教务给的顺序。
  final List<CreditProgressItem> electives;

  /// 两条链路都没算进去的课。
  final List<UnmatchedCourse> unmatched;

  /// **学校规定不计入总学分**的课（如大学生安全教育）—— 与 [unmatched] 分开列，
  /// 理由不同：这些不是「归不了类」，是「规定了不算」。
  final List<CreditProgressCourse> notCounted;

  /// 全部已修学分（含未归类）—— 与成绩页的合计对得上。
  final double earnedTotal;

  /// 培养方案标识（`2025 · 计算机与人工智能学院 · 计算机科学与技术`）；拿不到为 null。
  final String? curriculumLabel;

  /// 通识课程库的适用范围（界面用来标注「按哪张表查的」）。
  final GeneralEducationScope? catalogScope;

  /// 口径备注（逐条上屏）。
  final List<String> notes;

  const GraduationCreditProgress({
    required this.compulsory,
    required this.electives,
    required this.unmatched,
    required this.earnedTotal,
    this.practice = PracticeCreditProgress.none,
    this.notCounted = const [],
    this.curriculumLabel,
    this.catalogScope,
    this.notes = const [],
  });

  static const GraduationCreditProgress empty = GraduationCreditProgress(
    compulsory: CompulsoryCreditProgress.none,
    electives: [],
    unmatched: [],
    earnedTotal: 0,
  );

  /// 「学校规定不计入总学分」那些课的学分之和。
  double get notCountedCredits =>
      notCounted.fold(0.0, (s, c) => s + c.earned);

  /// **挂科的课**（有成绩、但学分一分没拿到）。
  ///
  /// 2026-10-08 加。挂科**既不算已修、也不算在修** —— 它占着培养方案的位置，
  /// 但没有产生任何学分，所以「还差」里仍然算它一份。重修通过后才消失。
  List<CreditProgressCourse> get failedCourses {
    final out = <CreditProgressCourse>[];
    for (final c in compulsory.courses) {
      if (c.failed) {
        out.add(
          CreditProgressCourse(
            code: c.code,
            name: c.name,
            credit: c.credit,
            earned: c.earned,
            semester: c.semester,
            score: c.score,
          ),
        );
      }
    }
    for (final s in practice.stages) {
      if (s.failed) {
        out.add(
          CreditProgressCourse(
            code: s.code,
            name: s.name,
            credit: s.credit,
            earned: s.earned,
            semester: s.semester,
          ),
        );
      }
    }
    for (final e in electives) {
      for (final c in e.courses) {
        if (c.failed) out.add(c);
      }
    }
    return out;
  }

  /// 挂科课程的学分之和（分母口径：这些学分**还没拿到**）。
  double get failedCredits =>
      failedCourses.fold(0.0, (s, c) => s + c.credit);

  /// 有没有挂科记录（推免页那句「无保研资格」的判据）。
  bool get hasFailed => failedCourses.isNotEmpty;

  bool get hasElectives => electives.isNotEmpty;

  /// 选修要求合计学分。
  double get electiveRequired => electives.fold(0, (sum, e) => sum + e.required);

  /// 计入各选修要求的学分之和（逐项截顶 —— 溢出互不抵扣）。
  double get electiveCounted => electives.fold(0, (sum, e) => sum + e.counted);

  /// 选修各项真实已修之和（不截顶，用于「其实修了多少」）。
  double get electiveEarned => electives.fold(0, (sum, e) => sum + e.earned);

  /// 选修还差多少学分。
  double get electiveRemaining =>
      electives.fold(0, (sum, e) => sum + e.remaining);

  List<CreditProgressItem> get satisfiedElectives =>
      [for (final e in electives) if (e.satisfied) e];

  /// 必修 + 选修「还差」合计。
  double get totalRemaining => compulsory.remaining + electiveRemaining;

  /// 必修 + 选修 + 实践环节「还差」合计（**毕业还差多少**就看它）。
  double get grandRemaining => totalRemaining + practice.remaining;

  /// 全部「已选未考」学分（本学期在修、还没出成绩）。
  ///
  /// ⚠ 它**不冲抵** [grandRemaining] —— 在修不等于拿到手，界面单独标一条。
  double get inProgressTotal =>
      compulsory.inProgress +
      practice.inProgress +
      electives.fold(0.0, (s, e) => s + e.inProgress);

  /// 未归类课程的学分之和。
  double get unmatchedCredits =>
      unmatched.fold(0, (sum, u) => sum + u.course.earned);
}

/// 一个选修要求项的判定方式。
enum ElectiveRuleKind {
  /// 培养方案 `subCategory` 命中（公共外语 / 学科开放 / 专业方向）。
  curriculumSubCategory,

  /// 通识课程库的模块。
  generalEducationModule,
}

/// 选修项的判定规则。
class ElectiveRule {
  final ElectiveRuleKind kind;

  /// 培养方案 `subCategory` 原文（[ElectiveRuleKind.curriculumSubCategory] 时用）。
  final String? subCategory;

  /// 通识模块（[ElectiveRuleKind.generalEducationModule] 时用）。
  final GeneralEducationModule? module;

  const ElectiveRule.sub(this.subCategory)
    : kind = ElectiveRuleKind.curriculumSubCategory,
      module = null;

  const ElectiveRule.module(this.module)
    : kind = ElectiveRuleKind.generalEducationModule,
      subCategory = null;

  /// 规则身份键：同一类课程只会落到同一个键上。
  String get key => switch (kind) {
    ElectiveRuleKind.curriculumSubCategory =>
      'sub:${canonicalCategoryKey(subCategory!)}',
    ElectiveRuleKind.generalEducationModule => 'module:${module!.name}',
  };

  /// 上屏用的一句话口径。
  String get ruleText => switch (kind) {
    ElectiveRuleKind.curriculumSubCategory => '培养方案「$subCategory」（选修）',
    ElectiveRuleKind.generalEducationModule => '通识课程库「${module!.label}」模块',
  };
}

/// 把教务要求项名解析成判定规则；认不出来返回 null（**不猜**）。
///
/// 教务的项目名实测形如 `2024科学、技术与方法选修2学分` / `2024学科开放选修课`，
/// 因此统一先过 [canonicalCategoryKey] 再比。
ElectiveRule? resolveElectiveRule(String requirementTitle) {
  final key = canonicalCategoryKey(requirementTitle);
  if (key.isEmpty) return null;
  switch (key) {
    case '公共外语课':
      return const ElectiveRule.sub('公共外语课');
    case '学科开放课':
      return const ElectiveRule.sub('学科开放课');
    case '专业方向课':
      return const ElectiveRule.sub('专业方向课');
  }
  for (final m in GeneralEducationModule.values) {
    if (m.canonicalKey == key) return ElectiveRule.module(m);
  }
  return null;
}

/// 一门已修课程被分到的去处。
class _Bucket {
  /// 落到某个选修规则上（键 = [ElectiveRule.key]）。
  final String? ruleKey;
  final String? unmatchedReason;

  const _Bucket.elective(this.ruleKey) : unmatchedReason = null;
  const _Bucket.unmatched(this.unmatchedReason) : ruleKey = null;

  bool get isElective => ruleKey != null;
}

/// 推算毕业学分进度。
///
/// [curriculum] 为 null（学籍 / 学院 / 专业 / 培养方案任一环拿不到）时：必修进度标记为
/// 「拿不到」，公共外语 / 学科开放 / 专业方向三项也只能显示要求值 —— 但
/// **四个通识模块仍然算得出来**（它们只依赖通识课程库 + 成绩）。
GraduationCreditProgress buildGraduationCreditProgress({
  required List<GraduationRequirement> requirements,
  required List<TakenCourse> taken,
  List<TakenCourse> inProgress = const [],
  Curriculum? curriculum,
  PracticeCurriculum? practice,
  GeneralEducationCatalog catalog = GeneralEducationCatalog.empty,
  int? cohort,
}) {
  final index = catalog.indexFor(cohort);
  final planByCode = <String, Course>{};
  final planByName = <String, Course>{};
  for (final c in curriculum?.courses ?? const <Course>[]) {
    if (c.code.isNotEmpty) planByCode.putIfAbsent(c.code, () => c);
    if (c.name.isNotEmpty) planByName.putIfAbsent(c.name, () => c);
  }
  // 实践环节表：按代码 / 名称两路建索引（那张表用的是自己的课程代码）
  final practiceByCode = <String, PracticeStage>{};
  final practiceByName = <String, PracticeStage>{};
  for (final s in practice?.stages ?? const <PracticeStage>[]) {
    if (s.code.isNotEmpty) practiceByCode.putIfAbsent(s.code, () => s);
    if (s.name.isNotEmpty) practiceByName.putIfAbsent(s.name, () => s);
  }

  // ① 去重（同码多条：取获得学分最高的；相同再取学期较新的）
  final deduped = <String, TakenCourse>{};
  for (final t in taken) {
    final key = t.code.isNotEmpty ? t.code : 'name:${t.name}';
    final prev = deduped[key];
    final better =
        prev == null ||
        t.earned > prev.earned + _eps ||
        ((t.earned - prev.earned).abs() <= _eps &&
            t.semester.compareTo(prev.semester) > 0);
    if (better) deduped[key] = t;
  }

  // ② 先把教务要求项解析成规则，只有「真的被要求」的类才建桶
  final requirementItems = [
    for (final r in requirements)
      if (!r.isTotal) r,
  ];
  final ruleOfItem = <String, ElectiveRule?>{
    for (final r in requirementItems) r.item: resolveElectiveRule(r.item),
  };
  // 规则键 → 要求项名（同一类别只应有一个要求项，先到先得）
  final itemOfRule = <String, String>{};
  final requiredSubCategories = <String>{};
  final requiredModules = <GeneralEducationModule>{};
  for (final r in requirementItems) {
    final rule = ruleOfItem[r.item];
    if (rule == null) continue;
    itemOfRule.putIfAbsent(rule.key, () => r.item);
    if (rule.kind == ElectiveRuleKind.curriculumSubCategory) {
      requiredSubCategories.add(canonicalCategoryKey(rule.subCategory!));
    } else {
      requiredModules.add(rule.module!);
    }
  }

  // ③ 逐门课分类
  final compulsoryEarnedByCode = <String, CompulsoryCourseState>{};
  /// 实践环节：代码（或 `name:` + 名称）→ 获得学分。
  final practiceEarned = <String, double>{};
  final electiveBuckets = <String, List<CreditProgressCourse>>{
    for (final r in requirementItems) r.item: [],
  };
  final unmatched = <UnmatchedCourse>[];
  final notCounted = <CreditProgressCourse>[];

  /// 已选未考（本学期在修）：只记「有没有在这条要求项里占位」，
  /// **不产生获得学分**、也不进「未归类」（还没出成绩，谈不上归错类）。
  final compulsoryInProgress = <String>{};
  final practiceInProgress = <String>{};
  final electiveInProgress = <String, List<CreditProgressCourse>>{
    for (final r in requirementItems) r.item: [],
  };

  /// 把一批课分到各桶里。[isInProgress] = true 时只登记「在修」。
  void classifyAll(Iterable<TakenCourse> list, {required bool isInProgress}) {
    for (final t in list) {
      final plan = planByCode[t.code] ?? planByName[t.name];
      final course = CreditProgressCourse(
        code: t.code,
        name: t.name,
        credit: t.credit,
        earned: t.earned,
        semester: t.semester,
        score: t.score,
      );

      if (plan != null && plan.requirement == CourseRequirement.compulsory) {
        // 必修课：留给第 ④ 步按培养方案逐门对齐。
        // ⚠ 键必须与第 ④ 步的查法一致 —— 培养方案里真有课程代码为空的行，
        // 一律用 '' 当键会让两门无码课互相顶掉，故退回课程名。
        final key = plan.code.isNotEmpty ? plan.code : 'name:${plan.name}';
        if (isInProgress) {
          compulsoryInProgress.add(key);
        } else {
          compulsoryEarnedByCode[key] = CompulsoryCourseState(
            code: plan.code,
            name: plan.name,
            credit: plan.credit,
            earned: t.earned,
            category: plan.subCategory,
            semester: t.semester,
            score: t.score,
          );
        }
        continue;
      }

      // 实践环节（第二张表）：**排在选修之前** —— 军事训练这类只挂在这张表里，
      // 不先认它就会掉进「未归类」。理论课程必修**优先于**它（若一门课两张表
      // 都有，按理论课程计入必修，且不重复计入实践环节；见 notes 的重叠提示）。
      final stage =
          practiceByCode[t.code] ??
          practiceByName[t.name] ??
          (plan == null ? null : practiceByName[plan.name]);
      if (stage != null) {
        final key = stage.code.isNotEmpty ? stage.code : 'name:${stage.name}';
        if (isInProgress) {
          practiceInProgress.add(key);
        } else {
          practiceEarned[key] = t.earned;
        }
        continue;
      }

      final bucket = _classify(
        course: course,
        plan: plan,
        index: index,
        requiredSubCategories: requiredSubCategories,
        requiredModules: requiredModules,
      );
      final title = bucket.ruleKey == null ? null : itemOfRule[bucket.ruleKey];
      if (title != null) {
        if (isInProgress) {
          electiveInProgress[title]!.add(course);
        } else {
          electiveBuckets[title]!.add(course);
        }
        continue;
      }
      // 在修课归不到类时**静默跳过**：它还没有成绩，进「未归类」只会是噪音。
      if (isInProgress) continue;
      // 学校明文规定不计入总学分的课（大学生安全教育）—— 理由要写对，
      // 别让用户以为是我们「没查到」。
      if (isNotCountedCreditCourse(code: t.code, name: t.name)) {
        notCounted.add(course);
        continue;
      }
      unmatched.add(
        UnmatchedCourse(
          course: course,
          reason:
              bucket.unmatchedReason ??
              (plan == null
                  ? '既不在本专业培养方案、也不在通识课程库里'
                  : plan.subCategory.isEmpty
                  ? '在培养方案里，但「课程类别」为空，判不出该归哪一项'
                  : '培养方案里属「${plan.subCategory}」，教务要求表里没有这一项'),
        ),
      );
    }
  }

  classifyAll(deduped.values, isInProgress: false);
  classifyAll(inProgress, isInProgress: true);

  // ④ 必修课表：以培养方案**全部必修课**为分母（未修的也要列出来）
  final compulsoryStates = <CompulsoryCourseState>[];
  for (final c in curriculum?.courses ?? const <Course>[]) {
    if (c.requirement != CourseRequirement.compulsory) continue;
    final key = c.code.isNotEmpty ? c.code : 'name:${c.name}';
    final hit = compulsoryEarnedByCode[key];
    compulsoryStates.add(
      hit == null
          ? CompulsoryCourseState(
              code: c.code,
              name: c.name,
              credit: c.credit,
              earned: 0,
              category: c.subCategory,
              inProgress: compulsoryInProgress.contains(key),
            )
          : CompulsoryCourseState(
              code: c.code,
              name: c.name,
              credit: c.credit,
              earned: hit.earned,
              category: c.subCategory,
              semester: hit.semester,
              score: hit.score,
              attempted: true,
            ),
    );
  }

  var compulsoryRequired = 0.0;
  var compulsoryEarned = 0.0;
  var compulsoryInProgressCredits = 0.0;
  for (final s in compulsoryStates) {
    compulsoryRequired += s.credit;
    compulsoryEarned += s.earned;
    if (s.inProgress) compulsoryInProgressCredits += s.credit;
  }

  // ⑤ 实践环节表：同样以**表内全部环节**为分母
  final practiceStates = <PracticeStageState>[];
  for (final s in practice?.stages ?? const <PracticeStage>[]) {
    final key = s.code.isNotEmpty ? s.code : 'name:${s.name}';
    practiceStates.add(
      PracticeStageState(
        code: s.code,
        name: s.name,
        category: s.category,
        credit: s.credit,
        earned: practiceEarned[key] ?? 0,
        inProgress: practiceInProgress.contains(key),
        // 「考核过」= 有成绩记录（`practiceEarned` 只在**非在修**那批里写）
        attempted: practiceEarned.containsKey(key),
        semester: s.semester,
      ),
    );
  }
  var practiceRequired = 0.0;
  var practiceEarnedTotal = 0.0;
  var practiceInProgressCredits = 0.0;
  for (final s in practiceStates) {
    practiceRequired += s.credit;
    practiceEarnedTotal += s.earned;
    if (s.inProgress) practiceInProgressCredits += s.credit;
  }
  // 两张表都出现的课：按理论课程计入必修，**不重复**计入实践环节。
  final overlap = [
    for (final s in practiceStates)
      if (s.code.isNotEmpty && planByCode.containsKey(s.code)) s.name,
  ];

  final electives = <CreditProgressItem>[];
  for (final r in requirementItems) {
    final rule = ruleOfItem[r.item];
    final pool = _poolOf(rule, curriculum);
    final counted = electiveBuckets[r.item]!;
    final pending = electiveInProgress[r.item]!;
    electives.add(
      CreditProgressItem(
        title: r.item,
        required: r.credit,
        earned: counted.fold(0.0, (s, c) => s + c.earned),
        courses: counted,
        inProgress: pending.fold(0.0, (s, c) => s + c.credit),
        inProgressCourses: pending,
        rule: rule?.ruleText ?? '教务要求表（本项口径未识别，只显示要求学分）',
        poolCount: pool.$1,
        poolCredits: pool.$2,
        recognized: rule != null,
      ),
    );
  }

  final notes = <String>[
    '必修 / 实践环节按培养方案两张表分别算；选修按教务「毕业学分要求」表逐项算。',
    '只计入「获得学分」的课程（不及格记 0，重修按取到学分的那次算）。',
    '各项溢出互不抵扣：某一项多修的学分不能顶另一项的缺口。',
    '实践环节（军训 / 实习实训 / 论文设计 / 科研创新实践）按学校《成绩管理办法》'
        '不计入课程加权平均成绩，但它**算毕业学分**。',
  ];
  if (curriculum == null) {
    notes.add('培养方案拿不到（学籍 / 学院 / 专业任一环缺），必修与三类专业选修无法统计。');
  }
  if (practice == null) {
    notes.add('实践环节表拿不到，军事训练 / 毕业实习这类环节无法统计。');
  } else if (overlap.isNotEmpty) {
    notes.add(
      '有 ${overlap.length} 项同时出现在理论课程与实践环节表里'
      '（${overlap.join('、')}），按理论课程计入必修，未重复计入实践环节。',
    );
  }
  if (notCounted.isNotEmpty) {
    notes.add(
      '「${notCounted.map((c) => c.name).join('、')}」按学校文件**不计入总学分**'
      '（只作毕业资格审核依据，见《2024 版本科人才培养方案修订指导意见》），'
      '所以没有算进上面任何一段。',
    );
  }
  // 挂科：单列一条，讲清「为什么这门课在清单里却没给我学分」
  final failed = <CreditProgressCourse>[];
  for (final s in compulsoryStates) {
    if (s.failed) {
      failed.add(
        CreditProgressCourse(
          code: s.code,
          name: s.name,
          credit: s.credit,
          earned: s.earned,
          semester: s.semester,
          score: s.score,
        ),
      );
    }
  }
  for (final s in practiceStates) {
    if (s.failed) {
      failed.add(
        CreditProgressCourse(
          code: s.code,
          name: s.name,
          credit: s.credit,
          earned: s.earned,
          semester: s.semester,
        ),
      );
    }
  }
  for (final e in electives) {
    for (final c in e.courses) {
      if (c.failed) failed.add(c);
    }
  }
  if (failed.isNotEmpty) {
    final credits = failed.fold<double>(0, (s, c) => s + c.credit);
    notes.add(
      '**有 ${failed.length} 门挂科**（${failed.map((c) => c.name).join('、')}），'
      '共 ${creditTextOf(credits)} 学分。挂科**不计入已修学分**（「已修」按获得学分算），'
      '必须重修通过才能拿到，所以它仍然留在「还差」里。',
    );
  }
  if (index.scope.sheets.isEmpty) {
    notes.add('通识课程库为空，四个通识模块无法统计。');
  } else if (!index.scope.exactCohortMatch) {
    notes.add(
      index.scope.cohort == null
          ? '通识课程库：学籍入学年未知，已按「${index.scope.sheetTitles.join('」「')}」查表。'
          : '通识课程库没有适用 ${index.scope.cohort} 级的表，已退到「${index.scope.sheetTitles.join('」「')}」。',
    );
  }

  return GraduationCreditProgress(
    compulsory: CompulsoryCreditProgress(
      required: compulsoryRequired,
      earned: compulsoryEarned,
      inProgress: compulsoryInProgressCredits,
      courses: compulsoryStates,
    ),
    practice: PracticeCreditProgress(
      required: practiceRequired,
      earned: practiceEarnedTotal,
      inProgress: practiceInProgressCredits,
      stages: practiceStates,
      label: practice == null
          ? null
          : '${practice.year} · ${practice.collegeName} · ${practice.majorName}',
    ),
    electives: electives,
    unmatched: unmatched,
    notCounted: notCounted,
    earnedTotal: deduped.values.fold(0.0, (s, t) => s + t.earned),
    curriculumLabel: curriculum == null
        ? null
        : '${curriculum.year} · ${curriculum.collegeName} · ${curriculum.majorName}',
    catalogScope: index.scope,
    notes: notes,
  );
}

/// 给一门课找去处：先培养方案、再通识课程库。
_Bucket _classify({
  required CreditProgressCourse course,
  required Course? plan,
  required GeneralEducationIndex index,
  required Set<String> requiredSubCategories,
  required Set<GeneralEducationModule> requiredModules,
}) {
  if (plan != null) {
    final subKey = canonicalCategoryKey(plan.subCategory);
    if (subKey.isNotEmpty && requiredSubCategories.contains(subKey)) {
      return _Bucket.elective(ElectiveRule.sub(plan.subCategory).key);
    }
    final planModule = generalEducationModuleOf(plan.subCategory);
    if (planModule != null) {
      if (requiredModules.contains(planModule)) {
        return _Bucket.elective(ElectiveRule.module(planModule).key);
      }
      return _Bucket.unmatched(
        '培养方案里属「${plan.subCategory}」，教务要求表里没有这一项',
      );
    }
    if (subKey.isNotEmpty) {
      return _Bucket.unmatched(
        '培养方案里属「${plan.subCategory}」，教务要求表里没有这一项',
      );
    }
    // 培养方案的二级分类为空 → 继续按通识课程库找
  }

  final libCourse = index.lookup(code: course.code, name: course.name);
  if (libCourse != null) {
    final module = libCourse.module;
    if (module == null) {
      return _Bucket.unmatched(
        '在通识课程库「${libCourse.sheetTitle}」里，但该行没有模块标签',
      );
    }
    if (requiredModules.contains(module)) {
      return _Bucket.elective(ElectiveRule.module(module).key);
    }
    return _Bucket.unmatched(
      '通识课程库把它归到「${module.label}」模块，教务要求表里没有这一项',
    );
  }

  return const _Bucket.unmatched(null);
}

/// 某个规则的课程池（培养方案里的门数与学分）；通识模块返回 0。
(int, double) _poolOf(ElectiveRule? rule, Curriculum? curriculum) {
  if (rule == null ||
      rule.kind != ElectiveRuleKind.curriculumSubCategory ||
      curriculum == null) {
    return (0, 0.0);
  }
  final want = canonicalCategoryKey(rule.subCategory!);
  var count = 0;
  var credits = 0.0;
  for (final c in curriculum.courses) {
    if (c.requirement != CourseRequirement.elective) continue;
    if (canonicalCategoryKey(c.subCategory) != want) continue;
    count++;
    credits += c.credit;
  }
  return (count, credits);
}
