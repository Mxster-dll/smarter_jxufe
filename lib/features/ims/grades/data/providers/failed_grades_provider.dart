/// 挂科记录（成绩表里获得学分为 0 的行）—— 推免页与毕业学分页共用。
///
/// 2026-10-08 立。判据见 `domain/failed_grade.dart`；数据源 = 成绩页写入的
/// Hive `Box<String>`（`grades|<enrollYear>|...` 键，值与成绩页**同一份缓存**）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/grades/data/providers/grades_box_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/failed_grade.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_result.dart';

/// 成绩缓存键前缀（由 `GradesLocalDataSource.cacheKey` 生成）。
const String _gradesKeyPrefix = 'grades|';

/// 从成绩缓存里挑出全部挂科记录；[box] 为 null 时返回空列表。
///
/// ⚠ **不去重**：同一门课挂过两次就是两条记录（推免看的是「有没有挂过」）。
List<FailedGrade> failedGradesFromBox(Box<String>? box) {
  if (box == null) return const [];
  final out = <FailedGrade>[];
  for (final key in box.keys) {
    if (key is! String || !key.startsWith(_gradesKeyPrefix)) continue;
    final raw = box.get(key);
    if (raw == null) continue;
    final GradesResult result;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) continue;
      result = GradesResult.fromMap(decoded);
    } catch (e) {
      debugPrint('[failed_grades] 成绩缓存副本解析失败 <$key>：$e');
      continue;
    }
    for (final g in result.grades) {
      final name = g.courseName.trim();
      if (name.isEmpty) continue;
      final credit = double.tryParse(g.credit.trim()) ?? 0;
      final earned = double.tryParse(g.earnedCredit.trim()) ?? 0;
      // 判据 = 有学分 + 一分没拿到（成绩表里的行都是已考核的）
      if (credit <= 0 || earned > 0) continue;
      out.add(
        FailedGrade(
          code: g.courseCode.trim(),
          name: name,
          credit: credit,
          score: double.tryParse(g.score.trim()),
          semester: g.semester,
        ),
      );
    }
  }
  out.sort((a, b) => b.semester.compareTo(a.semester));
  debugPrint('[failed_grades] 挂科记录 ${out.length} 条');
  return out;
}

/// 挂科记录（读不到就是空表 —— 页面据此**不显示**警示，而不是报错）。
final failedGradesProvider = FutureProvider<List<FailedGrade>>((ref) async {
  try {
    final box = await ref.watch(gradesBoxProvider.future);
    return failedGradesFromBox(box);
  } catch (e) {
    debugPrint('[failed_grades] 取挂科记录失败：$e');
    return const [];
  }
});
