/// 分数估计 · 教务成绩缓存读取（「之前分数」的数据来源）。
///
/// 数据来源：成绩页写入的 Hive box `gradesCache`（`Box<String>`）：
/// - 键形如 `grades|<enrollYear>|...`（见 GradesLocalDataSource.cacheKey）；
/// - 值 = `json.encode(GradesResult.toMap())` = `{'grades': [Grade.toMap(), ...]}`。
///
/// 同一时刻可能存在多份不同查询参数的缓存副本，因此遍历全部 `grades|`
/// 前缀的键后按课程码去重（保留学期较新的一条）。离线可用：解析失败或
/// box 不存在时一律返回空列表，不抛异常。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/storage/account_scoped_box.dart';
import '../../ims/grades/domain/grades_exclusions.dart';
import '../../ims/grades/domain/grades_result.dart';

/// 成绩缓存 box 的**基础**名（实际 box 按账号隔离，与
/// `lib/features/ims/grades/data/providers/grades_box_provider.dart` 一致）。
const geGradesBoxName = 'gradesCache';

/// 成绩缓存键前缀（由 GradesLocalDataSource.cacheKey 生成）。
const _gradesKeyPrefix = 'grades|';

/// 教务成绩中的一门「已出成绩」课程。
class GePriorGrade {
  /// 课程码（缺失时退化为课程名，仅作去重键用）。
  final String courseCode;

  /// 课程名。
  final String courseName;

  /// 百分制成绩（非数字成绩按 0 分，与成绩页「课程加权」同口径）。
  final double score;

  /// 学分（加权权重）。
  final double credits;

  /// 学期码，如 '251'。
  final String semester;

  const GePriorGrade({
    required this.courseCode,
    required this.courseName,
    required this.score,
    required this.credits,
    required this.semester,
  });
}

/// 解析成绩缓存中的全部已出成绩；[box] 为 null 时返回空列表。
///
/// 与成绩页口径一致：排除名单（[kExcludedGradeCourses]）内的课程不计入。
List<GePriorGrade> gePriorGradesFromBox(Box<String>? box) {
  if (box == null) {
    return const [];
  }
  final byCode = <String, GePriorGrade>{};
  var excluded = 0;
  for (final key in box.keys) {
    if (key is! String || !key.startsWith(_gradesKeyPrefix)) {
      continue;
    }
    final raw = box.get(key);
    if (raw == null) {
      continue;
    }
    final GradesResult result;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      result = GradesResult.fromMap(decoded);
    } catch (e) {
      // 缓存损坏：跳过该副本（并留痕，避免静默失败）。
      debugPrint('[score_estimate] 成绩缓存副本解析失败 <$key>：$e');
      continue;
    }
    for (final g in result.grades) {
      final name = g.courseName.trim();
      if (name.isEmpty) {
        continue;
      }
      // 与成绩页「课程加权」同口径：排除名单内的课程不参与统计。
      if (isExcludedGradeCourse(name)) {
        excluded++;
        continue;
      }
      final code = g.courseCode.trim();
      final grade = GePriorGrade(
        courseCode: code.isEmpty ? name : code,
        courseName: name,
        score: double.tryParse(g.score.trim()) ?? 0,
        credits: double.tryParse(g.credit.trim()) ?? 0,
        semester: g.semester,
      );
      final prev = byCode[grade.courseCode];
      // semester 为 '251' 形式，字典序即时间序 → 取较新的一条。
      if (prev == null || grade.semester.compareTo(prev.semester) >= 0) {
        byCode[grade.courseCode] = grade;
      }
    }
  }
  debugPrint(
    '[score_estimate] 成绩缓存 keys=${box.keys.length} → 计入 ${byCode.length} 门，'
    '按成绩页口径排除 $excluded 条',
  );
  return byCode.values.toList()
    ..sort((a, b) => a.courseName.compareTo(b.courseName));
}

/// 打开成绩缓存 box 并解析（box 已打开时 Hive 直接复用同一实例）。
///
/// [account] = 当前账号：成绩缓存按账号隔离（见 `core/storage/account_scoped_box.dart`），
/// 传 null/空表示账号未确定，读独立的 `__none` box（**不会**读到别的账号的成绩）。
///
/// 任何异常（box 未初始化、读取失败）都吞掉并返回空列表——本模块的
/// 加权平均只是增强信息，不应因成绩缓存问题阻塞页面。异常会打日志，
/// 便于排查「合计里没有教务成绩」这类静默失败。
Future<List<GePriorGrade>> loadGePriorGrades({String? account}) async {
  try {
    final box = await openAccountScopedBox(geGradesBoxName, account);
    return gePriorGradesFromBox(box);
  } catch (e, st) {
    debugPrint('[score_estimate] 打开成绩缓存 box 失败：$e\n$st');
    return const [];
  }
}
