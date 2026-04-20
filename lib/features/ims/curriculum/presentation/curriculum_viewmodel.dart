import 'package:riverpod/riverpod.dart';

import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/college/data/college_repository.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/major/data/major_repository.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/curriculum_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_state.dart';

class CurriculumViewModel extends StateNotifier<CurriculumState> {
  final CurriculumRepository _curriculumRepository;
  final CollegeRepository _collegeRepository;
  final MajorRepository _majorRepository;

  CurriculumViewModel({
    required CurriculumRepository repository,
    required CollegeRepository collegeRepository,
    required MajorRepository majorRepository,
  }) : _curriculumRepository = repository,
       _collegeRepository = collegeRepository,
       _majorRepository = majorRepository,
       super(CurriculumState()) {
    _loadColleges(); // 初始化时加载学院列表
  }

  Future<void> _loadColleges() async {
    state = state.copyWith(isLoadingColleges: true, errorMessage: null);
    final result = await _collegeRepository.getCollegeListIn(
      .curriculum,
      year: DateTime.now().year,
      forceRefresh: true,
    );
    result.fold(
      (failure) {
        print("加载学院列表失败：${failure.message}");
        state = state.copyWith(
          isLoadingColleges: false,
          errorMessage: _mapFailureToMessage(failure),
        );
      },
      (colleges) {
        state = state.copyWith(
          isLoadingColleges: false,
          colleges: colleges,
          errorMessage: null, // 清除之前的错误
        );
      },
    );
  }

  void onYearChanged(int? year) {
    state = state.copyWith(
      selectedYear: year,
      selectedMajor: null, // 年份变化时清空专业和表格
      majors: [],
      curriculum: null,
    );
    // 如果已有选中学院，重新加载专业
    if (state.selectedCollege != null && year != null) {
      _loadMajors(year, state.selectedCollege!);
    }
  }

  void onCollegeChanged(College? college) {
    state = state.copyWith(
      selectedCollege: college,
      selectedMajor: null,
      majors: [],
      curriculum: null,
    );
    if (college != null && state.selectedYear != null) {
      _loadMajors(state.selectedYear!, college);
    }
  }

  Future<void> _loadMajors(int year, College college) async {
    state = state.copyWith(isLoadingMajors: true, errorMessage: null);
    final result = await _majorRepository.getMajorListIn(
      .curriculum,
      year: year,
      college: college,
      forceRefresh: true, //TODO 测试时强制
    );
    result.fold(
      (failure) {
        print("加载专业列表失败：${failure.message}");
        state = state.copyWith(
          isLoadingMajors: false,
          errorMessage: _mapFailureToMessage(failure),
        );
      },
      (majors) {
        state = state.copyWith(
          isLoadingMajors: false,
          majors: majors,
          errorMessage: null,
        );
      },
    );
  }

  void onMajorChanged(Major? major) {
    state = state.copyWith(selectedMajor: major, curriculum: null);
    if (major != null &&
        state.selectedCollege != null &&
        state.selectedYear != null) {
      _loadCurriculum(state.selectedYear!, state.selectedCollege!, major);
    }
  }

  // 加载培养方案表格
  Future<void> _loadCurriculum(int year, College college, Major major) async {
    state = state.copyWith(isLoadingTable: true, errorMessage: null);
    final result = await _curriculumRepository.getCurriculum(
      year,
      college,
      major,
    );
    result.fold(
      (failure) {
        print("加载培养方案表格失败：${failure.message}");
        state = state.copyWith(
          isLoadingTable: false,
          errorMessage: _mapFailureToMessage(failure),
        );
      },
      (curriculum) {
        state = state.copyWith(
          isLoadingTable: false,
          curriculum: curriculum,
          errorMessage: null,
        );
      },
    );
  }

  String _mapFailureToMessage(Failure failure) => failure.toString();
}
