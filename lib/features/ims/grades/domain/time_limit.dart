/// 时间限制。
enum TimeLimit {
  sinceEnrollment('全部', 'sjxz1'), // 在原系统中叫“入学以来”
  academicYear('学年', 'sjxz2'),
  semester('学期', 'sjxz3');

  const TimeLimit(this.label, this.value);
  final String label;
  final String value;
}
