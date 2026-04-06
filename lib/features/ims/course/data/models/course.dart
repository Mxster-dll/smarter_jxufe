import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/course/data/models/assessment_method.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_importance.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_nature.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/course_requirement.dart';
import 'package:smarter_jxufe/features/ims/course/data/models/credit_hour.dart';

part 'course.freezed.dart';
part 'course.g.dart';

/// ### 课程
/// 区别于学科，课程对于不同学生是不一样的，尤其是不同学院的学生
@HiveType(typeId: 2, adapterName: 'CourseAdapter')
@freezed
class Course with _$Course {
  const factory Course({
    @HiveField(1) required String code,
    @HiveField(2) required String name,
    @HiveField(3) required double credit,
    @HiveField(4) required CreditHour creditHour,
    @HiveField(5) required String mainCategory,
    @HiveField(6) required String subCategory,
    @HiveField(7) required String? tertiaryCategory,
    @HiveField(8) required CourseRequirement requirement,
    @HiveField(9) required CourseNature nature,
    @HiveField(10) required CourseImportance importance,
    @HiveField(11) required AssessmentMethod assessmentMethod,
    @HiveField(12) required String identification,
  }) = _Course;

  factory Course.fromJson(Map<String, dynamic> json) => _$CourseFromJson(json);
}
