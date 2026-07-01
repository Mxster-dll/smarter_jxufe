import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/college/data/college_repository.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_repository_provider.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/curriculum_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_state.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/major/data/major_repository.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_repository_provider.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

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

    // 尝试获取缓存的学籍信息，用于预填默认值
    final studentInfoRepo = await ref.watch(
      studentInfoRepositoryProvider.future,
    );
    StudentInfo? studentInfo;
    studentInfoRepo.getCachedStudentInfo().fold(
      (_) {},
      (info) => studentInfo = info,
    );
    final defaultYear = studentInfo != null
        ? int.tryParse(studentInfo!.enrollYear)
        : null;

    // 确保年份列表包含入学年份
    List<int> years = List.generate(16, (i) => 2025 - i);
    if (defaultYear != null && !years.contains(defaultYear)) {
      years = [defaultYear, ...years];
    }

    // 初始状态（加载学院中，预填年份）
    state = AsyncData(
      CurriculumState(
        isLoadingColleges: true,
        selectedYear: defaultYear,
        years: years,
      ),
    );

    // 加载学院数据（等待完成）
    await _loadColleges();

    // 尝试从学籍信息预填学院和专业
    if (studentInfo != null && defaultYear != null) {
      final current = state.requireValue;
      College? matchedCollege;
      for (final c in current.colleges) {
        if (c.name == studentInfo!.college) {
          matchedCollege = c;
          break;
        }
      }

      if (matchedCollege != null) {
        // 设置学院并加载专业列表
        state = AsyncData(current.copyWith(selectedCollege: matchedCollege));
        await _loadMajors(defaultYear, matchedCollege);

        // 尝试匹配专业
        final afterMajors = state.requireValue;
        Major? matchedMajor;
        for (final m in afterMajors.majors) {
          if (m.name == studentInfo!.major) {
            matchedMajor = m;
            break;
          }
        }

        if (matchedMajor != null) {
          state = AsyncData(afterMajors.copyWith(selectedMajor: matchedMajor));
          await _loadCurriculum(defaultYear, matchedCollege, matchedMajor);
        }
      }
    }

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
