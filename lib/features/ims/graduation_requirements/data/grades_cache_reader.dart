/// 成绩缓存 → 毕业学分进度的输入（`TakenCourse`）。
///
/// 数据来源与分数估计模块**完全同源**：成绩页写入的 Hive box（`Box<String>`）：
/// - 键形如 `grades|<enrollYear>|...`（见 `GradesLocalDataSource.cacheKey`）；
/// - 值 = `json.encode(GradesResult.toMap())` = `{'grades': [Grade.toMap(), ...]}`。
///
/// 同一时刻可能存在多份不同查询参数的缓存副本，因此遍历**全部** `grades|`
/// 前缀的键，按课程码去重后交给算法（去重细则在 `credit_progress.dart`，
/// 这里只负责把两份缓存拼成一份更全的清单）。
///
/// ⚠ 与 `ge_prior_grades.dart` 的一处**有意不同**：这里**不套用**成绩页的
/// 课程排除名单（军事训练 / 毕业设计 …）。那份名单是**算 GPA/加权**的口径，
/// 而毕业学分要的是「到底拿了多少学分」—— 军事训练 2 学分是实打实的学分，
/// 把它按 GPA 口径剔掉会让合计对不上。剔掉后它只是进「未归类」，
/// 界面会照实说明原因。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/grades/domain/grade.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_result.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/credit_progress.dart';

/// 成绩缓存键前缀（由 `GradesLocalDataSource.cacheKey` 生成）。
const String _gradesKeyPrefix = 'grades|';

/// 成绩页的一条成绩 → 算法的输入。
TakenCourse takenCourseFromGrade(Grade g) => TakenCourse(
  code: g.courseCode.trim(),
  name: g.courseName.trim(),
  credit: double.tryParse(g.credit.trim()) ?? 0,
  earned: double.tryParse(g.earnedCredit.trim()) ?? 0,
  semester: g.semester,
  score: double.tryParse(g.score.trim()),
);

/// 挂科记录（`Grade` 级）：有成绩、但获得学分为 0。
///
/// 与 [TakenCourse.failed] 同判据 —— 成绩表里的行都是**已考核**的，
/// 所以「学分 > 0 且 获得学分 = 0」就是挂科，不会把在修课误判进来。
bool isFailedGrade(Grade g) {
  final credit = double.tryParse(g.credit.trim()) ?? 0;
  final earned = double.tryParse(g.earnedCredit.trim()) ?? 0;
  return credit > 0 && earned <= 0;
}

/// 从成绩缓存解析出全部已修课程；[box] 为 null 时返回空列表。
List<TakenCourse> takenCoursesFromGradesBox(Box<String>? box) {
  if (box == null) return const [];
  final byKey = <String, TakenCourse>{};
  var badCopies = 0;
  for (final key in box.keys) {
    if (key is! String || !key.startsWith(_gradesKeyPrefix)) continue;
    final raw = box.get(key);
    if (raw == null) continue;
    final GradesResult result;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        badCopies++;
        continue;
      }
      result = GradesResult.fromMap(decoded);
    } catch (e) {
      badCopies++;
      debugPrint('[graduation_credits] 成绩缓存副本解析失败 <$key>：$e');
      continue;
    }
    for (final g in result.grades) {
      final name = g.courseName.trim();
      if (name.isEmpty) continue;
      final code = g.courseCode.trim();
      final key = code.isEmpty ? 'name:$name' : code;
      final taken = TakenCourse(
        code: code,
        name: name,
        credit: double.tryParse(g.credit.trim()) ?? 0,
        earned: double.tryParse(g.earnedCredit.trim()) ?? 0,
        semester: g.semester,
        score: double.tryParse(g.score.trim()),
      );
      final prev = byKey[key];
      // 同码多条：留获得学分更高的；相同再留学期较新的（'251' 字典序即时间序）。
      if (prev == null ||
          taken.earned > prev.earned ||
          (taken.earned == prev.earned &&
              taken.semester.compareTo(prev.semester) > 0)) {
        byKey[key] = taken;
      }
    }
  }
  final list = byKey.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  debugPrint(
    '[graduation_credits] 成绩缓存 keys=${box.keys.length} → 已修课程 ${list.length} 门'
    '${badCopies > 0 ? '（$badCopies 份副本解析失败）' : ''}',
  );
  return list;
}
