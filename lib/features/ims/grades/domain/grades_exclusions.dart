/// 成绩统计的课程排除口径（成绩页 / 分数估计 / 推免加权共用）。
///
/// **2026-10-08 改口径**：此前是一份**手写的四个课名**（军事训练 / 创新创业实践
/// 活动 / 毕业设计 / 毕业论文），它其实是「实践类课程」的替身。用户当场点出：
/// 「实践环节一般不计入加权成绩，详见各材料」—— 材料里写得很明确：
///
/// > 课程加权平均成绩……注：4. **实践类课程（如毕业论文、毕业实习等），不计入
/// > 课程加权平均成绩。**（《江西财经大学全日制本科生成绩管理办法》第二十四条，
/// > 见 `assets/rules/text/r05a.md`；`r08a` / `r09a` / `r10a` / `r23a` 同款条款）
///
/// 所以现在的判据 = **本专业培养方案「实践环节」那张表**（`tableId=2509`，见
/// `features/ims/curriculum/domain/practice_stage.dart`）里的课程代码与名称，
/// **并集**上那份历史名单（历史名单留着兜底：表拿不到时行为与从前**逐字不变**）。
///
/// ⚠ 只影响**加权 / GPA 类统计**；[毕业学分](../../../graduation_requirements/domain/credit_progress.dart)
/// 那边实践环节是**算学分**的 —— 两者不矛盾（学分照给，只是不进加权）。
library;

import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';

/// 历史名单（实践类课程的旧替身）。**只增不减、不许删**：
/// 表拿不到时它就是全部判据，删了会让 GPA 数字悄悄变大。
const kExcludedGradeCourses = <String>{
  '军事训练',
  '创新创业实践活动',
  '毕业设计',
  '毕业论文',
};

/// 实践类课程的判据。
class PracticeCourseFilter {
  /// 命中的课程代码。
  final Set<String> codes;

  /// 命中的课程名称（含 [kExcludedGradeCourses] 那份历史名单）。
  final Set<String> names;

  const PracticeCourseFilter({
    this.codes = const {},
    this.names = kExcludedGradeCourses,
  });

  /// 拿不到实践环节表时的默认判据（= 历史行为）。
  static const PracticeCourseFilter fallback = PracticeCourseFilter();

  /// 从实践环节表建判据；[practice] 为 null 时退回 [fallback]。
  factory PracticeCourseFilter.fromPractice(PracticeCurriculum? practice) {
    if (practice == null || practice.stages.isEmpty) {
      return PracticeCourseFilter.fallback;
    }
    return PracticeCourseFilter(
      codes: practice.codes,
      names: {...kExcludedGradeCourses, ...practice.names},
    );
  }

  /// 这门课算不算「实践类」（不计入加权）。
  ///
  /// 代码优先、名称兜底 —— 成绩表偶有课程名改写过，代码更稳。
  bool excludes({String code = '', String name = ''}) {
    final c = code.trim();
    if (c.isNotEmpty && codes.contains(c)) return true;
    return names.contains(name.trim());
  }

  /// 只看名称的判据（给「手上没有课程代码」的老调用方用）。
  bool excludesName(String name) => names.contains(name.trim());

  bool get isEmpty => codes.isEmpty && names.isEmpty;
}
