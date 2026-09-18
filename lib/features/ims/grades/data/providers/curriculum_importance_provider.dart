import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/college/data/providers/college_repository_provider.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_repository_provider.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

/// 课程代码 → 课程地位（主干 / 非主干），来自**本专业培养方案**。
///
/// 2026-09-17 从 `grades_screen.dart` 的私有 `_curriculumImportanceMapProvider`
/// 原样迁出并公开：推免成绩页要用同一份口径算推免加权（主干×0.7 + 非主干×0.3），
/// 各写一份必然漂移。
///
/// 链路（与 §5「教务数据来源速查」一致）：学籍 → 学院按名匹配 → 专业按名匹配
/// → 培养方案（**命中本地缓存直接返回，离线可用**）。任何一步失败返回 null，
/// 调用方按「无课程地位信息」处理（此时推免加权降级为全部按非主干算，
/// 页面必须提示而不是静默给一个错数）。
final curriculumImportanceMapProvider =
    FutureProvider<Map<String, CourseImportance>?>((ref) async {
      final studentInfoRepo = await ref.watch(
        studentInfoRepositoryProvider.future,
      );
      StudentInfo? info;
      studentInfoRepo.getCachedStudentInfo().fold((_) {}, (i) => info = i);
      if (info == null) return null;
      final si = info!;

      final year = int.tryParse(si.enrollYear);
      if (year == null) return null;

      final collegeRepo = await ref.watch(collegeRepositoryProvider.future);
      College? matchedCollege;
      final collegesResult = await collegeRepo.getAllCollege();
      collegesResult.fold((_) {}, (colleges) {
        for (final c in colleges) {
          if (c.name == si.college) {
            matchedCollege = c;
            break;
          }
        }
      });
      if (matchedCollege == null) return null;
      final mc = matchedCollege!;

      final majorRepo = await ref.watch(majorRepositoryProvider.future);
      Major? matchedMajor;
      final majorsResult = await majorRepo.getAllMajorIn(mc, year: year);
      majorsResult.fold((_) {}, (majors) {
        for (final m in majors) {
          if (m.name == si.major) {
            matchedMajor = m;
            break;
          }
        }
      });
      if (matchedMajor == null) return null;
      final mm = matchedMajor!;

      final curriculumRepo = await ref.watch(
        curriculumRepositoryProvider.future,
      );
      final curriculumResult = await curriculumRepo.getCurriculumIn(
        year,
        mc,
        mm,
      );
      final map = <String, CourseImportance>{};
      curriculumResult.fold((_) {}, (curriculum) {
        for (final course in curriculum.courses) {
          map[course.code] = course.importance;
        }
      });
      return map;
    });
