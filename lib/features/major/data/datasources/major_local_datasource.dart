import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/major/domain/major.dart';

class MajorLocalDataSource {
  /// 以 [Major] 的 [name] 为键
  final Box<Major> _box;

  MajorLocalDataSource(this._box);

  String _key(int year, String collegeName, String name) =>
      '${year}_${collegeName}_$name';

  String _keyFrom(Major major) =>
      _key(major.year, major.collegeName, major.name);

  Future<void> saveMajor(Major major) => _box.put(_keyFrom(major), major);

  Future<void> saveMajorList(List<Major> majors) =>
      Future.wait(majors.map(saveMajor));

  bool hasCache(
    String name, {
    required int year,
    required String collegeName,
  }) => _box.containsKey(_key(year, collegeName, name));

  Major? getMajor(
    String name, {
    required int year,
    required String collegeName,
  }) => _box.get(_key(year, collegeName, name));

  List<Major> getAllMajorIn(String collegeName, {required int year}) => _box
      .values
      .where((e) => e.collegeName == collegeName && e.year == year)
      .toList();

  Future<void> deleteMajor(Major major) => _box.delete(_keyFrom(major));
  Future<int> clear() => _box.clear();
}
