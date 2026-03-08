import 'package:hive/hive.dart';

part 'CourseImportance.g.dart';

@HiveType(typeId: 5, adapterName: 'CourseImportanceAdapter')
enum CourseImportance {
  @HiveField(0)
  core,
  @HiveField(1)
  general,
  @HiveField(2)
  unknown;

  String get name => switch (this) {
    core => '主干课程',
    general => '非主干课程',
    unknown => '未知',
  };

  factory CourseImportance.parse(String source) => switch (source) {
    '主干课程' || '主干' => core,
    '非主干课程' || '非主干' => general,
    _ => unknown,
  };
}
