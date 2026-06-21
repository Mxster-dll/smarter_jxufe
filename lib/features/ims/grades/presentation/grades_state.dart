import 'package:smarter_jxufe/features/ims/grades/domain/grades_query_params.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/time_limit.dart';

class GradesState {
  final TimeLimit timeLimit;
  final bool showRawGrade;
  final bool selectMajor;
  final bool selectMinor;
  final bool selectWeiZhuan;
  final bool onlyNotPassed;
  final String semesterXq;

  const GradesState({
    this.timeLimit = TimeLimit.semester,
    this.showRawGrade = false,
    this.selectMajor = true,
    this.selectMinor = true,
    this.selectWeiZhuan = true,
    this.onlyNotPassed = false,
    this.semesterXq = '0',
  });

  GradesState copyWith({
    TimeLimit? timeLimit,
    bool? showRawGrade,
    bool? selectMajor,
    bool? selectMinor,
    bool? selectWeiZhuan,
    bool? onlyNotPassed,
    String? semesterXq,
  }) => GradesState(
    timeLimit: timeLimit ?? this.timeLimit,
    showRawGrade: showRawGrade ?? this.showRawGrade,
    selectMajor: selectMajor ?? this.selectMajor,
    selectMinor: selectMinor ?? this.selectMinor,
    selectWeiZhuan: selectWeiZhuan ?? this.selectWeiZhuan,
    onlyNotPassed: onlyNotPassed ?? this.onlyNotPassed,
    semesterXq: semesterXq ?? this.semesterXq,
  );

  int get selectedCategoryCount =>
      (selectMajor ? 1 : 0) + (selectMinor ? 1 : 0) + (selectWeiZhuan ? 1 : 0);

  GradesQueryParams get params => GradesQueryParams(
    enrollYear: '2025',
    timeLimit: timeLimit,
    showRawGrade: showRawGrade,
    selectMajor: selectMajor,
    selectMinor: selectMinor,
    selectWeiZhuan: selectWeiZhuan,
    onlyNotPassed: onlyNotPassed,
    semesterXq: timeLimit == TimeLimit.semester ? semesterXq : null,
    academicYear: timeLimit != TimeLimit.sinceEnrollment ? '2025' : null,
    academicYearNext: timeLimit != TimeLimit.sinceEnrollment ? '2026' : null,
  );
}
