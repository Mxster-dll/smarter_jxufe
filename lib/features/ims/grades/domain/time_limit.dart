/// 时间限制。
enum TimeLimit {
  sinceEnrollment('入学以来', 'sjxz1'),
  academicYear('学年', 'sjxz2'),
  semester('学期', 'sjxz3');

  const TimeLimit(this.label, this.value);
  final String label;
  final String value;
}
