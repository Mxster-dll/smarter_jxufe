import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/grades/domain/grades_query_params.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_result.dart';

/// 成绩的本地 Hive 缓存，以完整查询参数为键独立存储。
class GradesLocalDataSource {
  final Box<String> _box;

  GradesLocalDataSource(this._box);

  /// 根据查询参数生成唯一的缓存键。
  static String _cacheKey(GradesQueryParams p) => [
    'grades',
    p.enrollYear,
    p.timeLimit.name,
    p.showRawGrade,
    p.selectMajor,
    p.selectMinor,
    p.selectWeiZhuan,
    p.onlyNotPassed,
    p.semesterXq ?? r'$null',
    p.academicYear ?? r'$null',
    p.academicYearNext ?? r'$null',
  ].join('|');

  /// 保存成绩缓存。
  Future<void> saveGrades(
    GradesQueryParams params,
    GradesResult result,
  ) async => _box.put(_cacheKey(params), json.encode(result.toMap()));

  /// 读取缓存，无数据时返回 null。
  GradesResult? getCachedGrades(GradesQueryParams params) {
    final raw = _box.get(_cacheKey(params));
    if (raw == null) return null;
    try {
      return GradesResult.fromMap(json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 清除所有成绩缓存。
  Future<void> clearAll() => _box.clear();

  /// 清除指定参数的缓存。
  Future<void> clear(GradesQueryParams params) =>
      _box.delete(_cacheKey(params));
}
