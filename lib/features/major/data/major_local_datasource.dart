import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/major/domain/major.dart';

class MajorLocalDataSource {
  final Box<Major> _box;

  MajorLocalDataSource(this._box);

  String _keyString(String uuid) => 'Major_$uuid';
  String key(Major major) => _keyString(major.uuid);

  Future<void> saveMajor(Major major) => _box.put(key(major), major);
  Future<void> saveMajorList(List<Major> majors) =>
      Future.wait(majors.map(saveMajor)); // TODO 看运行时是否报错

  Future<void> deleteMajor(String uuid) => _box.delete(_keyString(uuid));

  List<Major> findMajorKnownAs(String name) =>
      _box.values.where((c) => c.isKnownAs(name)).toList();

  // Major? getMajorByUuid(String uuid) => _box.get(key(major));

  // List<T?> getMajorListIn<T extends Major>(FunctionType function) =>
  //     _box.values.map((e) => e.modelIn<T>(function)).toList();
  List<Major> getMajorList() => _box.values.toList();

  bool contains(String uuid) => _box.containsKey(_keyString(uuid));

  Future<int> clearAll() => _box.clear();
}
