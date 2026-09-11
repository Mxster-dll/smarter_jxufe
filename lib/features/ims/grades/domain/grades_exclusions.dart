/// 成绩统计的课程排除名单（成绩页与分数估计共用同一份口径）。
///
/// 成绩页的「课程加权 / GPA / 推免加权」等统计都会先剔除这些课程
/// （军事训练、创新创业实践活动、毕业设计、毕业论文）；分数估计的
/// 总加权平均必须遵循同一口径，否则两边数字无法对齐。
library;

/// 统一排除的课程名集合（成绩页历史口径，勿随意增删）。
const kExcludedGradeCourses = <String>{
  '军事训练',
  '创新创业实践活动',
  '毕业设计',
  '毕业论文',
};

/// 课程名是否在统一排除名单内（按去除首尾空白后的全名匹配）。
bool isExcludedGradeCourse(String courseName) =>
    kExcludedGradeCourses.contains(courseName.trim());
