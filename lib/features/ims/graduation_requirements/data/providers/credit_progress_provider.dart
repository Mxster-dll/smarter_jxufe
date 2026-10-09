/// 毕业学分进度的装配：教务要求表 + 本专业培养方案 + 通识课程库 + 已修成绩。
///
/// 四路数据各自的失败面互不牵连 —— 教务要求表挂了仍然出必修进度，
/// 培养方案拿不到仍然出四个通识模块的进度（详见 `credit_progress.dart` 的口径）。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/providers/my_curriculum_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/my_practice_curriculum_provider.dart';
// ⚠ `gradesProvider` 定义在**页面文件**里（不在 data/providers/），这是既成事实；
// 项目里已有同样做法的先例（`features/ai/tools/plan_tools.dart` import 了
// `graduation_requirements_screen.dart` 的 provider）。别为了「层次好看」把它复制一份 ——
// 那会变成两份成绩口径，而这里要的正是**和成绩页同一份缓存**。
import 'package:smarter_jxufe/features/ims/grades/data/providers/grades_box_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_query_params.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_result.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/time_limit.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_screen.dart'
    show gradesProvider;
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_display_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/grades_cache_reader.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/providers/general_education_catalog_provider.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/credit_progress.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/graduation_requirement.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/presentation/graduation_requirements_screen.dart'
    show graduationRequirementsProvider;

/// **当下学期**（`currentSchoolTerm` + 校历学期表）。
///
/// 口径与 AI 工具层的 `aiCurrentTerm` 一致（都传 `terms:`）—— 不传就退化成
/// 月份经验规则，学期会错一个月。目前只有本页要用，故先留在这里；
/// 将来第二处要用就该提到 `school_calendar` 去。
final currentSchoolTermProvider = Provider<({int xn, int xq})>(
  (ref) => currentSchoolTerm(
    DateTime.now(),
    terms: ref.watch(offlineSemesterTermsProvider),
  ),
);

/// 已修课程清单。
///
/// **一档**：走成绩页同款查询（`时间限制=全部` + 主修/辅修/微专全选）——
/// `GradesRepository.getGrades` 是**缓存优先**，命中缓存一个网络包都不发；
/// 缓存缺失时它会自己补拉一次，拉完顺带把成绩页的缓存也填上。
/// **二档**：上面失败（无学籍 / 会话失效 / 网络不通）就退回直接读成绩缓存 box ——
/// 离线可用，与分数估计模块同源。
///
/// ⚠ 刻意**不套用**成绩页的 GPA 课程排除名单（军事训练等），理由见
/// `grades_cache_reader.dart` 的 docstring。
final graduationTakenCoursesProvider = FutureProvider<List<TakenCourse>>((
  ref,
) async {
  final cohort = await ref.watch(myCohortProvider.future);
  if (cohort != null) {
    try {
      final GradesResult result = await ref.watch(
        gradesProvider(
          GradesQueryParams(
            enrollYear: '$cohort',
            timeLimit: TimeLimit.sinceEnrollment,
          ),
        ).future,
      );
      if (result.grades.isNotEmpty) {
        return [for (final g in result.grades) takenCourseFromGrade(g)];
      }
      debugPrint('[graduation_credits] 成绩查询返回空，改读本地缓存');
    } catch (e) {
      debugPrint('[graduation_credits] 成绩查询失败，改读本地缓存：$e');
    }
  } else {
    debugPrint('[graduation_credits] 无学籍入学年，直接读成绩缓存');
  }
  try {
    final box = await ref.watch(gradesBoxProvider.future);
    return takenCoursesFromGradesBox(box);
  } catch (e) {
    debugPrint('[graduation_credits] 成绩缓存也不可读：$e');
    return const [];
  }
});

/// 「已选未考」清单：**本学期课表里、还没有拿到学分的课**。
///
/// 用户 2026-10-08 原话：「用更更浅一点的红色，标识已选但是未考试的学分部分」。
/// 数据源 = **本学期课表的本地缓存**（`scheduleCachedEntriesProvider`，只读不联网）
/// 减去成绩里已经拿到学分的那批 —— 于是「这学期正在上、还没出分」的课自然浮现。
///
/// ⚠ 三条口径：
/// - **只认拿到学分的**：一门课挂过再重修，本学期课表里还有它 → 不算在修（有成绩了）。
/// - 课表缓存没有本学期（没打开过课表页 / 换过账号）→ 返回空表，界面就不会画浅色段，
///   **不会瞎猜**。
/// - 按课程代码去重（同一门课可能出现在多个上课时段）。
final graduationInProgressProvider = FutureProvider<List<TakenCourse>>((
  ref,
) async {
  try {
    final taken = await ref.watch(graduationTakenCoursesProvider.future);
    final passed = {
      for (final t in taken)
        if (t.earned > 0 && t.code.isNotEmpty) t.code,
    };
    final passedNames = {
      for (final t in taken)
        if (t.earned > 0 && t.name.isNotEmpty) t.name,
    };

    final term = ref.watch(currentSchoolTermProvider);
    final entries = await ref.watch(
      scheduleCachedEntriesProvider((xn: term.xn, xq: term.xq)).future,
    );

    final byCode = <String, TakenCourse>{};
    for (final e in entries) {
      final code = e.courseCode.trim();
      final name = e.courseName.trim();
      if (name.isEmpty) continue;
      if (code.isNotEmpty && passed.contains(code)) continue;
      if (passedNames.contains(name)) continue;
      final key = code.isNotEmpty ? code : 'name:$name';
      byCode.putIfAbsent(
        key,
        () => TakenCourse(
          code: code,
          name: name,
          credit: e.credits,
          earned: 0,
          semester: '',
        ),
      );
    }
    debugPrint(
      '[graduation_credits] 本学期 ${term.xn}-${term.xq} 课表 ${entries.length} 条 '
      '→ 已选未考 ${byCode.length} 门',
    );
    return byCode.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  } catch (e) {
    debugPrint('[graduation_credits] 取「已选未考」失败：$e');
    return const [];
  }
});

/// 页面要的一整份数据：推算结果 + 「教务要求表这次有没有取到」。
///
/// 分开装是因为两者的失败面不同：要求表要教务会话（会失效、会断网），
/// 而必修进度 / 未归类只依赖本地（培养方案缓存 + 成绩缓存 + asset）。
/// 要求表挂了不该把必修进度一起打掉。
class GraduationCreditReport {
  final GraduationCreditProgress progress;

  /// 教务要求表读取失败的原因；取到了就是 null。
  final String? requirementsError;

  const GraduationCreditReport({
    required this.progress,
    this.requirementsError,
  });
}

/// 毕业学分进度（页面唯一取数口）。
final graduationCreditReportProvider = FutureProvider<GraduationCreditReport>((
  ref,
) async {
  List<GraduationRequirement> requirements = const [];
  String? requirementsError;
  try {
    requirements = await ref.watch(graduationRequirementsProvider.future);
  } catch (e) {
    requirementsError = '$e';
    debugPrint('[graduation_credits] 教务要求表读取失败：$e');
  }

  final curriculum = await ref.watch(myCurriculumProvider.future);
  final practice = await ref.watch(myPracticeCurriculumProvider.future);
  final cohort = await ref.watch(myCohortProvider.future);
  final catalog = await ref.watch(generalEducationCatalogProvider.future);
  final taken = await ref.watch(graduationTakenCoursesProvider.future);
  final inProgress = await ref.watch(graduationInProgressProvider.future);

  return GraduationCreditReport(
    progress: buildGraduationCreditProgress(
      requirements: requirements,
      taken: taken,
      inProgress: inProgress,
      curriculum: curriculum,
      practice: practice,
      catalog: catalog,
      cohort: cohort,
    ),
    requirementsError: requirementsError,
  );
});
