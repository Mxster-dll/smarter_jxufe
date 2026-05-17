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

@riverpod
class CurriculumViewModel extends _$CurriculumViewModel {
  late final CurriculumRepository _curriculumRepository;
  late final CollegeRepository _collegeRepository;
  late final MajorRepository _majorRepository;

  @override
  Future<CurriculumState> build() async {
    // 异步获取依赖（必须等待）
    _curriculumRepository = await ref.watch(
      curriculumRepositoryProvider.future,
    );
    _collegeRepository = await ref.watch(collegeRepositoryProvider.future);
    _majorRepository = await ref.watch(majorRepositoryProvider.future);

    // 初始状态（加载学院中）
    final initialState = CurriculumState(isLoadingColleges: true);
    // 注意：此时 state 还是 AsyncLoading，但我们手动返回的 initialState 并不会被用到
    // 我们要在下面手动设置状态
    state = AsyncData(initialState);

    // 加载学院数据（等待完成）
    await _loadColleges(); // 这个函数内部会重新设置 state

    // 返回最终状态（实际上状态已经更新过了，这里返回值会被 AsyncNotifier 忽略？
    // 但实际上 AsyncNotifier 机制：build 返回的 Future 完成后，state 被设置为该返回值。
    // 所以我们需要返回 _loadColleges 更新后的状态。
    return state.requireValue;
  }

  Future<void> _loadColleges() async {
    // 注意：此时 state 是 AsyncData<CurriculumState>，我们通过 value 访问
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
