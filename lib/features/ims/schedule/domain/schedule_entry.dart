import 'class_time.dart';

/// 课表条目 —— 对应教务系统课表 HTML 中的一行
///
/// 包含：上课班级信息、课程信息、任课教师、选课状态、教材信息、
/// 以及从"上课时间地点"解析出的多次上课安排
class ScheduleEntry {
  /// 上课班级代码，如 "001567-056"
  final String classCode;

  /// 上课班级名称，如 "主干+"
  final String className;

  /// 课程代码，如 "1004600282"
  final String courseCode;

  /// 课程名称，如 "大学英语II"
  final String courseName;

  /// 总学时
  final int totalHours;

  /// 学分
  final double credits;

  /// 修读性质，如 "初修"
  final String studyNature;

  /// 任课教师代码，如 "1200400772"
  final String teacherCode;

  /// 任课教师姓名，如 "史希平"
  final String teacherName;

  /// 选课状态，如 "选中"
  final String selectionStatus;

  /// 是否外年级/专业选课
  final bool isCrossMajor;

  /// 是否有教材
  final bool hasTextbook;

  /// 上课时间地点列表（一门课可能有多个上课时段）
  final List<ClassTime> classTimes;

  /// 备注
  final String? remark;

  const ScheduleEntry({
    required this.classCode,
    required this.className,
    required this.courseCode,
    required this.courseName,
    required this.totalHours,
    required this.credits,
    required this.studyNature,
    required this.teacherCode,
    required this.teacherName,
    required this.selectionStatus,
    required this.isCrossMajor,
    required this.hasTextbook,
    required this.classTimes,
    this.remark,
  });

  @override
  String toString() =>
      'ScheduleEntry($courseCode $courseName | ${classTimes.length} sessions)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduleEntry &&
          classCode == other.classCode &&
          courseCode == other.courseCode;

  @override
  int get hashCode => Object.hash(classCode, courseCode);
}
