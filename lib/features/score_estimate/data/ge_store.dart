/// 分数估计 · Hive 本地存储（整表读写，单 key JSON）。
library;

import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../domain/ge_models.dart';

const geBoxName = 'score_estimate';
const _kCourses = 'courses';

class GeStore {
  final Box<String> box;

  const GeStore(this.box);

  Future<List<GeCourse>> loadCourses() async {
    final raw = box.get(_kCourses);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final c in decoded)
          if (c is Map<String, dynamic>) GeCourse.fromJson(c),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCourses(List<GeCourse> list) =>
      box.put(_kCourses, jsonEncode([for (final c in list) c.toJson()]));
}
