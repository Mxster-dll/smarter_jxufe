import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/grades/domain/time_limit.dart';
import 'package:smarter_jxufe/features/ims/grades/presentation/grades_state.dart';

/// 成绩筛选状态管理。
class GradesViewModel extends StateNotifier<GradesState> {
  GradesViewModel() : super(const GradesState());

  void setTimeLimit(TimeLimit v) => state = state.copyWith(timeLimit: v);
  void setSemesterXq(String v) => state = state.copyWith(semesterXq: v);
  void setAcademicYear(int v) => state = state.copyWith(academicYear: v);

  void toggleShowRawGrade() =>
      state = state.copyWith(showRawGrade: !state.showRawGrade);

  void toggleOnlyNotPassed() =>
      state = state.copyWith(onlyNotPassed: !state.onlyNotPassed);

  /// 主修 / 辅修 / 微专 切换，保证至少选中一个。
  void toggleCategory(String category) {
    switch (category) {
      case 'major':
        if (state.selectMajor && state.selectedCategoryCount <= 1) return;
        state = state.copyWith(selectMajor: !state.selectMajor);
      case 'minor':
        if (state.selectMinor && state.selectedCategoryCount <= 1) return;
        state = state.copyWith(selectMinor: !state.selectMinor);
      case 'weizhuan':
        if (state.selectWeiZhuan && state.selectedCategoryCount <= 1) return;
        state = state.copyWith(selectWeiZhuan: !state.selectWeiZhuan);
    }
  }
}

final gradesViewModelProvider =
    StateNotifierProvider<GradesViewModel, GradesState>((ref) {
      return GradesViewModel();
    });
