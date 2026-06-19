/// 成绩汇总条目（第二张表）。
class GradeSummary {
  /// 类别，如 "必修课"、"合计"
  final String category;

  /// 修读课程环节数
  final String courseCount;

  /// 学分
  final String credit;

  /// 获得学分
  final String earnedCredit;

  /// 获得绩点
  final String earnedGradePoint;

  /// 获得学分绩点
  final String earnedCreditGradePoint;

  /// 获得平均学分绩点
  final String avgGradePoint;

  const GradeSummary({
    required this.category,
    required this.courseCount,
    required this.credit,
    required this.earnedCredit,
    required this.earnedGradePoint,
    required this.earnedCreditGradePoint,
    required this.avgGradePoint,
  });
}
