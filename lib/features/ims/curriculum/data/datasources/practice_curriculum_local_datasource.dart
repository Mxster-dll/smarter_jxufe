import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';

/// 实践环节的本地缓存：**`Box<String>` 单 key JSON 整表读写**（§3「模型」的口径）。
///
/// 刻意**不复用** `curriculums` 那个 `Box<Curriculum>`：`Curriculum` 是 Hive 对象
/// 类型，往里加字段要走 schema 迁移 + 重跑 build_runner；实践环节是一张**独立的表**，
/// 单开一个 box 更省事也更安全（旧缓存不受影响）。
class PracticeCurriculumLocalDataSource {
  final Box<String> _box;

  PracticeCurriculumLocalDataSource(this._box);

  /// 缓存键：与 `CurriculumLocalDataSource.keyString` 同形，但加 `practice_` 前缀。
  String keyString(int year, String collegeName, String majorName) =>
      'practice_${year}_${collegeName}_$majorName';

  Future<void> save({
    required int year,
    required String collegeName,
    required String majorName,
    required PracticeCurriculum curriculum,
  }) => _box.put(
    keyString(year, collegeName, majorName),
    json.encode(curriculum.toMap()),
  );

  /// 读缓存；缺失或损坏一律返回 null（不让旧数据把页面打崩）。
  PracticeCurriculum? get(int year, String collegeName, String majorName) {
    final raw = _box.get(keyString(year, collegeName, majorName));
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return PracticeCurriculum.fromMap(decoded);
    } catch (e) {
      debugPrint('[practice_curriculum] 缓存解析失败：$e');
      return null;
    }
  }

  Future<void> clearAll() => _box.clear();
}
