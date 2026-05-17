import 'package:hive/hive.dart';

import 'package:smarter_jxufe/features/college/domain/college.dart';

class CollegeLocalDataSource {
  /// 以 [College] 的 [name] 为键
  final Box<College> _box;

  CollegeLocalDataSource(this._box);

  Future<void> saveCollege(College college) => _box.put(college.name, college);
  Future<void> saveCollegeList(List<College> colleges) =>
      Future.wait(colleges.map((e) => saveCollege(e)));

  bool hasCache(String name) => _box.containsKey(name);

  College? getCollege(String name) => _box.get(name);
  List<College> getAllCollege() => _box.values.toList();

  Future<void> deleteCollege(College college) => _box.delete(college.name);
  Future<int> clear() => _box.clear();
}
