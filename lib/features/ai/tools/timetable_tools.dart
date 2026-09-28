/// 工具集：课表查询与「找无课时间」。
///
/// 这里是**用户原始需求的原点** —— 用户原话：
/// 「我们希望知道今天蒋明华老师没有课的时间，然后 ai 返回会话」。
///
/// 实现不靠模型推理，而是复用了仓库里已有的两件东西：
/// - `lib/features/ims/public_query/domain/public_query.dart`：公共查询的
///   教师/班级/教室/课程课表（含「按姓名找 code」）；
/// - `lib/features/ims/public_query/domain/free_time.dart`：纯领域的
///   「把占用槽展开成空闲窗口」引擎（含单双周、半日块判定）。
///
/// 模型只负责**把口语化的时间与姓名翻译成参数**，算术全部由引擎做 ——
/// 这样「今天下午蒋老师什么时候有空」不会因为模型算错节次而给出错误答案。
///
/// ⚠ **学期可指定**（2026-09-27）：两个工具都吃 `xn`（学年起始年）+ `xq`
/// （0 第一 / 1 第二），不给 = 当下学期。此前这两个工具把学期写死成
/// 「当下学期那一项」（旧 `currentPublicQueryTerm`），而教务公共查询的学期
/// 列表本来就是多学年的（`publicQueryTermsProvider`）→ 用户问「上一学年」
/// 只能得到「我只查得到本学期」。判据 = [resolvePublicQueryTerm]（匹配不上
/// 就把可选学期列出来，模型换值重试）。
library;

import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/ai/tools/my_schedule_data.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_providers.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/free_time.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_timetable.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';

/// 公共查询课表（教师 / 班级 / 教室 / 课程）。
class QueryTimetableTool extends AiTool {
  const QueryTimetableTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'query_timetable',
    description:
        '查某个教师、班级、教室或课程的课表（走教务公共查询，需要登录教务）。'
        '想知道「某某老师这周上哪些课」「某间教室什么时候空着」时用它。'
        '**默认是当下学期**；问别的学期（「上学期」「上一学年」）时'
        '传 xn（学年起始年）+ xq（0 第一学期 / 1 第二学期）。'
        '如果只是想知道某人「什么时候没课」，直接用 find_free_time 更省事。',
    parameters: aiObjectSchema(
      {
        'kind': aiStrProp(
          '查询对象类型',
          enums: ['teacher', 'klass', 'classroom', 'course'],
          fallbackHint: 'teacher=教师课表，klass=班级课表，classroom=教室课表，course=课程课表',
        ),
        'names': aiStrListProp('对象名称列表（教师姓名 / 班级名 / 教室名 / 课程名），支持部分匹配'),
        'week': aiIntProp('只看第几教学周（可选，默认看整学期）', min: 1, max: 30),
        'xn': aiIntProp(
          '学年起始年（2025 = 2025-2026 学年；默认当下学期那一年）',
          min: 2000,
          max: 2100,
        ),
        'xq': aiIntProp('学段（0 第一学期 / 1 第二学期；默认当下学期所在学段）', min: 0, max: 2),
      },
      required: ['kind', 'names'],
    ),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final kindName = a.str('kind');
    final names = a.strList('names');
    final week = a.intOf('week', fallback: 0);
    final termArg = aiTermArg(ctx, a);
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final kind = publicQueryKindOf(kindName);
    if (kind == null) {
      return AiToolResult.fail('kind 只能是 teacher / klass / classroom / course。');
    }
    if (names.isEmpty) return const AiToolResult.fail('names 不能为空。');

    final PublicQueryTerm term;
    try {
      term = await resolvePublicQueryTerm(ctx, xn: termArg?.xn, xq: termArg?.xq);
    } catch (e) {
      return AiToolResult.fail('拿不到学期列表（$e）。公共查询需要先登录教务系统。');
    }

    final buffer = StringBuffer()
      ..writeln('学期：${term.name}${week > 0 ? '（只看第 $week 教学周）' : ''}');
    final uiEntries = <Map<String, dynamic>>[];

    for (final name in names) {
      final resolved = await resolvePublicQueryCodes(ctx, kind: kind, term: term, names: [name]);
      if (resolved.error != null) {
        buffer
          ..writeln()
          ..writeln('【$name】查询失败：${resolved.error}');
        continue;
      }
      final match = resolved.matches.isEmpty ? null : resolved.matches.first;
      if (match == null) {
        buffer
          ..writeln()
          ..writeln('【$name】没找到匹配对象。${resolved.hint}');
        continue;
      }
      final result = await fetchPublicTimetable(ctx, kind: kind, term: term, code: match.code);
      if (result.error != null) {
        buffer
          ..writeln()
          ..writeln('【${match.displayName}】查询失败：${result.error}');
        continue;
      }
      buffer
        ..writeln()
        ..writeln('【${match.displayName}】（${kind.shortTitle}）');
      buffer.write(renderTimetables(result.timetables, week: week));
      uiEntries.add({
        'kind': kind.name,
        'name': match.displayName,
        'code': match.code,
      });
    }

    return AiToolResult.ok(
      buffer.toString(),
      ui: {'kind': 'timetable', 'entries': uiEntries},
    );
  }
}

/// 找无课时间（我自己 / 指定教师 / 指定班级）。
class FindFreeTimeTool extends AiTool {
  const FindFreeTimeTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'find_free_time',
    description:
        '算出「某个人 / 某个班 / 我自己」在指定日子里没课的时间段。'
        '**问「谁什么时候有空」「哪天没课」一律用它**，不要用 query_timetable 再自己算。'
        '不传 teachers 与 classes 时 = 查我自己（读本地课表缓存，没有才联网）。'
        '**默认是当下学期**；问别的学期（「上学期」「上一学年」）时传 xn（学年起始年）'
        '+ xq（0 第一学期 / 1 第二学期），并**显式给 week**'
        '（别的学期没有「当前教学周」可言，不给就按第 1 周算）。'
        '返回值已经是「连续空闲的节次区间 + 对应钟点」，直接用自然语言转述即可。',
    parameters: aiObjectSchema({
      'teachers': aiStrListProp('教师姓名列表（如 ["蒋明华"]）。多人则返回「都有空」的共同时段'),
      'classes': aiStrListProp('班级名列表（如 ["26会计学S1班"]）。与 teachers 二选一或同时给'),
      'date': aiStrProp(
        '目标日期',
        fallbackHint: 'today=今天 / tomorrow=明天 / 2026-10-15 / 10-15；默认 today',
      ),
      'weekday': aiIntProp('直接指定星期几（1=周一 … 7=周日），给了就忽略 date'),
      'scope': aiStrProp('day=只看该日 / week=看整周', enums: ['day', 'week']),
      'week': aiIntProp('教学周（默认当前教学周；开学前或要看别的周时手填）', min: 1, max: 30),
      'min_periods': aiIntProp('最短连续空闲节数，默认 1（只想找两节连着的空档就填 2）', min: 1, max: 6),
      'xn': aiIntProp(
        '学年起始年（2025 = 2025-2026 学年；默认当下学期那一年）',
        min: 2000,
        max: 2100,
      ),
      'xq': aiIntProp('学段（0 第一学期 / 1 第二学期；默认当下学期所在学段）', min: 0, max: 2),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final teachers = a.strList('teachers');
    final classes = a.strList('classes');
    final dateText = a.optStr('date');
    final weekdayArg = args['weekday'] == null ? null : a.intOf('weekday');
    final scope = (a.optStr('scope') ?? 'day').toLowerCase();
    final weekArg = args['week'] == null ? 0 : a.intOf('week');
    final minPeriods = a.intOf('min_periods', fallback: 1);
    final termArg = aiTermArg(ctx, a);
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final cur = aiCurrentTerm(ctx);
    final isCurrentTerm =
        termArg == null || (termArg.xn == cur.xn && termArg.xq == cur.xq);
    final termLabel = termArg == null ? '' : myTermLabel(termArg);

    final now = ctx.now;
    final targetDay = weekdayArg != null
        ? _dayForWeekday(now, weekdayArg)
        : _resolveDate(now, dateText);

    // 教学周：显式给 > 当下学期推算；都拿不到就只能按第 1 周算（并明确告知）。
    // 查**别的学期**时绝不用「当前教学周」——那会把 261 的第 3 周当成 252 的第 3 周。
    var week = weekArg;
    String? weekNote;
    final teachingWeek = await _safeTeachingWeek(ctx);
    if (week <= 0) {
      if (isCurrentTerm && teachingWeek != null && teachingWeek.week >= 1) {
        week = teachingWeek.week;
      } else {
        week = 1;
        weekNote = isCurrentTerm
            ? '（当前不在教学周内，按第 1 教学周估算）'
            : '（$termLabel：没给教学周，按第 1 教学周估算）';
      }
    } else if (isCurrentTerm &&
        teachingWeek != null &&
        teachingWeek.week >= 1 &&
        week != teachingWeek.week) {
      weekNote = '（第 $week 教学周，当前是第 ${teachingWeek.week} 教学周）';
    }

    final Set<int> weekdays = scope == 'week'
        ? const {1, 2, 3, 4, 5, 6, 7}
        : {targetDay.weekday};

    // ── 收集占用槽 ────────────────────────────────────────────────
    final slots = <ScheduleSlot>[];
    final owners = <String>[];
    final notes = <String>[];

    if (teachers.isEmpty && classes.isEmpty) {
      final mine = await myScheduleSlots(
        ctx,
        week: week,
        xn: termArg?.xn,
        xq: termArg?.xq,
      );
      if (mine.error != null) {
        return AiToolResult.fail(mine.error!);
      }
      slots.addAll(mine.slots);
      owners.add('我');
    } else {
      final PublicQueryTerm term;
      try {
        term = await resolvePublicQueryTerm(
          ctx,
          xn: termArg?.xn,
          xq: termArg?.xq,
        );
      } catch (e) {
        return AiToolResult.fail('拿不到学期列表（$e）。查他人课表需要先登录教务系统。');
      }
      for (final entry in [
        for (final t in teachers) (PublicQueryKind.teacher, t),
        for (final c in classes) (PublicQueryKind.klass, c),
      ]) {
        final kind = entry.$1;
        final name = entry.$2;
        final resolved = await resolvePublicQueryCodes(
          ctx,
          kind: kind,
          term: term,
          names: [name],
        );
        if (resolved.error != null) {
          notes.add('【$name】查询失败：${resolved.error}');
          continue;
        }
        final match = resolved.matches.isEmpty ? null : resolved.matches.first;
        if (match == null) {
          notes.add('【$name】没找到匹配的${kind.ownerLabel}。${resolved.hint}');
          continue;
        }
        final result = await fetchPublicTimetable(
          ctx,
          kind: kind,
          term: term,
          code: match.code,
        );
        if (result.error != null) {
          notes.add('【${match.displayName}】查询失败：${result.error}');
          continue;
        }
        final got = slotsOfTimetables(result.timetables);
        if (got.isEmpty) {
          notes.add('【${match.displayName}】这一学期没有任何排课。');
          continue;
        }
        slots.addAll(got);
        owners.add(match.displayName);
      }
      if (owners.isEmpty) {
        return AiToolResult.fail(
          '没能取到任何目标的课表。${notes.isEmpty ? '' : '\n${notes.join('\n')}'}',
        );
      }
    }

    // ── 算空闲窗口 ────────────────────────────────────────────────
    final windows = findFreeWindows(
      slots: slots,
      week: week,
      weekdays: weekdays,
      minPeriods: minPeriods,
    );
    final ranked = rankFreeWindows(windows);
    final periodTable = await safePeriodTable(ctx);

    final buffer = StringBuffer();
    final dayLabel = _dayLabel(
      now,
      targetDay,
      weekdays,
      relative: isCurrentTerm,
    );
    buffer.writeln('对象：${owners.join(' + ')}');
    // 查询非本学期时把学期写出来（否则模型会拿「第 N 教学周」当成本学期的那一周）
    if (termArg != null) buffer.writeln('学期：$termLabel');
    buffer.writeln(
      '时间：$dayLabel · 第 $week 教学周${weekNote ?? ''}'
      '${minPeriods > 1 ? ' · 至少连续 $minPeriods 节' : ''}',
    );
    for (final note in notes) {
      buffer.writeln('注意：$note');
    }
    buffer.writeln();

    if (ranked.isEmpty) {
      buffer.writeln(
        scope == 'week'
            ? '这一周里没有符合条件的连续空档。'
            : '这一天没有符合条件的连续空档（课排满了，或最小连续节数设得太高）。',
      );
    } else {
      buffer.writeln('无课时段（共 ${ranked.length} 段，按「连续节数多 → 星期靠前」排序）：');
      for (final w in ranked) {
        final time = _windowTime(periodTable, w);
        buffer.writeln(
          '· ${w.weekday == targetDay.weekday || scope == 'week' ? '周${_cnWeekday(w.weekday)} ' : ''}'
          '第 ${w.startPeriod}-${w.endPeriod} 节'
          '${time == null ? '' : '（$time）'}'
          '，共 ${w.periods} 节',
        );
      }
    }

    final uiWindows = [
      for (final w in ranked)
        {
          'weekday': w.weekday,
          'startPeriod': w.startPeriod,
          'endPeriod': w.endPeriod,
          'periods': w.periods,
          'label': w.label,
        },
    ];
    return AiToolResult.ok(
      buffer.toString(),
      ui: {
        'kind': 'freeTime',
        'owners': owners,
        'week': week,
        'weekdays': weekdays.toList()..sort(),
        'windows': uiWindows,
      },
    );
  }
}

// ────────────────────────────── 公共查询辅助 ──────────────────────────────

/// `kind` 字符串 → 枚举（认中英文与常见别名）。
PublicQueryKind? publicQueryKindOf(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'teacher':
    case '教师':
    case '老师':
      return PublicQueryKind.teacher;
    case 'klass':
    case 'class':
    case 'banji':
    case '班级':
      return PublicQueryKind.klass;
    case 'classroom':
    case 'room':
    case '教室':
      return PublicQueryKind.classroom;
    case 'course':
    case '课程':
      return PublicQueryKind.course;
  }
  return null;
}

/// 当下学期对应的公共查询学期项。
///
/// - 给了 [xn] / [xq] → 就用那个学期；教务学期列表里没有 → 抛
///   （错误文案里列出可选学期，模型据此换一个值重试）；
/// - 都没给 → 当下学期那一项（匹配不上时沿用旧行为：退回列表第一项）。
Future<PublicQueryTerm> resolvePublicQueryTerm(
  AiToolContext ctx, {
  int? xn,
  int? xq,
}) async {
  final terms = await ctx.ref.read(publicQueryTermsProvider.future);
  if (terms.isEmpty) throw StateError('学期列表为空');
  if (xn != null || xq != null) {
    for (final t in terms) {
      if ((xn == null || t.xn == xn) && (xq == null || t.xqM == xq)) return t;
    }
    throw StateError(
      '教务没有这个学期的公共查询数据（xn=${xn ?? '?'}，xq=${xq ?? '?'}）。'
      '可选学期：${publicQueryTermChoices(terms)}',
    );
  }
  final st = currentSchoolTerm(
    ctx.now,
    terms: ctx.ref.read(offlineSemesterTermsProvider),
  );
  for (final t in terms) {
    if (t.matches(st.xn, st.xq)) return t;
  }
  return terms.first;
}

/// 教务学期列表的一行文本（「这个学期查不到」时列可选值用）。
String publicQueryTermChoices(List<PublicQueryTerm> terms, {int limit = 8}) =>
    terms
        .take(limit)
        .map((t) => '${t.name}（xn=${t.xn}，xq=${t.xqM}）')
        .join(' / ');

/// 姓名 → code 的解析结果。
class ResolvedPublicQuery {
  final List<PublicQueryOption> matches;
  final String? error;

  /// 没匹配到时的提示（列出该类型下前几个候选，便于模型纠正）。
  final String hint;

  const ResolvedPublicQuery({
    this.matches = const [],
    this.error,
    this.hint = '',
  });
}

/// 按名称在公共查询的选择器里找 code。
///
/// 先精确同名 → 再包含匹配 → 都没有则返回空（[ResolvedPublicQuery.hint] 给出候选）。
Future<ResolvedPublicQuery> resolvePublicQueryCodes(
  AiToolContext ctx, {
  required PublicQueryKind kind,
  required PublicQueryTerm term,
  required List<String> names,
}) async {
  final request = PublicQueryRequest(kind: kind, term: term);
  final List<PublicQueryOption> options;
  try {
    options = await ctx.ref.read(publicQueryComboBoxProvider(request).future);
  } catch (e) {
    return ResolvedPublicQuery(error: '$e');
  }
  if (options.isEmpty) {
    return const ResolvedPublicQuery(hint: '该学期没有可选对象。');
  }
  final wanted = names.map((n) => n.trim()).where((n) => n.isNotEmpty).toList();
  final out = <PublicQueryOption>[];
  for (final name in wanted) {
    PublicQueryOption? found;
    for (final o in options) {
      if (o.displayName == name || o.name == name) {
        found = o;
        break;
      }
    }
    if (found == null) {
      final loose = <PublicQueryOption>[];
      for (final o in options) {
        if (o.displayName.contains(name) || o.name.contains(name)) loose.add(o);
      }
      if (loose.length == 1) {
        found = loose.first;
      } else if (loose.length > 1) {
        return ResolvedPublicQuery(
          hint: '「$name」有 ${loose.length} 个同名/近似对象：'
              '${loose.take(5).map((o) => o.displayName).join('、')}。请让用户说全名。',
        );
      }
    }
    if (found == null) {
      final sample = options.take(8).map((o) => o.displayName).join('、');
      return ResolvedPublicQuery(
        hint: '没有名为「$name」的对象。该学期可选示例：$sample'
            '${options.length > 8 ? ' 等 ${options.length} 个' : ''}',
      );
    }
    if (!out.any((o) => o.code == found!.code)) out.add(found);
  }
  return ResolvedPublicQuery(matches: out);
}

/// 拉取一份公共查询课表。
Future<PublicQueryReportOutcome> fetchPublicTimetable(
  AiToolContext ctx, {
  required PublicQueryKind kind,
  required PublicQueryTerm term,
  required String code,
}) async {
  final request = _requestWithCode(kind, term, code);
  try {
    final result = await ctx.ref.read(publicQueryReportProvider(request).future);
    if (result.isEmpty) {
      return const PublicQueryReportOutcome(
        timetables: [],
        error: '教务没有检索到记录（该学期可能没排课）',
      );
    }
    return PublicQueryReportOutcome(timetables: result.timetables);
  } catch (e) {
    return PublicQueryReportOutcome(timetables: const [], error: '$e');
  }
}

PublicQueryRequest _requestWithCode(
  PublicQueryKind kind,
  PublicQueryTerm term,
  String code,
) => switch (kind) {
  PublicQueryKind.teacher => PublicQueryRequest(
    kind: kind,
    term: term,
    teacherCode: code,
  ),
  PublicQueryKind.klass => PublicQueryRequest(kind: kind, term: term, classCode: code),
  PublicQueryKind.classroom => PublicQueryRequest(kind: kind, term: term, roomCode: code),
  PublicQueryKind.course => PublicQueryRequest(
    kind: kind,
    term: term,
    courseCode: code,
  ),
};

/// 公共查询结果（带错误说明）。
class PublicQueryReportOutcome {
  final List<PublicTimetable> timetables;
  final String? error;

  const PublicQueryReportOutcome({required this.timetables, this.error});
}

/// 把课表渲染成给模型看的紧凑文本。
///
/// 格式刻意做成「一行一节课」而不是 ASCII 网格：模型读行式文本的准确率明显高于
/// 读对齐网格，而且行式在 [week] 过滤后还能顺手把「这门课还剩几周」讲清楚。
String renderTimetables(List<PublicTimetable> timetables, {int week = 0}) {
  if (timetables.isEmpty) return '（无排课）\n';
  final buffer = StringBuffer();
  for (final t in timetables) {
    if (timetables.length > 1 && t.owner.isNotEmpty) {
      buffer.writeln('— ${t.owner}${t.subtitle.isEmpty ? '' : '（${t.subtitle}）'} —');
    }
    final cells = week > 0
        ? [
            for (final c in t.cells)
              if (week >= c.startWeek && week <= c.endWeek) c,
          ]
        : t.cells;
    if (cells.isEmpty) {
      buffer.writeln(week > 0 ? '  第 $week 教学周没有课。' : '  没有排课。');
      continue;
    }
    for (final c in cells) {
      buffer.writeln(
        '  ${c.slotLabel} · ${c.weekLabel} · ${c.text}',
      );
    }
    for (final n in t.notes) {
      buffer.writeln('  备注：$n');
    }
  }
  return buffer.toString();
}

// ────────────────────────────── 时间辅助 ──────────────────────────────

/// 解析日期参数（今天是基准）。
DateTime _resolveDate(DateTime now, String? raw) {
  final today = DateTime(now.year, now.month, now.day);
  final text = (raw ?? '').trim().toLowerCase();
  switch (text) {
    case '':
    case 'today':
    case '今天':
    case '今日':
      return today;
    case 'tomorrow':
    case '明天':
      return today.add(const Duration(days: 1));
    case 'yesterday':
    case '昨天':
      return today.subtract(const Duration(days: 1));
    case '后天':
      return today.add(const Duration(days: 2));
  }
  final iso = DateTime.tryParse(text);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  // `10-15` / `10/15` 这类省略年份的写法
  final md = RegExp(r'^(\d{1,2})[-/月](\d{1,2})日?$').firstMatch(text);
  if (md != null) {
    final m = int.tryParse(md.group(1)!);
    final d = int.tryParse(md.group(2)!);
    if (m != null && d != null && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      return DateTime(today.year, m, d);
    }
  }
  return today;
}

/// 本教学周内的第 [weekday] 天（1=周一）。
DateTime _dayForWeekday(DateTime now, int weekday) {
  final w = weekday.clamp(1, 7);
  final today = DateTime(now.year, now.month, now.day);
  return today.add(Duration(days: w - today.weekday));
}

/// 目标日期的中文标签。
///
/// [relative] = false 时**不带「今天 / 明天 / 本周」这类相对说法** ——
/// 查别的学期（「上学期周三谁有空」）时那个「今天」是骗人的，
/// 日期属于另一个学期，只能按星期几说。
String _dayLabel(
  DateTime now,
  DateTime day,
  Set<int> weekdays, {
  bool relative = true,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final diff = day.difference(today).inDays;
  final rel = switch (relative ? diff : 99) {
    0 => '今天',
    1 => '明天',
    -1 => '昨天',
    _ => '',
  };
  if (weekdays.length > 1) {
    return '${relative ? '本周' : '整周'}'
        '（${weekdays.map((w) => '周${_cnWeekday(w)}').join('、')}）';
  }
  final dateText =
      '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  return '$rel$dateText 周${_cnWeekday(day.weekday)}';
}

const List<String> _cnWeekdays = ['一', '二', '三', '四', '五', '六', '日'];

String _cnWeekday(int weekday) =>
    weekday >= 1 && weekday <= 7 ? _cnWeekdays[weekday - 1] : '?';

/// 空闲窗口 → 钟点文案（作息表缺该节次时返回 null，不猜）。
String? _windowTime(PeriodTable? table, FreeWindow window) =>
    periodTimeText(table, window.startPeriod, window.endPeriod);

Future<TeachingWeek?> _safeTeachingWeek(AiToolContext ctx) async {
  try {
    return await ctx.ref.read(teachingWeekProvider.future);
  } catch (_) {
    return null;
  }
}
