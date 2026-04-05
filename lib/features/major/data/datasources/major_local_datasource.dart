import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/function_type.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';
import 'package:smarter_jxufe/features/major/domain/unified_major.dart';

class MajorLocalDataSource {
  final Box<UnifiedMajor> _box;

  MajorLocalDataSource(this._box);

  String key(UnifiedMajor major) => 'UnifiedMajor${major.uuid}';

  Future<void> saveMajor(UnifiedMajor major) => _box.put(key(major), major);

  Future<void> deleteMajor(UnifiedMajor major) => _box.delete(key(major));

  UnifiedMajor? getMajorByUuid(UnifiedMajor major) => _box.get(key(major));

  List<T?> getMajorListIn<T extends Major>(FunctionType function) =>
      _box.values.map((e) => e.modelIn<T>(function)).toList();
  List<UnifiedMajor> getAllMajors() => _box.values.toList();

  Future<int> clearAll() => _box.clear();
}
