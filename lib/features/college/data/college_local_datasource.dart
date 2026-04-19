import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/college/domain/college.dart';

class CollegeLocalDataSource {
  final Box<College> _box;

  CollegeLocalDataSource(this._box);

  Future<void> saveCollege(College college) => _box.put(college.uuid, college);
  Future<void> saveCollegeList(List<College> colleges) =>
      Future.wait(colleges.map(saveCollege));

  bool contains(String uuid) => _box.containsKey(uuid);

  College? getCollegeByUuid(String uuid) => _box.get(uuid);
  List<College> getCollegeList() => _box.values.toList();

  List<College> findCollegeKnownAs(String name) =>
      _box.values.where((c) => c.isKnownAs(name)).toList();

  Future<void> deleteCollege(String uuid) => _box.delete(uuid);
  Future<int> clearAll() => _box.clear();
}
