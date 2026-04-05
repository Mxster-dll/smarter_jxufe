import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_college.dart';

class CollegeLocalDataSource {
  final Box<CurriculumCollege> _box;

  CollegeLocalDataSource(this._box);

  CurriculumCollege? getCollegeById(String id) => _box.get(id);

  Future<void> saveCollege(CurriculumCollege college) =>
      _box.put(college.code, college);
}
