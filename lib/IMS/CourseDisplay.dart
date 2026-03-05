import 'package:flutter/foundation.dart';

import 'Course.dart';

extension CourseCategoryDisplay on CourseMainCategory {
  String get displayText => name;
}

extension CourseSubcategoryDisplay on CourseSubcategory {
  String get displayText => name;
}

extension CourseRequirementDisplay on CourseRequirement {
  String get displayText => switch (this) {
    .required => '必修课',
    .elective => '选修课',
    .restricted => '限选课',
    .free => '任选课',
    .excellence => '卓越型',
    .topNotch => '拔尖型',
    .innoEntre => '创新创业型',
    .major => '专业方向',
  };
}

extension CourseNatureDisplay on CourseNature {
  String get displayText => switch (this) {
    .theory => '理论课程',
    .practical => '实践环节',
  };
}

extension CourseImportanceDisplay on CourseImportance {
  String get displayText => switch (this) {
    .core => '主干课程',
    .general => '非主干课程',
  };
}

extension AssessmentMethodDisplay on AssessmentMethod {
  String get displayText => switch (this) {
    .exam => '考试',
    .coursework => '考查',
  };
}
