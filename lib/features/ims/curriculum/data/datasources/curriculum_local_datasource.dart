import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_key.dart';

class CurriculumLocalDataSource {
  final Box<Curriculum> _box;

  CurriculumLocalDataSource(this._box);

  String keyString(CurriculumKey key) =>
      keyStringFrom(key.year, key.collegeId, key.majorId);

  String keyStringFrom(int year, String collegeId, String majorId) =>
      'curriculum_${year}_${collegeId}_$majorId';

  Future<void> saveCurriculum({
    required int year,
    required String collegeId,
    required String majorId,
    required Curriculum curriculum,
  }) => _box.put(keyStringFrom(year, collegeId, majorId), curriculum);

  Future<void> saveCurriculumByKey(CurriculumKey key, Curriculum curriculum) =>
      _box.put(keyString(key), curriculum);

  bool existCurriculum(int year, String collegeId, String majorId) =>
      _box.containsKey(keyStringFrom(year, collegeId, majorId));

  bool existCurriculumByKey(CurriculumKey key) =>
      _box.containsKey(keyString(key));

  Curriculum? getCurriculum(int year, String collegeId, String majorId) =>
      _box.get(keyStringFrom(year, collegeId, majorId));

  Curriculum? getCurriculumByKey(CurriculumKey key) => _box.get(keyString(key));

  List<Curriculum> getAllCurriculums() => _box.values.toList();

  Future<void> deleteCurriculum(int year, String collegeId, String majorId) =>
      _box.delete(keyStringFrom(year, collegeId, majorId));

  Future<void> deleteCurriculumByKey(CurriculumKey key) =>
      _box.delete(keyString(key));

  Future<void> clearAll() => _box.clear();
}
