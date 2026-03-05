import 'package:get_storage/get_storage.dart';

import 'package:smarter_jxufe/ims/AcademicTime.dart';

class CourseMainCategory {
  static final box = GetStorage();
  static final Map<String, CourseMainCategory> _cache = loadCache();

  final String name;

  const CourseMainCategory._(this.name);

  factory CourseMainCategory(String name) {
    if (!_cache.containsKey(name)) {
      _cache[name] = CourseMainCategory._(name);
      box.write('cache', _cache);
    }

    return _cache[name]!;
  }

  static Map<String, CourseMainCategory> loadCache() => {
    for (final name in box.read<List<String>>('cache') ?? [])
      name: CourseMainCategory(name),
  };
}

class CourseSubcategory {
  static final box = GetStorage();
  static final Map<String, CourseSubcategory> _cache = loadCache();

  final String name;

  const CourseSubcategory._(this.name);

  factory CourseSubcategory(String name) {
    if (!_cache.containsKey(name)) {
      _cache[name] = CourseSubcategory._(name);
      box.write('cache', _cache);
    }

    return _cache[name]!;
  }

  static Map<String, CourseSubcategory> loadCache() => {
    for (final name in box.read<List<String>>('cache') ?? [])
      name: CourseSubcategory(name),
  };
}

class TertiaryCategory {
  static final box = GetStorage();
  static final Map<String, TertiaryCategory> _cache = loadCache();

  final String name;

  const TertiaryCategory._(this.name);

  factory TertiaryCategory(String name) {
    if (!_cache.containsKey(name)) {
      _cache[name] = TertiaryCategory._(name);
      box.write('cache', _cache);
    }

    return _cache[name]!;
  }

  static Map<String, TertiaryCategory> loadCache() => {
    for (final name in box.read<List<String>>('cache') ?? [])
      name: TertiaryCategory(name),
  };
}

enum CourseRequirement {
  required,
  elective,
  restricted,
  free,
  excellence,
  topNotch,
  innoEntre,
  major;

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

  factory CourseNature.parse(String source) => switch (source) {
    '理论课程' || '理论' => .theory,
    '实践环节' || '实践' => .practical,
    _ => throw FormatException('CourseNature.parse($source)转换失败'),
  };
}

enum CourseImportance {
  core,
  general;

  factory CourseImportance.parse(String source) => switch (source) {
    '主干课程' || '主干' => .core,
    '非主干课程' || '非主干' => .general,
    _ => throw FormatException('CourseImportance.parse($source)转换失败'),
  };
}

enum AssessmentMethod {
  exam,
  coursework;

  factory AssessmentMethod.parse(String source) => switch (source) {
    '考试' => .exam,
    '考查' => .coursework,
    _ => throw FormatException('AssessmentMethod.parse($source)转换失败'),
  };
}

class Course {
  final String code;
  final String name;
  final double credit;
  final CreditHour creditHour;
  final CourseMainCategory category;
  final CourseSubcategory subcategory;
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
    this.category,
    this.subcategory,
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
  late final CourseMainCategory category;
  late final CourseSubcategory subcategory;
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

  static final fourth = [];
  set categories(String categories) {
    final parts = categories.split('/');

    if (parts.length != 3) {
      fourth.add(categories);
    }

    category = CourseMainCategory(parts[0]);
    subcategory = CourseSubcategory(parts[1]);
    requirement = CourseRequirement.parse(parts.last);
  }

  Course build() => Course(
    code,
    name,
    credit,
    creditHour,
    category,
    subcategory,
    requirement,
    nature,
    importance,
    assessmentMethod,
    identification,
  );
}

enum CourseFilter { major, minor, all }
