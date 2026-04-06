import 'package:smarter_jxufe/old/ims/data/repositories/ims/AcademicTime.dart';

enum CourseRequirement {
  required,
  elective,
  restricted,
  free,
  excellence,
  topNotch,
  innoEntre,
  major;

  String get name => switch (this) {
    .required => '必修课',
    .elective => '选修课',
    .restricted => '限选课',
    .free => '任选课',
    .excellence => '卓越型',
    .topNotch => '拔尖型',
    .innoEntre => '创新创业型',
    .major => '专业方向',
  };

  factory CourseRequirement.parse(String source) => switch (source) {
    '必修课' || '必修' => .required,
    '选修课' || '选修' => .elective,
    '限选课' || '限选' => .restricted,
    '任选课' || '任选' => .free,
    '卓越型' || '卓越' => .excellence,
    '拔尖型' || '拔尖' => .topNotch,
    '创新创业型' || '创新创业' => innoEntre,
    '专业方向' => .major,
    _ => throw FormatException('CourseRequirement.parse($source)转换失败'),
  };
}

enum CourseNature {
  theory,
  practical;

  String get name => switch (this) {
    .theory => '理论课程',
    .practical => '实践环节',
  };

  factory CourseNature.parse(String source) => switch (source) {
    '理论课程' || '理论' => .theory,
    '实践环节' || '实践' => .practical,
    _ => throw FormatException('CourseNature.parse($source)转换失败'),
  };
}

enum CourseImportance {
  core,
  general;

  String get name => switch (this) {
    .core => '主干课程',
    .general => '非主干课程',
  };

  factory CourseImportance.parse(String source) => switch (source) {
    '主干课程' || '主干' => .core,
    '非主干课程' || '非主干' => .general,
    _ => throw FormatException('CourseImportance.parse($source)转换失败'),
  };
}

enum AssessmentMethod {
  exam,
  coursework;

  String get name => switch (this) {
    .exam => '考试',
    .coursework => '考查',
  };

  factory AssessmentMethod.parse(String source) => switch (source) {
    '考试' => .exam,
    '考查' => .coursework,
    _ => throw FormatException('AssessmentMethod.parse($source)转换失败'),
  };
}

/// 区别于学科，课程对于不同学生是不一样的，尤其是不同学院的学生
class Course {
  final String code;
  final String name;
  final double credit;
  final CreditHour creditHour;

  final String mainCategory;
  final String subCategory;
  final String? tertiaryCategory;

  final CourseRequirement requirement;
  final CourseNature nature;
  final CourseImportance importance;
  final AssessmentMethod assessmentMethod;
  final String identification;

  const Course(
    this.code,
    this.name,
    this.credit,
    this.creditHour,
    this.mainCategory,
    this.subCategory,
    this.tertiaryCategory,
    this.requirement,
    this.nature,
    this.importance,
    this.assessmentMethod,
    this.identification,
  );

  @override
  String toString() => name;
}

class CourseBuilder {
  late final String code;
  late final String name;
  late final double credit;
  late final CreditHour creditHour;

  late final String mainCategory;
  late final String subCategory;
  late final String? tertiaryCategory;

  late final CourseRequirement requirement;
  late final CourseNature nature;
  late final CourseImportance importance;
  late final AssessmentMethod assessmentMethod;
  late final String identification;

  set codeAndName(String codeAndName) {
    Match? match = RegExp(r'\[(\d+)\](.+)').firstMatch(codeAndName);
    if (match == null) throw FormatException('课程格式错误: $codeAndName');

    code = match.group(1)!;
    name = match.group(2)!;
  }

  set categories(String categories) {
    final parts = categories.split('/');

    mainCategory = parts[0];
    subCategory = parts[1];
    tertiaryCategory = (parts.length == 4) ? parts[2] : null;

    requirement = CourseRequirement.parse(parts.last);
  }

  Course build() => Course(
    code,
    name,
    credit,
    creditHour,
    mainCategory,
    subCategory,
    tertiaryCategory,
    requirement,
    nature,
    importance,
    assessmentMethod,
    identification,
  );
}

enum CourseFilter { major, minor, all }
