import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_major.dart';

class MajorLocalDataSource {
  final Box<CurriculumMajor> _box;

  MajorLocalDataSource(this._box);

  CurriculumMajor? getMajorById(String id) => _box.get(id);

  Future<void> saveMajor(CurriculumMajor college) =>
      _box.put(college.code, college);
}
