enum TimeLimit {
  sinceEnrollment('入学以来', 'sjxz1'),
  academicYear('学年', 'sjxz2'),
  semester('学期', 'sjxz3');

  const TimeLimit(this.name, this.value);

  final String name;
  final String value;
}

enum SemesterType {
  first('第一学期', 1),
  second('第二学期', 2),
  next('第二阶段', -1);

  const SemesterType(this.name, this.code);

  final String name;
  final int code;
}

class AcademicYear {
  final int value;

  AcademicYear._internal(this.value);

  static final Map<int, AcademicYear> _cache = {};

  factory AcademicYear.of(int year) {
    if (year < 1976 || year > 2099) throw Exception('日期超限：year=$year');

    return _cache.putIfAbsent(year, () => AcademicYear._internal(year));
  }

  @override
  String toString() => '$value-${value + 1}学年';

  String get short {
    final str = value.toString();

    assert(str.length == 4);
    return str.substring(str.length - 2);
  }

  static AcademicYear get thisYear => AcademicYear.of(DateTime.now().year);

  AcademicYear get nextYear => AcademicYear.of(value + 1);
  AcademicYear get lastYear => AcademicYear.of(value - 1);

  AcademicYear operator +(int interval) => AcademicYear.of(value + interval);
  AcademicYear operator -(int interval) => AcademicYear.of(value - interval);
}

class Semester {
  final AcademicYear year;
  final SemesterType type;

  const Semester(this.year, this.type);

  @override
  String toString() => '$year${type.name}';

  String get code => '${year.short}${type.code}';
}
