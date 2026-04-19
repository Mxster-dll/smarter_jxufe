import 'package:hive_flutter/hive_flutter.dart';
import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';

class CollegeLocalDataSource {
  final Box<College> _box;

  /// 索引盒子。键为 `year`，值为学院 UUID 集合
  final Box<List<String>> _indexBox;

  CollegeLocalDataSource(this._box, this._indexBox);

  String _indexKey(int year) => year.toString();

  Future<void> saveCollege(College college, {required int year}) async {
    await _box.put(college.uuid, college);

    final uuidList = _indexBox.get(_indexKey(year)) ?? <String>[];
    if (!uuidList.contains(college.uuid)) uuidList.add(college.uuid);

    await _indexBox.put(_indexKey(year), uuidList);
  }

  Future<void> saveCollegeList(List<College> colleges, {required int year}) =>
      Future.wait(colleges.map((e) => saveCollege(e, year: year)));

  bool contains(String uuid) => _box.containsKey(uuid);

  College? getCollegeByUuid(String uuid) => _box.get(uuid);
  List<College> getCollegeList() => _box.values.toList();

  List<College> findCollegeKnownAs(String name) =>
      _box.values.where((c) => c.isKnownAs(name)).toList();

  List<String>? getCollegeUuidsIn(int year) => _indexBox.get(_indexKey(year));

  /// 注意区分空列表与 null，前者表示该条件下无学院，后者表示本地无缓存
  List<College>? getCollegeListIn(FunctionType function, {required int year}) {
    final uuids = getCollegeUuidsIn(year);
    if (uuids == null) return null;
    return uuids
        .map(getCollegeByUuid)
        .whereType<College>()
        .where((e) => e.functionIdIn.containsKey(function))
        .toList();
  }

  // Future<void> deleteCollege(String uuid) => _box.delete(uuid);

  Future<void> clearAll() async {
    await _box.clear();
    await _indexBox.clear();
  }
}
