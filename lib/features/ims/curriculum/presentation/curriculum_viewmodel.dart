import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/college/data/college_repository.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_repository_provider.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_repository_provider.dart';
import 'package:smarter_jxufe/features/major/data/major_repository.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_repository_provider.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/curriculum_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_state.dart';

part 'curriculum_viewmodel.g.dart';

//TODO 测试时强制
@riverpod
class CurriculumViewModel extends _$CurriculumViewModel {
  late final CurriculumRepository _curriculumRepository;
  late final CollegeRepository _collegeRepository;
  late final MajorRepository _majorRepository;

  @override
  Future<CurriculumState> build() async {
    _curriculumRepository = await ref.watch(
      curriculumRepositoryProvider.future,
    );
    _collegeRepository = await ref.watch(collegeRepositoryProvider.future);
    _majorRepository = await ref.watch(majorRepositoryProvider.future);

    final initialState = CurriculumState(isLoadingColleges: true);
    state = AsyncData(initialState);

    await _loadColleges(); // 这个函数内部会重新设置 state

    return state.requireValue;
  }

  Future<void> _loadColleges() async {
    final currentState = state.requireValue;
    state = AsyncData(
      currentState.copyWith(isLoadingColleges: true, errorMessage: null),
    );
    final result = await _collegeRepository.getAllCollege();
    result.fold(
      (failure) {
        print("加载学院列表失败：${failure.message}");
        state = AsyncData(
          currentState.copyWith(
            isLoadingColleges: false,
            errorMessage: _mapFailureToMessage(failure),
          ),
        );
      },
      (colleges) {
        state = AsyncData(
          currentState.copyWith(
            isLoadingColleges: false,
            colleges: colleges,
            errorMessage: null,
          ),
        );
      },
    );
  }

  void onYearChanged(int? year) {
    final currentState = state.value!;
    state = AsyncData(
      currentState.copyWith(
        selectedYear: year,
        selectedMajor: null,
        majors: [],
        curriculum: null,
      ),
    );
    if (currentState.selectedCollege != null && year != null) {
      _loadMajors(year, currentState.selectedCollege!);
    }
  }

  void onCollegeChanged(College? college) {
    final currentState = state.value!;
    state = AsyncData(
      currentState.copyWith(
        selectedCollege: college,
        selectedMajor: null,
        majors: [],
        curriculum: null,
      ),
    );
    if (college != null && currentState.selectedYear != null) {
      _loadMajors(currentState.selectedYear!, college);
    }
  }

  Future<void> _loadMajors(int year, College college) async {
    final currentState = state.value!;
    state = AsyncData(
      currentState.copyWith(isLoadingMajors: true, errorMessage: null),
    );
    final result = await _majorRepository.getAllMajorIn(college, year: year);
    result.fold(
      (failure) {
        print("加载专业列表失败：${failure.message}");
        state = AsyncData(
          currentState.copyWith(
            isLoadingMajors: false,
            errorMessage: _mapFailureToMessage(failure),
          ),
        );
      },
      (majors) {
        state = AsyncData(
          currentState.copyWith(
            isLoadingMajors: false,
            majors: majors,
            errorMessage: null,
          ),
        );
      },
    );
  }

  void onMajorChanged(Major? major) {
    final currentState = state.value!;
    state = AsyncData(
      currentState.copyWith(selectedMajor: major, curriculum: null),
    );
    if (major != null &&
        currentState.selectedCollege != null &&
        currentState.selectedYear != null) {
      _loadCurriculum(
        currentState.selectedYear!,
        currentState.selectedCollege!,
        major,
      );
    }
  }

  Future<void> _loadCurriculum(int year, College college, Major major) async {
    final currentState = state.value!;
    state = AsyncData(
      currentState.copyWith(isLoadingTable: true, errorMessage: null),
    );
    final result = await _curriculumRepository.getCurriculumIn(
      year,
      college,
      major,
    );
    result.fold(
      (failure) {
        print("加载培养方案表格失败：${failure.message}");
        state = AsyncData(
          currentState.copyWith(
            isLoadingTable: false,
            errorMessage: _mapFailureToMessage(failure),
          ),
        );
      },
      (curriculum) {
        state = AsyncData(
          currentState.copyWith(
            isLoadingTable: false,
            curriculum: curriculum,
            errorMessage: null,
          ),
        );
      },
    );
  }

  String _mapFailureToMessage(Failure failure) => failure.toString();
}
