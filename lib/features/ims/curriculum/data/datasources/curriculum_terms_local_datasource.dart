import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_terms.dart';

/// 开课学期侧表的本地缓存：**`Box<String>` 单 key JSON 整表读写**（§3「模型」口径）。
///
/// 键与 `CurriculumLocalDataSource.keyString` 同形、加 `terms_` 前缀
/// （实践环节那条是 `practice_` 前缀，别混）。
class CurriculumTermsLocalDataSource {
  final Box<String> _box;

  CurriculumTermsLocalDataSource(this._box);

  String keyString(int year, String collegeName, String majorName) =>
      'terms_${year}_${collegeName}_$majorName';

  Future<void> save({
    required int year,
    required String collegeName,
    required String majorName,
    required CurriculumTerms terms,
  }) => _box.put(
    keyString(year, collegeName, majorName),
    json.encode(terms.toMap()),
  );

  /// 读缓存；缺失或损坏一律返回 null（不让旧数据把页面打崩）。
  CurriculumTerms? get(int year, String collegeName, String majorName) {
    final raw = _box.get(keyString(year, collegeName, majorName));
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return CurriculumTerms.fromMap(decoded);
    } catch (e) {
      debugPrint('[curriculum_terms] 缓存解析失败：$e');
      return null;
    }
  }

  Future<void> clearAll() => _box.clear();
}
