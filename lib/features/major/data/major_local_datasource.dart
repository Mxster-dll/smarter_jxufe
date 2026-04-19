import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class MajorLocalDataSource {
  final Box<Major> _box;

  /// 索引盒子。键为 `${year}_${collegeUuid}`，值为专业 UUID 集合
  final Box<Set<String>> _indexBox;

  MajorLocalDataSource(this._box, this._indexBox);

  Future<void> saveMajor(Major major) => _box.put(major.uuid, major);
  Future<void> saveMajorList(List<Major> majors) =>
      Future.wait(majors.map(saveMajor));

  bool contains(String uuid) => _box.containsKey(uuid);

  Major? getMajorByUuid(String uuid) => _box.get(uuid);
  List<Major> getMajorList() => _box.values.toList();

  List<Major> findMajorKnownAs(String name) =>
      _box.values.where((c) => c.isKnownAs(name)).toList();

  /// 注意区分空列表与 null，前者表示该条件下无专业，后者表示本地无缓存
  List<Major>? getMajorListIn(
    FunctionType function, {
    required int year,
    required String collegeId,
  }) => _indexBox
      .get('${year}_$collegeId')
      ?.map(getMajorByUuid)
      .whereType<Major>()
      .where((e) => e.functionIdIn.containsKey(function))
      .toList();

  Future<void> deleteMajor(String uuid) => _box.delete(uuid);
  Future<int> clearAll() => _box.clear();
}
