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
    String? errorMessage,
    List<College>? colleges,
    College? selectedCollege,
    List<int>? years,
    int? selectedYear,
    List<Major>? majors,
    Major? selectedMajor,
    Curriculum? curriculum,
  }) {
    return CurriculumState(
      isLoadingColleges: isLoadingColleges ?? this.isLoadingColleges,
      isLoadingMajors: isLoadingMajors ?? this.isLoadingMajors,
      isLoadingTable: isLoadingTable ?? this.isLoadingTable,
      errorMessage: errorMessage,
      colleges: colleges ?? this.colleges,
      selectedCollege: selectedCollege ?? this.selectedCollege,
      years: years ?? this.years,
      selectedYear: selectedYear ?? this.selectedYear,
      majors: majors ?? this.majors,
      selectedMajor: selectedMajor ?? this.selectedMajor,
      curriculum: curriculum ?? this.curriculum,
    );
  }
}
