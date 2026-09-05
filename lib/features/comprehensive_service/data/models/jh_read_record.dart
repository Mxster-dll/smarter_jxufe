/// 蛟湖阅读考核记录（SSP 平台 read_list.html 一行）。
///
/// 对应学工平台「蛟湖阅读详单」中当前学生本人的一条记录。
class JhReadRecord {
  /// 序号
  final String index;

  /// 学号
  final String studentId;

  /// 姓名
  final String name;

  /// 学院
  final String college;

  /// 班级
  final String className;

  /// 加分项名称（通常为「蛟湖阅读学分」）
  final String bonusName;

  /// 是否完成入馆学习（是/否，可为空表示未录入）
  final String entryLearning;

  /// 借阅数量是否合格（是/否，可为空表示未录入）
  final String borrowQualified;

  /// 学分
  final String credit;

  /// 详单查看 id（read_detail.html?id=），空表示无可查看详情
  final String detailId;

  const JhReadRecord({
    required this.index,
    required this.studentId,
    required this.name,
    required this.college,
    required this.className,
    required this.bonusName,
    required this.entryLearning,
    required this.borrowQualified,
    required this.credit,
    required this.detailId,
  });
}
