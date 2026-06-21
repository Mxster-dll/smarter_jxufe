import 'package:smarter_jxufe/features/ims/grades/domain/time_limit.dart';

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
