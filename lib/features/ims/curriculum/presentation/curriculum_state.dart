import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

class CurriculumState {
  final bool isLoadingColleges;
  final bool isLoadingMajors;
  final bool isLoadingTable;
  final String? errorMessage;
  final List<College> colleges;
  final College? selectedCollege;
  final List<int> years; // 可选年份列表，如 2010..2025
  final int? selectedYear;
  final List<Major> majors;
  final Major? selectedMajor;
  final Curriculum? curriculum;

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
    );
  }

  static const _sentinel = Object();
}
