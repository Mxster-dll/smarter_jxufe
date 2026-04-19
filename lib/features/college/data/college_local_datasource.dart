import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';

class CollegeLocalDataSource {
  final Box<College> _box;

  /// 索引盒子。键为 `year`，值为学院 UUID 集合
  final Box<Set<String>> _indexBox;

  CollegeLocalDataSource(this._box, this._indexBox);

  Future<void> saveCollege(College college) => _box.put(college.uuid, college);
  Future<void> saveCollegeList(List<College> colleges) =>
      Future.wait(colleges.map(saveCollege));

  bool contains(String uuid) => _box.containsKey(uuid);

  College? getCollegeByUuid(String uuid) => _box.get(uuid);
  List<College> getCollegeList() => _box.values.toList();

  List<College> findCollegeKnownAs(String name) =>
      _box.values.where((c) => c.isKnownAs(name)).toList();

  /// 注意区分空列表与 null，前者表示该条件下无专业，后者表示本地无缓存
  List<College>? getCollegeListIn(FunctionType function, {required int year}) =>
      _indexBox
          .get(year.toString())
          ?.map(getCollegeByUuid)
          .whereType<College>()
          .where((e) => e.functionIdIn.containsKey(function))
          .toList();

  Future<void> deleteCollege(String uuid) => _box.delete(uuid);
  Future<int> clearAll() => _box.clear();
}
