import 'package:smarter_jxufe/IMS/Subject.dart';

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

class GradeTable {
  final List<SubjectGrade> grades;
  final double gpa;

  GradeTable(this.grades, this.gpa);
}

class SubjectGrade {
  final Subject subject;
  final String courseNature;
  final double score;
  final double credit;
  final double gradePoint;
  final double gradePointCredit;
  final String remark;

  SubjectGrade(
    this.subject,
    this.courseNature,
    this.score,
    this.credit,
    this.gradePoint,
    this.gradePointCredit,
    this.remark,
  );
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
