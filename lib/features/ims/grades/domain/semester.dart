/// 学年学期，如 "2025-2026学年第一学期"。
///
/// 提供两种字符串表示：
/// - [fullName] 完整名称，如 "2025-2026学年第一学期"
/// - [shortCode] 短编号，如 "251"（年份后两位 + 学期号）
class Semester {
  /// 起始年份，如 2025 表示 2025-2026 学年。
  final int startYear;

  /// 学期号：1=第一学期，2=第二学期。
  final int semesterNumber;

  const Semester({required this.startYear, required this.semesterNumber});

  /// 从 "2025-2026学年第一学期" 格式的字符串解析。
  factory Semester.parse(String raw) {
    final match = RegExp(r'(\d{4})-(\d{4})学年第([一二三])学期').firstMatch(raw);
    if (match == null) {
      throw FormatException('无法解析学期字符串: $raw');
    }
    final startYear = int.parse(match.group(1)!);
    const semesterMap = {'一': 1, '二': 2, '三': 3};
    final semesterNumber = semesterMap[match.group(3)!]!;
    return Semester(startYear: startYear, semesterNumber: semesterNumber);
  }

  /// 完整名称，如 "2025-2026学年第一学期"。
  String get fullName {
    const semesterNames = {1: '一', 2: '二', 3: '三'};
    final endYear = startYear + 1;
    final sem = semesterNames[semesterNumber]!;
    return '$startYear-$endYear学年第$sem学期';
  }

  /// 短编号，如 "251"（年份后两位 + 学期号）。
  String get shortCode {
    final yearPart = (startYear % 100).toString().padLeft(2, '0');
    return '$yearPart$semesterNumber';
  }

  @override
  bool operator ==(Object other) =>
      other is Semester &&
      startYear == other.startYear &&
      semesterNumber == other.semesterNumber;

  @override
  int get hashCode => Object.hash(startYear, semesterNumber);

  @override
  String toString() => shortCode;
}
