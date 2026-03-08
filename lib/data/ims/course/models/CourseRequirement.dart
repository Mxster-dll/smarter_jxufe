import 'package:hive/hive.dart';

part 'CourseRequirement.g.dart';

@HiveType(typeId: 0, adapterName: 'CourseRequirementAdapter')
enum CourseRequirement {
  @HiveField(0)
  required,
  @HiveField(1)
  elective,
  @HiveField(2)
  restricted,
  @HiveField(3)
  free,
  @HiveField(4)
  excellence,
  @HiveField(5)
  topNotch,
  @HiveField(6)
  innovation,
  @HiveField(7)
  major,
  @HiveField(8)
  unknown;

  String get name => switch (this) {
    required => '必修课',
    elective => '选修课',
    restricted => '限选课',
    free => '任选课',
    excellence => '卓越型',
    topNotch => '拔尖型',
    innovation => '创新创业型',
    major => '专业方向',
    unknown => '未知',
  };

  factory CourseRequirement.parse(String source) => switch (source) {
    '必修课' || '必修' => required,
    '选修课' || '选修' => elective,
    '限选课' || '限选' => restricted,
    '任选课' || '任选' => free,
    '卓越型' || '卓越' => excellence,
    '拔尖型' || '拔尖' => topNotch,
    '创新创业型' || '创新创业' => innovation,
    '专业方向' => major,
    _ => unknown,
  };
}
