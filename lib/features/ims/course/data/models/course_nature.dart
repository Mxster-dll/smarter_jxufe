import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/constants/hive_type_ids.dart';

part 'course_nature.g.dart';

/// ### 课程性质
/// （理论/实践）
@HiveType(typeId: kCourseNatureTypeId)
enum CourseNature {
  @HiveField(0)
  theory,
  @HiveField(1)
  practical,
  @HiveField(2)
  unknown;

  String get displayName => switch (this) {
    theory => '理论课程',
    practical => '实践环节',
    unknown => '未知',
  };

  factory CourseNature.parse(String source) => switch (source) {
    '理论课程' || '理论' => theory,
    '实践环节' || '实践' => practical,
    _ => unknown,
  };
}
