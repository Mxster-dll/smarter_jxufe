/// 工具集：成绩 / 分数估计 / 截止日期。
///
/// 三个工具全部读**本地数据**（离线可用、不消耗教务会话）：
/// - 成绩 = `gePriorGradesProvider`（成绩页写的 `gradesCache`，已含排除名单与同课去重）；
/// - 分数估计 = `geCoursesProvider` + 同一份成绩 + 培养方案学分索引；
/// - 截止日期 = 分数估计课程里的 `deadlines`（含重复条目的「下一次截止」滚动）。
library;

import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_curriculum.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_prior_grades.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_providers.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_summary.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_deadline.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_engine.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_models.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_time.dart'
    show schoolTermTextOfCode;

/// 查成绩（教务已出成绩缓存）。
class GetGradesTool extends AiTool {
  const GetGradesTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_grades',
    description:
        '查我的成绩（来自教务成绩缓存，离线可得）。'
        '可以按课程名、学期筛选，也可以直接要加权平均分。'
        '注意：这里只有**教务已出**的成绩；本学期还没出分的课要用 get_score_estimate。',
    parameters: aiObjectSchema({
      'course': aiStrProp('课程名关键词（包含匹配，如「高等数学」）'),
      'semester': aiStrProp('学期码，如 251（=2025-2026学年第一学期）、261；不给则全部学期'),
      'only_failed': aiBoolProp('只看不及格的（<60 分）'),
      'sort': aiStrProp('排序', enums: ['score_desc', 'score_asc', 'name']),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final course = a.optStr('course');
    final semester = a.optStr('semester');
    final onlyFailed = a.boolOf('only_failed');
    final sort = (a.optStr('sort') ?? 'score_desc').toLowerCase();
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final List<GePriorGrade> all;
    try {
      all = await ctx.ref.read(gePriorGradesProvider.future);
    } catch (e) {
      return AiToolResult.fail('成绩缓存读取失败：$e');
    }
    if (all.isEmpty) {
      return const AiToolResult.ok(
        '本地还没有成绩数据。可以让用户先打开一次「成绩」页面拉取，之后就能离线查询了。',
      );
    }

    var rows = all.where((g) {
      if (course != null && !g.courseName.contains(course)) return false;
      if (semester != null && g.semester != semester.trim()) return false;
      if (onlyFailed && g.score >= 60) return false;
      return true;
    }).toList();

    rows.sort((x, y) => switch (sort) {
      'score_asc' => x.score.compareTo(y.score),
      'name' => x.courseName.compareTo(y.courseName),
      _ => y.score.compareTo(x.score),
    });

    // 加权平均（口径与成绩页一致：Σ 成绩×学分 / Σ 学分，学分 ≤ 0 不计）
    var creditSum = 0.0;
    var weighted = 0.0;
    for (final g in rows) {
      if (g.credits <= 0) continue;
      creditSum += g.credits;
      weighted += g.score * g.credits;
    }
    final average = creditSum > 0 ? weighted / creditSum : null;

    final buffer = StringBuffer();
    final filters = <String>[
      if (course != null) '课程含「$course」',
      if (semester != null) aiSemesterLabel(semester),
      if (onlyFailed) '只看不及格',
    ];
    buffer.writeln(
      '共 ${rows.length} 门课${filters.isEmpty ? '' : '（${filters.join('，')}）'}'
      '${average == null ? '' : '，加权平均 ${average.toStringAsFixed(2)} 分'
          '（${creditSum.toStringAsFixed(1)} 学分）'}。',
    );
    if (rows.isEmpty) {
      buffer.writeln('没有符合条件的成绩记录。');
      return AiToolResult.ok(buffer.toString());
    }
    buffer.writeln();
    // 按学期分组，读起来更像成绩单
    final bySemester = <String, List<GePriorGrade>>{};
    for (final g in rows) {
      bySemester.putIfAbsent(g.semester, () => []).add(g);
    }
    final keys = bySemester.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final key in keys) {
      buffer.writeln('【${aiSemesterLabel(key)}】');
      for (final g in bySemester[key]!) {
        buffer.writeln(
          '· ${g.courseName} ${_fmtScore(g.score)}'
          '${g.credits > 0 ? ' · ${g.credits} 学分' : ''}',
        );
      }
    }

    final ui = <String, dynamic>{'kind': 'grades', 'count': rows.length};
    if (average != null) ui['average'] = average;
    return AiToolResult.ok(buffer.toString(), ui: ui);
  }
}

/// 分数估计（本学期课程 + 加权汇总）。
class GetScoreEstimateTool extends AiTool {
  const GetScoreEstimateTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_score_estimate',
    description:
        '查「分数估计」模块里的数据：每门课的平时分构成、当前平时均分、'
        '若期末考 X 分则总评多少、总分加权平均（含已出成绩）。'
        '问「我这门课现在什么水平」「要考多少分才能到 90」时用它。',
    parameters: aiObjectSchema({
      'course': aiStrProp('只看某门课（课程名包含匹配）'),
      'detail': aiBoolProp('是否展开每门课的分项明细（默认只给汇总与逐课总评）'),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final course = a.optStr('course');
    final detail = a.boolOf('detail');
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final List<GeCourse> courses;
    final List<GePriorGrade> prior;
    GeCurriculumIndex index = const GeCurriculumIndex.empty();
    try {
      courses = await ctx.ref.read(geCoursesProvider.future);
      prior = await ctx.ref.read(gePriorGradesProvider.future);
      index = await ctx.ref.read(geCurriculumIndexProvider.future);
    } catch (e) {
      return AiToolResult.fail('分数估计数据读取失败：$e');
    }

    final summarize = geSummarize(prior: prior, courses: courses, index: index);
    final summary = summarize.summary;
    final buffer = StringBuffer();
    buffer.writeln(
      '总分加权平均：${summary.average == null ? '暂无（还没有可计入的分数）' : '${summary.average!.toStringAsFixed(2)} 分'}'
      ' · 计入 ${summary.count} 门 / ${summary.totalCredits.toStringAsFixed(1)} 学分',
    );
    buffer.writeln(
      '其中：教务已出 ${summary.gradesCount} 门'
      '（${summary.gradesCredits.toStringAsFixed(1)} 学分），'
      '本模块估计 ${summary.estimateCount} 门'
      '（${summary.estimateCredits.toStringAsFixed(1)} 学分）',
    );
    if (summarize.pendingCount > 0) {
      buffer.writeln('另有 ${summarize.pendingCount} 门课未填期末分或学分为 0，未计入。');
    }

    final wanted = course == null
        ? courses
        : [
            for (final c in courses)
              if (c.name.contains(course)) c,
          ];
    if (wanted.isEmpty) {
      buffer.writeln();
      buffer.writeln(
        course == null
            ? '分数估计模块里还没有课程。'
            : '分数估计模块里没有课程名含「$course」的课。',
      );
      return AiToolResult.ok(buffer.toString());
    }

    buffer.writeln();
    buffer.writeln('逐课：');
    for (final c in wanted) {
      final calc = geCalc(c);
      final total = geTotalWithFinal(calc, c.finalScore);
      final credits = geEffectiveCredits(index, c).credits;
      buffer.writeln(
        '· ${c.name}'
        '${credits > 0 ? '（$credits 学分）' : ''}'
        ' · 平时占比 ${c.dailyPercent.toStringAsFixed(0)}%'
        ' · 平时均分 ${calc.dailyMean.toStringAsFixed(1)}'
        '${c.parts.isEmpty ? '（未配置分项）' : ''}'
        '${c.finalScore == null ? ' · 期末未填' : ' · 期末 ${_fmtScore(c.finalScore!)}'}'
        '${total == null ? ' · 总评待定' : ' · 总评约 ${total.toStringAsFixed(1)}'}'
        ' · 平时可再挣 ${calc.gainableCap.toStringAsFixed(1)} 分（上限总评 '
        '${(calc.dailyCeiling + calc.finalContrib(100)).toStringAsFixed(1)}）',
      );
      if (detail && c.parts.isNotEmpty) {
        for (final p in c.parts) {
          buffer.writeln(
            '    - ${p.name}：${_partText(p)}（满分 ${_trim(p.cap)}，得分 ${gePartScore(p).toStringAsFixed(2)}）',
          );
        }
      }
      if (detail && c.note.trim().isNotEmpty) {
        buffer.writeln('    - 备注：${_oneLine(c.note)}');
      }
    }

    return AiToolResult.ok(
      buffer.toString(),
      ui: {
        'kind': 'scoreEstimate',
        'count': wanted.length,
        if (summary.average != null) 'average': summary.average,
      },
    );
  }
}

/// 课程截止日期。
class GetDeadlinesTool extends AiTool {
  const GetDeadlinesTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_deadlines',
    description:
        '查课程截止日期（作业 / 网课 / 考试，用户在「分数估计 → 课程详情」里手工录入的）。'
        '问「最近有什么要交的」「接下来几天有什么截止」时用它。'
        '重复条目（每周 / 每两周）会自动滚到下一次，不会显示成过期。',
    parameters: aiObjectSchema({
      'days': aiIntProp('只看未来几天内（默认 30 天；给 0 表示不限制）', min: 0, max: 365),
      'course': aiStrProp('只看某门课（课程名包含匹配）'),
      'include_done': aiBoolProp('是否包含本期已完成的（默认不包含）'),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final days = args['days'] == null ? 30 : a.intOf('days', fallback: 30);
    final course = a.optStr('course');
    final includeDone = a.boolOf('include_done');
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final List<GeCourse> courses;
    try {
      courses = await ctx.ref.read(geCoursesProvider.future);
    } catch (e) {
      return AiToolResult.fail('截止日期读取失败：$e');
    }

    final now = ctx.now;
    final entries = <({GeCourse course, GeDeadline deadline})>[];
    for (final c in courses) {
      if (course != null && !c.name.contains(course)) continue;
      for (final d in c.deadlines) {
        if (!includeDone && geDeadlineDoneNow(d, now)) continue;
        final due = geDeadlineEffectiveDue(d, now);
        if (days > 0 && due.difference(now).inHours > days * 24) continue;
        entries.add((course: c, deadline: d));
      }
    }
    entries.sort(
      (x, y) => geDeadlineEffectiveDue(x.deadline, now)
          .compareTo(geDeadlineEffectiveDue(y.deadline, now)),
    );

    if (entries.isEmpty) {
      return AiToolResult.ok(
        days > 0
            ? '未来 $days 天内没有截止日期${course == null ? '' : '（课程含「$course」）'}。'
            : '没有未完成的截止日期。',
      );
    }

    final buffer = StringBuffer()
      ..writeln('共 ${entries.length} 条截止日期：');
    for (final e in entries) {
      final due = geDeadlineEffectiveDue(e.deadline, now);
      final status = geDeadlineStatus(e.deadline, now);
      buffer.writeln(
        '· ${geDeadlineDueText(due, now)}'
        ' · ${e.deadline.title}'
        '（${e.deadline.kind.label} · ${e.course.name}）'
        ' · ${geDeadlineCountdownText(e.deadline, now)}'
        '${status == GeDeadlineStatus.overdue ? ' · 已过期' : ''}'
        '${e.deadline.doneAt == null ? '' : ' · 已完成'}'
        '${e.deadline.repeat == GeDeadlineRepeat.none ? '' : ' · ${geDeadlineRepeatText(e.deadline, now)}'}',
      );
      if (e.deadline.note.trim().isNotEmpty) {
        buffer.writeln('    备注：${_oneLine(e.deadline.note)}');
      }
    }

    return AiToolResult.ok(
      buffer.toString(),
      ui: {'kind': 'deadlines', 'count': entries.length},
    );
  }
}

// ────────────────────────────── 小工具 ──────────────────────────────

/// 学期码 → 中文名（`251` → `2025-2026学年第一学期`）。
///
/// **解析口径的唯一实现在 `school_calendar/domain/school_time.dart`**
/// （`schoolTermTextOfCode`，2026-09-27 起）：本函数只保留 AI 侧的两个兜底
/// —— 空串给「未知学期」、认不出原样返回（AI 文案里露出原码比吞掉好）。
String aiSemesterLabel(String code) {
  final t = code.trim();
  if (t.isEmpty) return '未知学期';
  final name = schoolTermTextOfCode(t);
  return name.isEmpty ? t : name;
}

/// 分项的一句话描述（三种模式口径不同，别混）。
String _partText(GePart p) => switch (p.mode) {
  GePartMode.up => '已完成 ${p.current}/${p.target}',
  GePartMode.down => '剩余 ${p.current}/${p.target}（负计数）',
  GePartMode.score => '得分 ${_trim(p.score)}/${_trim(p.target.toDouble())}',
};

String _fmtScore(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

String _trim(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

String _oneLine(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();
