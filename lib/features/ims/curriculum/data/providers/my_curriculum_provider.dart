/// 「本专业培养方案」的唯一链路：学籍 → 学院 → 专业 → 培养方案。
///
/// 这条链原先后被抄了三份（`aiCurriculumProvider` /
/// `curriculumImportanceMapProvider` / `geCurriculumIndexProvider`），
/// 2026-10-08 收拢到这里 —— 新功能（毕业学分进度）直接用，
/// 那两处已改成从这里派生，只有分数估计那处带自己的降级日志暂未迁
/// （见各自的注释）。
///
/// 离线特性：`CurriculumRepository.getCurriculumIn` **命中本地缓存不发网络**，
/// 所以只要用户打开过一次培养方案页，这里离线也能拿到。任一步失败返回 null，
/// 调用方按「拿不到」处理 —— 不编数据。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/college/data/providers/college_repository_provider.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_repository_provider.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

/// 本机缓存的学籍（离线；没有就 null）。
final myStudentInfoProvider = FutureProvider<StudentInfo?>((ref) async {
  try {
    final repo = await ref.watch(studentInfoRepositoryProvider.future);
    return repo.getCachedStudentInfo().fold((_) => null, (i) => i);
  } catch (_) {
    return null;
  }
});

/// 本专业培养方案（拿不到就是 null）。
final myCurriculumProvider = FutureProvider<Curriculum?>((ref) async {
  try {
    final key = await ref.watch(myPlanKeyProvider.future);
    if (key == null) return null;
    final repo = await ref.watch(curriculumRepositoryProvider.future);
    final result = await repo.getCurriculumIn(key.year, key.college, key.major);
    return result.fold((_) => null, (c) => c);
  } catch (_) {
    return null;
  }
});

/// 学籍上的入学年级（培养方案年份 / 通识课程库适用表都按它选）。
final myCohortProvider = FutureProvider<int?>((ref) async {
  final si = await ref.watch(myStudentInfoProvider.future);
  return int.tryParse(si?.enrollYear.trim() ?? '');
});

/// 「本专业」的定位三元组：入学年 + 学院 + 专业（都已按名字在教务列表里对上号）。
///
/// 抽出来是因为**理论课程**与**实践环节**是两张表、两条仓库调用，但定位方式
/// 一模一样（学籍 → 学院按名匹配 → 专业按名匹配）。2026-10-08 加实践环节时
/// 收拢到这里，别再抄第三份。
class MyPlanKey {
  final int year;
  final College college;
  final Major major;

  const MyPlanKey({
    required this.year,
    required this.college,
    required this.major,
  });
}

/// 定位本专业；任一步失败返回 null（不编）。
final myPlanKeyProvider = FutureProvider<MyPlanKey?>((ref) async {
  try {
    final si = await ref.watch(myStudentInfoProvider.future);
    if (si == null) return null;
    final year = int.tryParse(si.enrollYear.trim());
    if (year == null) return null;

    final collegeRepo = await ref.watch(collegeRepositoryProvider.future);
    final colleges = (await collegeRepo.getAllCollege()).fold(
      (_) => const <College>[],
      (list) => list,
    );
    College? college;
    for (final c in colleges) {
      if (c.name == si.college) {
        college = c;
        break;
      }
    }
    if (college == null) return null;

    final majorRepo = await ref.watch(majorRepositoryProvider.future);
    final majors = (await majorRepo.getAllMajorIn(
      college,
      year: year,
    )).fold((_) => const <Major>[], (list) => list);
    Major? major;
    for (final m in majors) {
      if (m.name == si.major) {
        major = m;
        break;
      }
    }
    if (major == null) return null;

    return MyPlanKey(year: year, college: college, major: major);
  } catch (_) {
    return null;
  }
});
