import 'package:flutter/material.dart';

enum CourseCategory {
  publicCourse2024(2024, '公共课');

  const CourseCategory(this.year, this.chinese);

  final int? year;
  final String chinese;
}

enum CourseSubcategory { publicMathematicsCourse }

enum CourseRequirement { required, elective }

enum CourseNature { theory, practical }

enum CourseImportance { core, general }

enum AssessmentMethod { exam, coursework }

enum Course {
  advancedMathematicsI(
    '1004701034',
    '高等数学I',
    4.0,
    .publicCourse2024,
    .publicMathematicsCourse,
    importance: .core,
    assessmentMethod: .exam,
  );

  const Course(
    this.code,
    this.name,
    this.credit,
    this.category,
    this.subcategory, {
    this.requirement = .required,
    this.nature = .theory,
    this.importance = .general,
    this.assessmentMethod = .coursework,
  });

  final String code;
  final String name;
  final double credit;
  final CourseCategory category;
  final CourseSubcategory subcategory;
  final CourseRequirement requirement;
  final CourseNature nature;
  final CourseImportance importance;
  final AssessmentMethod assessmentMethod;
}

enum CourseFilter { major, minor, all }
