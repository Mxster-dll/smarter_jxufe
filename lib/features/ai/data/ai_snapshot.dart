/// 系统提示词与「轻量常驻快照」。
///
/// 三层上下文，代价从低到高：
/// 1. **系统提示词**（[aiSystemPrompt]）—— 恒定，定义行为准则；
/// 2. **轻量快照**（[buildAiSnapshot]）—— 每次提问都带，**纯离线**（学籍缓存 +
///    教学周推算 + 设置摘要），让模型一开始就知道「现在几点、我是谁、第几周」，
///    省掉一轮工具调用；这就是用户拍板的「轻量常驻快照」；
/// 3. **工具调用** —— 具体数据按需取，只有真用到才花 token。
///
/// 另有一条降级路径 [buildAiDataPack]：模型不支持 function calling 时，
/// 预取一批常用数据直接塞进提示词（用户拍板的「自动降级为预取数据塞提示词」）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/ai/tools/my_schedule_data.dart';
import 'package:smarter_jxufe/features/ai/tools/tool_registry.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';

const List<String> _cnWeekdays = ['一', '二', '三', '四', '五', '六', '日'];

/// 现在时刻的紧凑描述（`2026-10-15 周四 14:30`）。
String aiNowLabel(DateTime now) {
  final w = now.weekday >= 1 && now.weekday <= 7 ? _cnWeekdays[now.weekday - 1] : '?';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)} 周$w '
      '${two(now.hour)}:${two(now.minute)}';
}

/// 轻量常驻快照（**不联网**；任何一步失败就跳过那一行，绝不抛）。
Future<String> buildAiSnapshot(Ref ref, {required DateTime now}) async {
  final lines = <String>['现在：${aiNowLabel(now)}'];

  // 学期 + 教学周（离线：校历快照 + 日期推算）
  try {
    final terms = ref.read(offlineSemesterTermsProvider);
    final term = currentSchoolTerm(now, terms: terms);
    final week = await ref.read(teachingWeekProvider.future);
    final termName = '${term.xn}-${term.xn + 1}学年'
        '${term.xq == 0 ? '第一学期' : (term.xq == 1 ? '第二学期' : '第 ${term.xq} 学段')}';
    // 学期参数（xn/xq）写进快照：模型问起别的学期时能直接填，不必先试错一遍
    lines.add(
      '学期：$termName（xn=${term.xn}，xq=${term.xq}）'
      '${week == null ? '' : '，${week.week >= 1 ? '第 ${week.week} 教学周' : '尚未开学（第 0 周）'}'}',
    );
    // 可选学期（离线，最多 4 个）——「上学期」「去年」这类说法要落到具体 xn/xq
    final choices = availableSchoolTermsFrom(terms, current: term, limit: 4);
    if (choices.length > 1) {
      lines.add(
        '可选学期：${availableTermsHintFrom(choices, current: term)}'
        '（问别的学期时把这组 xn/xq 传给课表类工具）',
      );
    }
  } catch (_) {
    // 校历不可用：不写这一行
  }

  // 学籍（离线缓存；`getCachedStudentInfo` 是同步的 Either，失败给 null）
  try {
    final repo = await ref.read(studentInfoRepositoryProvider.future);
    final info = repo.getCachedStudentInfo().fold((_) => null, (v) => v);
    if (info != null) {
      final bits = <String>[
        if (info.name.trim().isNotEmpty) info.name.trim(),
        if (info.college.trim().isNotEmpty) info.college.trim(),
        if (info.major.trim().isNotEmpty) info.major.trim(),
        if (info.enrollYear.trim().isNotEmpty) '${info.enrollYear.trim()} 级',
        if (info.className.trim().isNotEmpty) info.className.trim(),
      ];
      if (bits.isNotEmpty) lines.add('用户：${bits.join(' · ')}');
    }
  } catch (_) {
    // 学籍缓存读不到：不写这一行
  }

  if (lines.length == 1) return lines.first;
  return lines.join('\n');
}

/// 降级数据包：模型不支持函数调用时，预取一批常用数据塞进提示词。
///
/// 直接复用工具本身（而不是另写一套取数），保证两条路径的数据口径**完全一致**。
Future<String> buildAiDataPack(AiToolContext ctx) async {
  const wanted = <({String tool, Map<String, dynamic> args, String label})>[
    (tool: 'get_student_info', args: {}, label: '学籍'),
    (tool: 'get_my_schedule', args: {'scope': 'week'}, label: '本周课表'),
    (tool: 'get_deadlines', args: {'days': 30}, label: '近期截止日期'),
    (tool: 'get_grades', args: {'sort': 'score_desc'}, label: '成绩'),
    // 用户 2026-09-27：「给这个模块（综测）接入 ai 助手的数据源」—— 降级态
    // （模型不支持函数调用 / 被自动降级）也要有综测，否则 AI 会答不出综测问题。
    (tool: 'get_zongce', args: {}, label: '综测'),
  ];
  final parts = <String>[];
  for (final item in wanted) {
    final tool = aiToolByName(item.tool);
    if (tool == null || !tool.available(ctx)) continue;
    try {
      final result = await tool.run(ctx, item.args);
      if (!result.ok) continue;
      parts.add('【${item.label}】\n${result.content}');
    } catch (_) {
      // 单项失败不影响其它项
    }
  }
  return parts.join('\n\n');
}

/// 系统提示词。
///
/// 写法上的取舍：**规则要具体到可执行**（「问无课时间一律用 find_free_time」），
/// 而不是「请准确回答问题」这种没法照做的空话 —— 前者能显著减少乱答与乱调工具。
String aiSystemPrompt({
  String snapshot = '',
  String dataPack = '',
  bool toolsEnabled = true,
  String extra = '',
}) {
  final buffer = StringBuffer()
    ..writeln('你是「智慧er江财」App 内置的助手，服务江西财经大学的学生。')
    ..writeln('你的数据来自这个 App 与学校教务系统，**必须用工具去查，不要凭空编造**。')
    ..writeln();

  if (toolsEnabled) {
    buffer
      ..writeln('## 工作方式')
      ..writeln('1. 涉及用户个人数据（成绩、课表、学籍、分数估计、截止日期、设置）或')
      ..writeln('   学校规定（学籍、奖惩、推免、竞赛认定、学分…）的问题，**先调用工具取真实数据再回答**。')
      ..writeln('2. 问「某人什么时候没空/有空」「今天谁没课」→ 一律用 `find_free_time`，')
      ..writeln('   不要用 `query_timetable` 自己算。')
      ..writeln('3. 问「学校怎么规定的」→ 先 `search_rules`，摘要不够再 `read_rule` 读具体条文，')
      ..writeln('   引用时把文号与条文出处一起说清楚。')
      ..writeln('4. 时间以「现在」为基准自己推算（今天/明天/周几），不要说「我无法知道当前时间」。')
      ..writeln('5. 工具结果是权威数据：照实转述，不要改动数字；工具报错就如实说明并给出下一步建议。')
      ..writeln('6. 需要用户去某个页面操作时，用 `open_page` 附一个跳转按钮。')
      // 用户 2026-09-27：「给这个模块（综测）接入 ai 助手的数据源」→ 光有工具不够，
      // 路由规则里也要点名，模型才会把它用在综测问题上（规则要具体到可执行）。
      ..writeln('7. 问综测（综合素质测评）的问题 —— 「我综测多少分」「哪一育拖后腿」')
      ..writeln('   「德育为什么被扣分」「哪条加分算进去了」→ 用 `get_zongce`；')
      ..writeln('   要逐条核对材料**计入 / 未计入**（德育按表 3~7 各板块、智育竞赛按封顶 5 分）')
      ..writeln('   时给 `detail: true`。总评是五育**按占比加权**，不是简单平均。')
      ..writeln('8. 要改 App 设置时用 `update_app_setting`（会弹确认框，用户可能拒绝）。')
      // 用户 2026-09-27：「为什么app内ai提示只能查本学期课表，但是我们明明是有查各学期
      // 课表的能力的」—— 工具加了学期参数还不够，路由规则里不写，模型照旧只答本学期。
      ..writeln('9. 课表类问题（`get_my_schedule` / `query_timetable` / `find_free_time`）')
      ..writeln('   **默认是当下学期**；用户提到别的学期 —— 「上学期」「上一学年」')
      ..writeln('   「2025-2026 学年第一学期」——就传 `xn`（学年起始年，2025-2026 学年 → 2025）')
      ..writeln('   与 `xq`（0 第一学期 / 1 第二学期），并**显式给 `week`**（别的学期没有')
      ..writeln('   「当前教学周」）。不确定有哪些学期就看「现在的情况」里的可选学期，别回答')
      ..writeln('   「我只能查本学期」。')
      ..writeln();
  } else {
    buffer
      ..writeln('## 工作方式（数据已预取，本次没有工具可用）')
      ..writeln('1. 下面「已知数据」是你**全部**的信息来源；里面没有的，就如实说查不到，')
      ..writeln('   并指引用户去 App 对应页面查看。**绝不要编造**。')
      ..writeln('2. 时间以「现在」为基准自己推算。')
      ..writeln();
  }

  buffer
    ..writeln('## 回答风格')
    ..writeln('- 用中文，简洁、口语化，先说结论再补细节。')
    ..writeln('- 需要罗列时用短横线列表，**不要用 markdown 表格**（手机上看不清）。')
    ..writeln('- 不要暴露工具名、参数名、JSON、字段名这些内部细节，直接给用户结论。')
    ..writeln('- 不知道就说不知道，不要为了显得有帮助而猜。')
    ..writeln();

  if (snapshot.trim().isNotEmpty) {
    buffer
      ..writeln('## 现在的情况')
      ..writeln(snapshot.trim())
      ..writeln();
  }
  if (dataPack.trim().isNotEmpty) {
    buffer
      ..writeln('## 已知数据')
      ..writeln(dataPack.trim())
      ..writeln();
  }
  if (extra.trim().isNotEmpty) {
    buffer
      ..writeln('## 用户的额外要求')
      ..writeln(extra.trim())
      ..writeln();
  }
  return buffer.toString().trimRight();
}
