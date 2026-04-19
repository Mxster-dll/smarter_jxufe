import 'package:hive_flutter/hive_flutter.dart';
import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class MajorLocalDataSource {
  final Box<Major> _box;

  /// 索引盒子。键为 `${year}_${collegeUuid}`，值为专业 UUID 集合
  final Box<List<String>> _indexBox;

  MajorLocalDataSource(this._box, this._indexBox);

  String _indexKey(int year, String collegeId) => '${year}_$collegeId';

  Future<void> saveMajor(
    Major major, {
    required int year,
    required String collegeId,
  }) {
    _box.put(major.uuid, major);

    final uuidList = getMajorUuidsIn(year, collegeId) ?? <String>[];
    if (!uuidList.contains(major.uuid)) uuidList.add(major.uuid);

    return _indexBox.put(_indexKey(year, collegeId), uuidList);
  }

  Future<void> saveMajorList(
    List<Major> majors, {
    required int year,
    required String collegeId,
  }) => Future.wait(
    majors.map((e) => saveMajor(e, year: year, collegeId: collegeId)),
  );

  bool contains(String uuid) => _box.containsKey(uuid);

  Major? getMajorByUuid(String uuid) => _box.get(uuid);
  List<Major> getMajorList() => _box.values.toList();

  List<Major> findMajorKnownAs(String name) =>
      _box.values.where((c) => c.isKnownAs(name)).toList();

  List<String>? getMajorUuidsIn(int year, String collegeId) =>
      _indexBox.get(_indexKey(year, collegeId));

  /// 注意区分空列表与 null，前者表示该条件下无专业，后者表示本地无缓存
  List<Major>? getMajorListIn(
    FunctionType function, {
    required int year,
    required String collegeId,
  }) => getMajorUuidsIn(year, collegeId)
      ?.map(getMajorByUuid)
      .whereType<Major>()
      .where((e) => e.functionIdIn.containsKey(function))
      .toList();

  // Future<void> deleteMajor(String uuid) => _box.delete(uuid);

  Future<void> clearAll() async {
    await _box.clear();
    await _indexBox.clear();
  }
}
