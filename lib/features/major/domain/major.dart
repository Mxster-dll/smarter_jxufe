import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/constants/hive_type_ids.dart';

part 'major.g.dart';

@HiveType(typeId: kMajorTypeId)
class Major {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String code;

  @HiveField(3)
  final int year;

  @HiveField(4)
  final String collegeName;

  Major({
    required this.id,
    required this.name,
    required this.code,
    required this.year,
    required this.collegeName,
  });

  @override
  String toString() =>
      'Major<$year>[$id](name: $collegeName-$name, code: $code)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Major &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          code == other.code &&
          name == other.name &&
          year == other.year &&
          collegeName == other.collegeName;

  @override
  int get hashCode => '$id|$name|$code|$collegeName|$year'.hashCode;
}
