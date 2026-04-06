import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/college/domain/college.dart';

class CollegeLocalDataSource {
  final Box<College> _box;

  CollegeLocalDataSource(this._box);

  String _keyString(String uuid) => 'College_$uuid';
  String key(College college) => _keyString(college.uuid);

  Future<void> saveCollege(College college) => _box.put(key(college), college);
  Future<void> saveCollegeList(List<College> colleges) =>
      Future.wait(colleges.map(saveCollege)); // TODO 看运行时是否报错

  Future<void> deleteCollege(String uuid) => _box.delete(_keyString(uuid));

  List<College> findCollegeKnownAs(String name) =>
      _box.values.where((c) => c.isKnownAs(name)).toList();

  // College? getCollegeByUuid(String uuid) => _box.get(key(college));

  // List<T?> getCollegeListIn<T extends College>(FunctionType function) =>
  //     _box.values.map((e) => e.modelIn<T>(function)).toList();
  List<College> getCollegeList() => _box.values.toList();

  bool contains(String uuid) => _box.containsKey(_keyString(uuid));

  Future<int> clearAll() => _box.clear();
}
