import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_key.dart';

class CurriculumLocalDataSource {
  final Box<Curriculum> _box;

  CurriculumLocalDataSource(this._box);

  String toKeyString(CurriculumKey key) =>
      keyString(key.year, key.college.name, key.major.name);

  String keyString(int year, String collegeName, String majorName) =>
      'curriculum_${year}_${collegeName}_$majorName';

  Future<void> saveCurriculum({
    required int year,
    required String collegeName,
    required String majorName,
    required Curriculum curriculum,
  }) => _box.put(keyString(year, collegeName, majorName), curriculum);

  Future<void> saveCurriculumByKey(CurriculumKey key, Curriculum curriculum) =>
      _box.put(toKeyString(key), curriculum);

  bool existCurriculum(int year, String collegeName, String majorName) =>
      _box.containsKey(keyString(year, collegeName, majorName));

  bool existCurriculumByKey(CurriculumKey key) =>
      _box.containsKey(toKeyString(key));

  Curriculum? getCurriculum(int year, String collegeName, String majorName) =>
      _box.get(keyString(year, collegeName, majorName));

  Curriculum? getCurriculumByKey(CurriculumKey key) =>
      _box.get(toKeyString(key));

  List<Curriculum> getAllCurriculums() => _box.values.toList();

  Future<void> deleteCurriculum(
    int year,
    String collegeName,
    String majorName,
  ) => _box.delete(keyString(year, collegeName, majorName));

  Future<void> deleteCurriculumByKey(CurriculumKey key) =>
      _box.delete(toKeyString(key));

  Future<void> clearAll() => _box.clear();
}
