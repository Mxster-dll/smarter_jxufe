import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class CurriculumState {
  final bool isLoadingColleges;
  final bool isLoadingMajors;
  final bool isLoadingTable;

  /// 整页级错误（学院 / 专业 / **理论课程表**取数失败）—— 界面画一条 InfoBar，
  /// 已有的内容照常显示。开课学期与实践环节各自的失败另有字段（它们只影响本段）。
  final String? errorMessage;
  final List<College> colleges;
  final College? selectedCollege;
  final List<int> years; // 可选年份列表，如 2010..2025
  final int? selectedYear;
  final List<Major> majors;
  final Major? selectedMajor;
  final Curriculum? curriculum;

  /// 理论课程**每一门的开课学期**（`学年学期` 原文，与 `curriculum.courses` 同序）。
  /// 空列表 = 还没取到（界面按「未排定」显示，并如实提示没取到）。
  final List<String> semesters;
  final bool isLoadingSemesters;

  /// 开课学期单独失败（不影响课程表本身）—— 界面只在「按开课学期」聚合时提示。
  final String? semestersError;

  /// 培养方案**第二张表**：实践环节（`pyfa.sjhj.html` / `tableId=2509`）。
  final PracticeCurriculum? practice;
  final bool isLoadingPractice;
  final String? practiceError;

  CurriculumState({
    this.isLoadingColleges = false,
    this.isLoadingMajors = false,
    this.isLoadingTable = false,
    this.errorMessage,
    this.colleges = const [],
    this.selectedCollege,
    List<int>? years,
    this.selectedYear,
    this.majors = const [],
    this.selectedMajor,
    this.curriculum,
    this.semesters = const [],
    this.isLoadingSemesters = false,
    this.semestersError,
    this.practice,
    this.isLoadingPractice = false,
    this.practiceError,
  }) : years = years ?? List.generate(16, (i) => 2025 - i);

  CurriculumState copyWith({
    bool? isLoadingColleges,
    bool? isLoadingMajors,
    bool? isLoadingTable,
    Object? errorMessage = _sentinel,
    List<College>? colleges,
    Object? selectedCollege = _sentinel,
    List<int>? years,
    Object? selectedYear = _sentinel,
    List<Major>? majors,
    Object? selectedMajor = _sentinel,
    Object? curriculum = _sentinel,
    List<String>? semesters,
    bool? isLoadingSemesters,
    Object? semestersError = _sentinel,
    Object? practice = _sentinel,
    bool? isLoadingPractice,
    Object? practiceError = _sentinel,
  }) {
    return CurriculumState(
      isLoadingColleges: isLoadingColleges ?? this.isLoadingColleges,
      isLoadingMajors: isLoadingMajors ?? this.isLoadingMajors,
      isLoadingTable: isLoadingTable ?? this.isLoadingTable,
      errorMessage:
          identical(errorMessage, _sentinel)
              ? this.errorMessage
              : errorMessage as String?,
      colleges: colleges ?? this.colleges,
      selectedCollege:
          identical(selectedCollege, _sentinel)
              ? this.selectedCollege
              : selectedCollege as College?,
      years: years ?? this.years,
      selectedYear:
          identical(selectedYear, _sentinel)
              ? this.selectedYear
              : selectedYear as int?,
      majors: majors ?? this.majors,
      selectedMajor:
          identical(selectedMajor, _sentinel)
              ? this.selectedMajor
              : selectedMajor as Major?,
      curriculum:
          identical(curriculum, _sentinel)
              ? this.curriculum
              : curriculum as Curriculum?,
      semesters: semesters ?? this.semesters,
      isLoadingSemesters: isLoadingSemesters ?? this.isLoadingSemesters,
      semestersError:
          identical(semestersError, _sentinel)
              ? this.semestersError
              : semestersError as String?,
      practice:
          identical(practice, _sentinel)
              ? this.practice
              : practice as PracticeCurriculum?,
      isLoadingPractice: isLoadingPractice ?? this.isLoadingPractice,
      practiceError:
          identical(practiceError, _sentinel)
              ? this.practiceError
              : practiceError as String?,
    );
  }

  static const _sentinel = Object();
}
