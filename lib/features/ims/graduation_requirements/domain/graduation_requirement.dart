/// 毕业学分要求条目。
class GraduationRequirement {
  /// 序号
  final int index;

  /// 项目名称，如 "2024公共外语选修课"
  final String item;

  /// 学分
  final double credit;

  /// 是否为合计行
  final bool isTotal;

  const GraduationRequirement({
    required this.index,
    required this.item,
    required this.credit,
    this.isTotal = false,
  });
}
