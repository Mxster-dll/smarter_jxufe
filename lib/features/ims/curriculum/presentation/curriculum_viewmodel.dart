import 'package:flutter/foundation.dart' show debugPrint;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/college/data/college_repository.dart';
import 'package:smarter_jxufe/features/college/data/providers/college_repository_provider.dart';
import 'package:smarter_jxufe/features/college/domain/college.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/practice_curriculum_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/curriculum_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/providers/practice_curriculum_providers.dart';
import 'package:smarter_jxufe/features/ims/curriculum/data/curriculum_repository.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/curriculum_state.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/major/data/major_repository.dart';
import 'package:smarter_jxufe/features/major/data/providers/major_repository_provider.dart';
import 'package:smarter_jxufe/features/major/domain/major.dart';

part 'curriculum_viewmodel.g.dart';

/// 培养方案页的取数（年份 / 学院 / 专业选择 + 两张表）。
///
/// 一次「选中」要拉三份数据，**按顺序**：
/// 1. 理论课程（`tableId=2508`，缓存优先）；
/// 2. 开课学期侧表 —— 真去抓表时第 1 步已经把侧表一起落盘了，所以这一步通常
///    零网络；只有 2026-10 之前的老缓存才需要为它多跑一次（见
///    `CurriculumRepository.getCourseSemestersIn`）；
/// 3. 实践环节（`tableId=2509`，缓存优先）。
///
/// 三份各自的失败面互不牵连：理论课程挂了整页报错；开课学期挂了只影响
/// 「按开课学期」聚合；实践环节挂了只影响最后那一段。
@riverpod
class CurriculumViewModel extends _$CurriculumViewModel {
  late final CurriculumRepository _curriculumRepository;
  late final PracticeCurriculumRepository _practiceRepository;
  late final CollegeRepository _collegeRepository;
  late final MajorRepository _majorRepository;

  @override
  Future<CurriculumState> build() async {
    // 异步获取依赖（必须等待）
    _curriculumRepository = await ref.watch(
      curriculumRepositoryProvider.future,
    );
    _practiceRepository = await ref.watch(
      practiceCurriculumRepositoryProvider.future,
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
          await _loadAll(defaultYear, matchedCollege, matchedMajor);
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
        debugPrint('加载学院列表失败：${failure.message}');
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
        semesters: const [],
        semestersError: null,
        practice: null,
        practiceError: null,
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
        semesters: const [],
        semestersError: null,
        practice: null,
        practiceError: null,
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
        debugPrint('加载专业列表失败：${failure.message}');
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
      currentState.copyWith(
        selectedMajor: major,
        curriculum: null,
        semesters: const [],
        semestersError: null,
        practice: null,
        practiceError: null,
      ),
    );
    if (major != null &&
        currentState.selectedCollege != null &&
        currentState.selectedYear != null) {
      _loadAll(
        currentState.selectedYear!,
        currentState.selectedCollege!,
        major,
      );
    }
  }

  /// **重新取当前选中的三份数据**（自动刷新与「刷新」按钮都走这里）。
  ///
  /// [force] = false（默认，自动刷新用）：缓存优先 —— 学期/课程/实践环节
  /// 命中本地缓存就零网络，离开再回来不会白跑请求；
  /// [force] = true（用户点刷新）：绕过缓存，真去教务重抓两张表。
  Future<void> reload({bool force = false}) async {
    final current = state.value;
    if (current == null) return;
    final year = current.selectedYear;
    final college = current.selectedCollege;
    final major = current.selectedMajor;
    if (year == null || college == null || major == null) return;
    await _loadAll(year, college, major, force: force);
  }

  /// 三份数据一起换。**顺序有意义**：理论课程那一步会把开课学期侧表一起落盘，
  /// 所以紧接着的 `_loadSemesters` 多半直接命中缓存（不会多打一次请求）。
  Future<void> _loadAll(
    int year,
    College college,
    Major major, {
    bool force = false,
  }) async {
    await _loadCurriculum(year, college, major, force: force);
    await _loadSemesters(year, college, major, force: force);
    await _loadPractice(year, college, major, force: force);
  }

  Future<void> _loadCurriculum(
    int year,
    College college,
    Major major, {
    bool force = false,
  }) async {
    final currentState = state.value!;
    state = AsyncData(
      currentState.copyWith(isLoadingTable: true, errorMessage: null),
    );
    final result = await _curriculumRepository.getCurriculumIn(
      year,
      college,
      major,
      forceRefresh: force,
    );
    result.fold(
      (failure) {
        debugPrint('加载培养方案表格失败：${failure.message}');
        state = AsyncData(
          state.value!.copyWith(
            isLoadingTable: false,
            errorMessage: _mapFailureToMessage(failure),
          ),
        );
      },
      (curriculum) {
        state = AsyncData(
          state.value!.copyWith(
            isLoadingTable: false,
            curriculum: curriculum,
            errorMessage: null,
          ),
        );
      },
    );
  }

  /// 开课学期（`学年学期` 列）。失败**不**写 `errorMessage`（那是整页级的），
  /// 只写 `semestersError`，界面在「按开课学期」聚合时如实提示「没取到」。
  Future<void> _loadSemesters(
    int year,
    College college,
    Major major, {
    bool force = false,
  }) async {
    state = AsyncData(
      state.value!.copyWith(isLoadingSemesters: true, semestersError: null),
    );
    final result = await _curriculumRepository.getCourseSemestersIn(
      year,
      college,
      major,
      forceRefresh: force,
    );
    result.fold(
      (failure) {
        debugPrint('加载开课学期失败：${failure.message}');
        state = AsyncData(
          state.value!.copyWith(
            isLoadingSemesters: false,
            semesters: const [],
            semestersError: _mapFailureToMessage(failure),
          ),
        );
      },
      (semesters) {
        state = AsyncData(
          state.value!.copyWith(
            isLoadingSemesters: false,
            semesters: semesters,
            semestersError: null,
          ),
        );
      },
    );
  }

  /// 实践环节（培养方案第二张表）。失败只影响这一段的显示。
  Future<void> _loadPractice(
    int year,
    College college,
    Major major, {
    bool force = false,
  }) async {
    state = AsyncData(
      state.value!.copyWith(isLoadingPractice: true, practiceError: null),
    );
    final result = await _practiceRepository.getPracticeCurriculumIn(
      year,
      college,
      major,
      forceRefresh: force,
    );
    result.fold(
      (failure) {
        debugPrint('加载实践环节失败：${failure.message}');
        state = AsyncData(
          state.value!.copyWith(
            isLoadingPractice: false,
            practice: null,
            practiceError: _mapFailureToMessage(failure),
          ),
        );
      },
      (practice) {
        state = AsyncData(
          state.value!.copyWith(
            isLoadingPractice: false,
            practice: practice,
            practiceError: null,
          ),
        );
      },
    );
  }

  String _mapFailureToMessage(Failure failure) => failure.toString();
}
