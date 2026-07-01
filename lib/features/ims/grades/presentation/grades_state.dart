import 'package:smarter_jxufe/features/ims/grades/domain/grades_query_params.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/time_limit.dart';

/// 成绩页面筛选状态。
class GradesState {
  final TimeLimit timeLimit;
  final bool showRawGrade;
  final bool selectMajor;
  final bool selectMinor;
  final bool selectWeiZhuan;
  final bool onlyNotPassed;
  final String semesterXq;
  final int academicYear;

  const GradesState({
    this.timeLimit = TimeLimit.semester,
    this.showRawGrade = false,
    this.selectMajor = true,
    this.selectMinor = true,
    this.selectWeiZhuan = true,
    this.onlyNotPassed = false,
    this.semesterXq = '0',
    this.academicYear = 2025,
  });

  GradesState copyWith({
    TimeLimit? timeLimit,
    bool? showRawGrade,
    bool? selectMajor,
    bool? selectMinor,
    bool? selectWeiZhuan,
    bool? onlyNotPassed,
    String? semesterXq,
    int? academicYear,
  }) => GradesState(
    timeLimit: timeLimit ?? this.timeLimit,
    showRawGrade: showRawGrade ?? this.showRawGrade,
    selectMajor: selectMajor ?? this.selectMajor,
    selectMinor: selectMinor ?? this.selectMinor,
    selectWeiZhuan: selectWeiZhuan ?? this.selectWeiZhuan,
    onlyNotPassed: onlyNotPassed ?? this.onlyNotPassed,
    semesterXq: semesterXq ?? this.semesterXq,
    academicYear: academicYear ?? this.academicYear,
  );

  /// 主修 / 辅修 / 微专 中选中的数量。
  int get selectedCategoryCount =>
      (selectMajor ? 1 : 0) + (selectMinor ? 1 : 0) + (selectWeiZhuan ? 1 : 0);

  /// 构建查询参数。
  GradesQueryParams get params => GradesQueryParams(
    enrollYear: '2025',
    timeLimit: timeLimit,
    showRawGrade: showRawGrade,
    selectMajor: selectMajor,
    selectMinor: selectMinor,
    selectWeiZhuan: selectWeiZhuan,
    onlyNotPassed: onlyNotPassed,
    semesterXq: timeLimit == TimeLimit.semester ? semesterXq : null,
    academicYear: timeLimit != TimeLimit.sinceEnrollment
        ? academicYear.toString()
        : null,
    academicYearNext: timeLimit != TimeLimit.sinceEnrollment
        ? (academicYear + 1).toString()
        : null,
  );
}
