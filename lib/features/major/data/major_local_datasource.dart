import 'package:hive_flutter/hive_flutter.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class MajorLocalDataSource {
  final Box<Major> _box;

  MajorLocalDataSource(this._box);

  Future<void> saveMajor(Major major) => _box.put(major.uuid, major);
  Future<void> saveMajorList(List<Major> majors) =>
      Future.wait(majors.map(saveMajor));

  bool contains(String uuid) => _box.containsKey(uuid);

  Major? getMajorByUuid(String uuid) => _box.get(uuid);
  List<Major> getMajorList() => _box.values.toList();

  List<Major> findMajorKnownAs(String name) =>
      _box.values.where((c) => c.isKnownAs(name)).toList();

  Future<void> deleteMajor(String uuid) => _box.delete(uuid);
  Future<int> clearAll() => _box.clear();
}
