/// 成绩条目。
class Grade {
  /// 序号
  final String index;

  /// 课程代码，如 1002300011
  final String courseCode;

  /// 课程名称，如 "当代大学生国家安全教育"
  final String courseName;

  /// 学分
  final String credit;

  /// 类别，如 "2024公共课/国家安全教育/必修课"
  final String category;

  /// 修读性质，如 "初修"
  final String nature;

  /// 考核方式，如 "考试"、"考查"
  final String examType;

  /// 成绩
  final String score;

  /// 获得学分
  final String earnedCredit;

  /// 绩点
  final String gradePoint;

  /// 学分绩点
  final String creditGradePoint;

  /// 备注
  final String notes;

  const Grade({
    required this.index,
    required this.courseCode,
    required this.courseName,
    required this.credit,
    required this.category,
    required this.nature,
    required this.examType,
    required this.score,
    required this.earnedCredit,
    required this.gradePoint,
    required this.creditGradePoint,
    required this.notes,
  });
}

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

/// 成绩查询完整结果。
class GradesResult {
  final List<Grade> grades;
  final List<GradeSummary> summaries;

  const GradesResult({required this.grades, required this.summaries});
}

/// 时间限制。
enum TimeLimit {
  sinceEnrollment('入学以来', 'sjxz1'),
  academicYear('学年', 'sjxz2'),
  semester('学期', 'sjxz3');

  const TimeLimit(this.label, this.value);
  final String label;
  final String value;
}

/// 成绩查询参数。
class GradesQueryParams {
  final String enrollYear;
  final TimeLimit timeLimit;
  final bool showRawGrade;
  final bool selectMajor;
  final bool selectMinor;
  final bool selectWeiZhuan;
  final bool onlyNotPassed;
  final String? semesterXq;
  final String? academicYear;
  final String? academicYearNext;

  const GradesQueryParams({
    required this.enrollYear,
    this.timeLimit = TimeLimit.semester,
    this.showRawGrade = false,
    this.selectMajor = true,
    this.selectMinor = true,
    this.selectWeiZhuan = true,
    this.onlyNotPassed = false,
    this.semesterXq,
    this.academicYear,
    this.academicYearNext,
  });

  @override
  bool operator ==(Object other) =>
      other is GradesQueryParams &&
      enrollYear == other.enrollYear &&
      timeLimit == other.timeLimit &&
      showRawGrade == other.showRawGrade &&
      selectMajor == other.selectMajor &&
      selectMinor == other.selectMinor &&
      selectWeiZhuan == other.selectWeiZhuan &&
      onlyNotPassed == other.onlyNotPassed &&
      semesterXq == other.semesterXq &&
      academicYear == other.academicYear &&
      academicYearNext == other.academicYearNext;

  @override
  int get hashCode => Object.hash(
    enrollYear,
    timeLimit,
    showRawGrade,
    selectMajor,
    selectMinor,
    selectWeiZhuan,
    onlyNotPassed,
    semesterXq,
    academicYear,
    academicYearNext,
  );
}
