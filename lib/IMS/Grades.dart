import 'dart:math';

import 'package:smarter_jxufe/ims/AcademicTime.dart';
import 'package:smarter_jxufe/ims/Course.dart';

enum WeightedType {
  courseAll('课程加权（所有学年）', 1),
  courseLastYear('课程加权（上学年）', 2),
  courseLastTerm('课程加权（上学期）', 3),
  // diversion( '分流加权', 4),
  graduate('毕业加权', 5),
  minor('辅修加权', 6),
  gradRec('推免加权', 7);

  const WeightedType(this.name, this.id);

  final String name;
  final int id;
}

extension Sum<T extends num> on Iterable<T> {
  double get sum {
    double sum = 0;
    for (final i in this) {
      sum += i;
    }

    return sum;
  }
}

extension Average<T> on Iterable<T> {
  double average(num Function(T) value, num Function(T) weight) {
    double weightSum = map((e) => value(e) * weight(e)).sum;
    double totalWeight = map((e) => weight(e)).sum;

    return (totalWeight == 0) ? 0 : weightSum / totalWeight;
  }
}

extension WeightedAverage on Iterable<CourseGrade> {
  double get weighted => average((sg) => sg.score, (sg) => sg.credit);
  double get overallWeighted =>
      0.7 * coreCourses.weighted + 0.3 * nonCoreCourses.weighted;
  double get gradePointAverage =>
      average((sg) => sg.gradePoint, (sg) => sg.credit);
}

extension Filter on Iterable<CourseGrade> {
  Iterable<CourseGrade> get all => this;
  Iterable<CourseGrade> get lastYear =>
      where((grade) => grade.semester.inLastYear);
  Iterable<CourseGrade> get lastSemester =>
      where((grade) => grade.semester == AcademicPeriod.now.lastSemester);
  Iterable<CourseGrade> get before7thSemester => where((grade) => true);

  Iterable<CourseGrade> get coreCourses =>
      where((grade) => grade.course.importance == .core);
  Iterable<CourseGrade> get nonCoreCourses =>
      where((grade) => grade.course.importance == .general);
  Iterable<CourseGrade> get ofTheoryCourse =>
      where((grade) => grade.course.nature == .theory);
  Iterable<CourseGrade> get ofPracticalCourse =>
      where((grade) => grade.course.nature == .practical);
}

class GradeTable {
  final List<CourseGrade> grades;
  final Map<String, WeightedGrade> weightedGrades;

  GradeTable(this.grades, this.weightedGrades);

  double get courseAllWeighted => grades.ofTheoryCourse.weighted;
  double get courseLastYearWeighted => grades.ofTheoryCourse.lastYear.weighted;
  double get courseLastSemesterWeighted =>
      grades.ofTheoryCourse.lastSemester.weighted;
  double get graduateWeighted => grades.ofTheoryCourse.overallWeighted;
  double get gradRecWeighted =>
      grades.ofTheoryCourse.before7thSemester.overallWeighted;

  double get gpa => grades.all.gradePointAverage;
}

extension _Grades on double {
  bool get hasPassed => this >= 60;
}

enum CourseAttempt {
  first('初修'),
  retake('重修');

  const CourseAttempt(this.chinese);

  final String chinese;

  @override
  String toString() => chinese;
}

class CourseGrade {
  final Course course;
  final CourseAttempt attempt;
  final Semester semester;
  final double score;
  final double credit;
  final double gradePoint;
  late final double gradePointCredit;
  final String remark;

  CourseGrade(
    this.course,
    this.score,
    this.semester, {
    this.attempt = .first,
    this.remark = '',
  }) : credit = score.hasPassed ? course.credit : 0,
       gradePoint = min(0, course.credit / 10 - 5) {
    gradePointCredit = credit * gradePoint;
  }
}

class WeightedGrade {
  final String grade;
  final int classRank, majorRank, gradeRank;

  WeightedGrade(this.grade, this.classRank, this.majorRank, this.gradeRank);

  static WeightedGrade fromMap(Map<String, dynamic> weightedGrade) {
    final grade = weightedGrade['课程加权成绩'];
    if (grade == null) throw Exception('缺少 "课程加权成绩"');

    int extractRank(String key) {
      final rankText = weightedGrade[key];
      if (rankText == null) throw Exception('缺少 "$key"');

      final rank = int.tryParse(rankText);
      if (rank == null) throw Exception('"$key" 格式错误');

      return rank;
    }

    return WeightedGrade(
      grade,
      extractRank('班级排名'),
      extractRank('专业排名'),
      extractRank('年级排名'),
    );
  }

  @override
  String toString() =>
      '''

::加权成绩排名::
课程加权成绩: $grade
班级排名: $classRank
专业排名: $majorRank
年级排名: $gradeRank

''';
}
