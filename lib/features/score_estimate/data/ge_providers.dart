/// 分数估计 · providers：Hive box 与 store 装配。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../college/data/providers/college_repository_provider.dart';
import '../../college/domain/college.dart';
import '../../../core/network/current_account_provider.dart';
import '../../../core/storage/account_scoped_box.dart';
import '../../ims/curriculum/data/providers/curriculum_repository_provider.dart';
import '../../ims/grades/data/providers/grades_box_provider.dart';
import '../../ims/student_info/data/providers/student_info_repository_provider.dart';
import '../../major/data/providers/major_repository_provider.dart';
import '../../major/domain/major.dart';
import '../domain/ge_models.dart';
import 'ge_curriculum.dart';
import 'ge_prior_grades.dart';
import 'ge_store.dart';

/// 分数估计的本地 box（**按账号隔离**：本人录的课程与预估分不该跨账号串）。
///
/// 见 `core/storage/account_scoped_box.dart`：box 名 = `score_estimate_<账号>`，
/// 账号未确定时用 `score_estimate__none`；旧的全局 box 会被第一个打开的账号
/// 迁移认领一次。切号 → `currentAccountProvider` 变化 → 本 provider 重跑。
final geBoxProvider = FutureProvider<Box<String>>(
  (ref) => openAccountScopedBox(geBoxName, ref.watch(currentAccountProvider)),
);

final geStoreProvider = FutureProvider<GeStore>((ref) async {
  final box = await ref.watch(geBoxProvider.future);
  return GeStore(box);
});

/// 全部课程（按创建先后）；写库后在 UI 侧同步本地列表/重新 load 保持一致。
final geCoursesProvider = FutureProvider<List<GeCourse>>((ref) async {
  final store = await ref.watch(geStoreProvider.future);
  return store.loadCourses();
});

/// 教务成绩缓存中的「已出成绩」（离线可读），用于与估计分合计总加权平均。
///
/// 复用成绩页的 `gradesBoxProvider`（同一 Hive box 实例），并已按成绩页的
/// 排除课程口径过滤（见 ge_prior_grades.dart）。若该 provider 链路异常，
/// 回退到直接按 box 名打开，避免「合计里没有教务成绩」的静默失败。
final gePriorGradesProvider = FutureProvider<List<GePriorGrade>>((ref) async {
  try {
    final box = await ref.watch(gradesBoxProvider.future);
    return gePriorGradesFromBox(box);
  } catch (e) {
    debugPrint('[score_estimate] gradesBoxProvider 链路失败，回退直连 box：$e');
    return loadGePriorGrades(account: ref.read(currentAccountProvider));
  }
});

/// 本专业培养方案的学分索引（课程代码 / 课程名 → 学分）。
///
/// 链路与成绩页 `_curriculumImportanceMapProvider`（grades_screen.dart:24-81）
/// 一致：学籍（学院/专业/入学年）→ 学院 → 专业 → 培养方案。培养方案命中本地
/// 缓存时**不发网络**（CurriculumRepository.getCurriculumIn 先查缓存），
/// 因此离线也能拿到学分。任一步失败都返回空索引，不阻塞课程列表与加权计算
/// （此时界面回退到课程自身记录的学分）。
final geCurriculumIndexProvider = FutureProvider<GeCurriculumIndex>((
  ref,
) async {
  try {
    final studentInfoRepo = await ref.watch(
      studentInfoRepositoryProvider.future,
    );
    final si = studentInfoRepo.getCachedStudentInfo().fold(
      (_) => null,
      (i) => i,
    );
    if (si == null) {
      debugPrint('[score_estimate] 培养方案索引：无本地学籍信息，跳过');
      return const GeCurriculumIndex.empty();
    }
    final year = int.tryParse(si.enrollYear);
    if (year == null) {
      debugPrint('[score_estimate] 培养方案索引：入学年无法解析（${si.enrollYear}）');
      return const GeCurriculumIndex.empty();
    }

    final collegeRepo = await ref.watch(collegeRepositoryProvider.future);
    final colleges = (await collegeRepo.getAllCollege()).fold(
      (_) => const <College>[],
      (list) => list,
    );
    College? matchedCollege;
    for (final c in colleges) {
      if (c.name == si.college) {
        matchedCollege = c;
        break;
      }
    }
    if (matchedCollege == null) {
      debugPrint('[score_estimate] 培养方案索引：学院未匹配（${si.college}）');
      return const GeCurriculumIndex.empty();
    }

    final majorRepo = await ref.watch(majorRepositoryProvider.future);
    final majors = (await majorRepo.getAllMajorIn(
      matchedCollege,
      year: year,
    )).fold((_) => const <Major>[], (list) => list);
    Major? matchedMajor;
    for (final m in majors) {
      if (m.name == si.major) {
        matchedMajor = m;
        break;
      }
    }
    if (matchedMajor == null) {
      debugPrint('[score_estimate] 培养方案索引：专业未匹配（${si.major}）');
      return const GeCurriculumIndex.empty();
    }

    final curriculumRepo = await ref.watch(curriculumRepositoryProvider.future);
    final curriculum = await curriculumRepo.getCurriculumIn(
      year,
      matchedCollege,
      matchedMajor,
    );
    final index = curriculum.fold(
      (_) => const GeCurriculumIndex.empty(),
      (c) => GeCurriculumIndex.fromCurriculum(c),
    );
    debugPrint(
      '[score_estimate] 培养方案索引：${index.majorName} '
      '可匹配课程 ${index.codeCount} 门（按名 ${index.nameCount} 门）',
    );
    return index;
  } catch (e) {
    debugPrint('[score_estimate] 培养方案索引构建失败：$e');
    return const GeCurriculumIndex.empty();
  }
});
