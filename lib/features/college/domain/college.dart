import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/constants/hive_type_ids.dart';

part 'college.g.dart';

@HiveType(typeId: kCollegeTypeId)
class College {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String code;

  College(this.id, this.name, this.code);

  @override
  String toString() => 'College[$id](name: $name, code: $code)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is College &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          code == other.code;

  @override
  int get hashCode => '$id|$name|$code'.hashCode;
}
