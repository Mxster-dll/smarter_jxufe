/// 志愿活动（学生活动时长统计列表的一行）。
///
/// 列表页 `…/StuVolWork/stu_list.html` 只有 10 列（序号 / 活动名称 / 发起人 /
/// 负责人 / 所属部门 / 类别 / 认定时长 / 申请状态 / 认定状态 / 操作），
/// **没有时间列**；活动时间来自每行的「详情」页（见
/// `data/anti_corruption/volunteer_detail_parser.dart`），由
/// `VolunteerHoursRepository` 在拉列表后逐条补齐到 [startDate] / [endDate]。
library;

class VolunteerActivity {
  final int index;
  final String activityName;
  final String initiator;
  final String responsiblePerson;
  final String department;
  final String activityCategory;
  final String recognizedHours;
  final String applicationStatus;
  final String recognitionStatus;
  final String detailId;
  final String detailType;

  /// 活动开始 / 结束日期（`YYYY-MM-DD`）；详情页取不到时为空串。
  final String startDate;
  final String endDate;

  const VolunteerActivity({
    required this.index,
    required this.activityName,
    required this.initiator,
    required this.responsiblePerson,
    required this.department,
    required this.activityCategory,
    required this.recognizedHours,
    required this.applicationStatus,
    required this.recognitionStatus,
    required this.detailId,
    required this.detailType,
    this.startDate = '',
    this.endDate = '',
  });

  VolunteerActivity copyWith({String? startDate, String? endDate}) {
    return VolunteerActivity(
      index: index,
      activityName: activityName,
      initiator: initiator,
      responsiblePerson: responsiblePerson,
      department: department,
      activityCategory: activityCategory,
      recognizedHours: recognizedHours,
      applicationStatus: applicationStatus,
      recognitionStatus: recognitionStatus,
      detailId: detailId,
      detailType: detailType,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  /// 认定时长（小时）；解析失败按 0 计。
  double get hours => double.tryParse(recognizedHours.trim()) ?? 0;

  /// 活动时间文案；两日期都没有时为空串。
  String get activityTimeText => volunteerTimeText(startDate, endDate);

  /// 用于学年归集的日期：开始日期优先，缺失时回退结束日期。
  DateTime? get activityDate =>
      volunteerParseDate(startDate) ?? volunteerParseDate(endDate);
}

/// 活动时间文案：起止同日只写一天，跨天写 `起 ~ 止`。
String volunteerTimeText(String start, String end) {
  final s = start.trim();
  final e = end.trim();
  if (s.isEmpty && e.isEmpty) return '';
  if (s.isEmpty) return e;
  if (e.isEmpty || s == e) return s;
  return '$s ~ $e';
}

/// 解析日期：兼容 `2026-05-26`（详情页）与 `2026年5月28日`（认定登记表 Word）两种写法。
DateTime? volunteerParseDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final dash = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
  if (dash != null) {
    return DateTime(
      int.parse(dash.group(1)!),
      int.parse(dash.group(2)!),
      int.parse(dash.group(3)!),
    );
  }
  final cn = RegExp(r'^(\d{4})年(\d{1,2})月(\d{1,2})日$').firstMatch(text);
  if (cn != null) {
    return DateTime(
      int.parse(cn.group(1)!),
      int.parse(cn.group(2)!),
      int.parse(cn.group(3)!),
    );
  }
  return null;
}
