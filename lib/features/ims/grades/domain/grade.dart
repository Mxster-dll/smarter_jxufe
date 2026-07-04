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

  /// 所属学期短编号，如 "251"
  final String semester;

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
    required this.semester,
  });

  Map<String, dynamic> toMap() => {
    'index': index,
    'courseCode': courseCode,
    'courseName': courseName,
    'credit': credit,
    'category': category,
    'nature': nature,
    'examType': examType,
    'score': score,
    'earnedCredit': earnedCredit,
    'gradePoint': gradePoint,
    'creditGradePoint': creditGradePoint,
    'notes': notes,
    'semester': semester,
  };

  factory Grade.fromMap(Map<String, dynamic> m) => Grade(
    index: m['index'] as String? ?? '',
    courseCode: m['courseCode'] as String? ?? '',
    courseName: m['courseName'] as String? ?? '',
    credit: m['credit'] as String? ?? '',
    category: m['category'] as String? ?? '',
    nature: m['nature'] as String? ?? '',
    examType: m['examType'] as String? ?? '',
    score: m['score'] as String? ?? '',
    earnedCredit: m['earnedCredit'] as String? ?? '',
    gradePoint: m['gradePoint'] as String? ?? '',
    creditGradePoint: m['creditGradePoint'] as String? ?? '',
    notes: m['notes'] as String? ?? '',
    semester: m['semester'] as String? ?? '',
  );
}
