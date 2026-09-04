/// 学生基础信息（第二课堂成绩单抬头）。
class SecondClassStudent {
  final String name;
  final String studentId;
  final String college;
  final String gender;
  final String className;
  final String major;

  const SecondClassStudent({
    required this.name,
    required this.studentId,
    required this.college,
    required this.gender,
    required this.className,
    required this.major,
  });
}

/// 成绩单中的一条学分记录。
class SecondClassRecord {
  /// 获奖/活动年份；志愿服务总计行此字段为空。
  final String year;

  /// 项目/活动名称。
  final String projectName;

  /// 获得学分。
  final double credit;

  /// 所属平台（思想引领 / 学术讲座 / 校园文化 / 志愿服务 等）。
  final String platform;

  const SecondClassRecord({
    required this.year,
    required this.projectName,
    required this.credit,
    required this.platform,
  });
}

/// 第二课堂成绩单（/admin/tzz/dektRecordSummary/schoolReport.html）。
class SecondClassCreditReport {
  final SecondClassStudent student;

  /// 明细记录（含「志愿服务总计xx小时」汇总行，其 year 为空）。
  final List<SecondClassRecord> records;

  final double totalCredit;
  final double validCredit;

  /// 十二个平台的学分汇总（有序：思想引领、学术论文、校园文化……）。
  final Map<String, double> platformCredits;

  /// 志愿服务累计小时数（从「志愿服务总计xx小时」行解析）。
  final double volunteerHours;

  const SecondClassCreditReport({
    required this.student,
    required this.records,
    required this.totalCredit,
    required this.validCredit,
    required this.platformCredits,
    required this.volunteerHours,
  });
}

/// 学分预警板块行（首页学分预警表）。
class CreditBoardRow {
  final String name;

  /// 已获学分（子板块行可能无应获/标准/状态，仅展示学分）。
  final double earned;

  /// 至少应获学分；无硬性要求时为空。
  final double? required;

  /// 认定标准文本；无要求时为空。
  final String? standard;

  /// 达标状态文本（已达标/未达标）；无要求时为空。
  final String? status;

  /// 该行是否有达标要求（即 [required]/[status] 是否齐全）。
  bool get hasRequirement =>
      required != null && status != null && status!.isNotEmpty;

  /// 是否达标（仅当 [hasRequirement] 时有效）。
  bool get passed => hasRequirement && status == '已达标';

  const CreditBoardRow({
    required this.name,
    required this.earned,
    required this.required,
    required this.standard,
    required this.status,
  });
}

/// 第二课堂学分总览（综合成绩单 + 学分预警板）。
class SecondClassOverview {
  final SecondClassCreditReport report;

  /// 预警板数据行（不含表头与总计行）。
  final List<CreditBoardRow> boardRows;

  /// 阶段学分要求文案（如「大一下学期4月份前须获得1学分」）。
  final List<String> milestones;

  /// 预警板总计：应获总学分（通常为 6）。
  final double totalRequired;

  /// 预警板总计是否达标。
  final bool totalPassed;

  const SecondClassOverview({
    required this.report,
    required this.boardRows,
    required this.milestones,
    required this.totalRequired,
    required this.totalPassed,
  });
}
