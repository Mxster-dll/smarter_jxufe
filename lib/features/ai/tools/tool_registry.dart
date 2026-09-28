/// 工具注册表：**唯一**的工具清单。
///
/// 新增一个工具 = 在这里加一行 + 写它的测试。别在别处再拼列表 ——
/// 下发给模型的 `tools` 数组与执行时的名字查找都从这里取，
/// 两份清单一旦漂移，就会出现「模型调了一个找不到的工具」这类静默失败。
library;

import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/ai/tools/app_tools.dart';
import 'package:smarter_jxufe/features/ai/tools/life_tools.dart';
import 'package:smarter_jxufe/features/ai/tools/plan_tools.dart';
import 'package:smarter_jxufe/features/ai/tools/rules_tools.dart';
import 'package:smarter_jxufe/features/ai/tools/schedule_tools.dart';
import 'package:smarter_jxufe/features/ai/tools/score_tools.dart';
import 'package:smarter_jxufe/features/ai/tools/timetable_tools.dart';

/// 全部内置工具（const 单例，无状态）。
const List<AiTool> kAllAiTools = [
  // 规章制度（离线检索）
  SearchRulesTool(),
  ReadRuleTool(),
  // 课表与无课时间
  GetMyScheduleTool(),
  FindFreeTimeTool(),
  QueryTimetableTool(),
  // 成绩与学习数据
  GetGradesTool(),
  GetScoreEstimateTool(),
  GetDeadlinesTool(),
  // 培养方案与毕业要求
  GetCurriculumTool(),
  GetGraduationCreditsTool(),
  // 生活与综合数据
  GetVolunteerHoursTool(),
  GetZongceTool(),
  ListMaterialsTool(),
  GetSchoolCalendarTool(),
  GetEnergyTool(),
  // 学籍 / 设置 / 跳转
  GetStudentInfoTool(),
  GetAppSettingsTool(),
  UpdateAppSettingTool(),
  OpenPageTool(),
];

/// 当前上下文下可用的工具（[AiTool.available] 为 false 的不会下发给模型）。
List<AiTool> availableAiTools(AiToolContext ctx) => [
  for (final tool in kAllAiTools)
    if (tool.available(ctx)) tool,
];

/// 按名字查工具（模型返回的 `tool_calls.function.name`）。
AiTool? aiToolByName(String name) {
  final key = name.trim();
  for (final tool in kAllAiTools) {
    if (tool.spec.name == key) return tool;
  }
  return null;
}
