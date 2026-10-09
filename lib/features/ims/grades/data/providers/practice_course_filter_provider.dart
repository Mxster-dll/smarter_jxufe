/// 「实践类课程」判据的 provider —— 由**本专业培养方案 · 实践环节表**推导。
///
/// 2026-10-08 立（用户原话：「还有一个联动的部分，那就是『实践环节』一般不计入
/// 加权成绩，详见各材料」）。口径与出处见 `domain/grades_exclusions.dart`。
///
/// ⚠ 刻意做成**同步** `Provider`：消费方（成绩页 / 分数估计）都在同步路径上
/// 过滤课程，用 `.valueOrNull` 读实践环节表 —— 表还没到时就是历史那份名单，
/// 表到了页面自然重建。**不要**改成 FutureProvider 逼调用方 await。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/curriculum/data/providers/my_practice_curriculum_provider.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/grades_exclusions.dart';

final practiceCourseFilterProvider = Provider<PracticeCourseFilter>(
  (ref) => PracticeCourseFilter.fromPractice(
    ref.watch(myPracticeCurriculumProvider).valueOrNull,
  ),
);
