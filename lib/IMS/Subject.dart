enum SubjectCategory {
  publicCourse2024,
  compulsoryCourse,
  publicMathematicsCourse,
}

enum Subject {
  advancedMathematicsI('1004701034', '高等数学I', 4.0, [
    .compulsoryCourse,
    .publicMathematicsCourse,
    .publicCourse2024,
  ], '考试');

  const Subject(
    this.code,
    this.name,
    this.credit,
    this.category,
    this.assessmentMethod,
  );

  final String code;
  final String name;
  final double credit;
  final List<SubjectCategory> category;
  final String assessmentMethod;
}

enum SubjectFilter { major, minor, all }
