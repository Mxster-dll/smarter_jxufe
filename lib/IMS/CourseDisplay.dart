import 'Course.dart';

extension CourseCategoryDisplay on CourseCategory {
  String get displayText => '$year$chinese';
}

extension CourseSubcategoryDisplay on CourseSubcategory {
  String get displayText => switch (this) {
    .publicMathematicsCourse => '',
  };
}

extension CourseRequirementDisplay on CourseRequirement {
  String get displayText => switch (this) {
    .required => '必修课',
    .elective => '选修课',
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
