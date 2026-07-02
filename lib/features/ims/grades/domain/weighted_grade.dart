/// 加权成绩排名结果。
class WeightedGrade {
  /// 加权成绩（字符串形式，如 "85.32"）
  final String grade;

  /// 班级排名
  final int classRank;

  /// 专业排名
  final int majorRank;

  /// 年级排名
  final int gradeRank;

  const WeightedGrade({
    required this.grade,
    required this.classRank,
    required this.majorRank,
    required this.gradeRank,
  });
}
