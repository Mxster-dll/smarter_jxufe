/// 工具集：我的课表。
///
/// 数据源 = [loadMySchedule]（先读本地缓存、缓存空才联网教务，口径见
/// `my_schedule_data.dart`）。联网那条路需要教务会话，会话不在会失败 ——
/// 所以错误文案里带了「先打开一次课表页面把数据缓存下来」这个可操作建议。
///
/// ⚠ **学期可指定**（2026-09-27）：`xn`（学年起始年）+ `xq`（0 第一 / 1 第二 /
/// 2 第二阶段）不给 = 当下学期。此前本工具的参数表里没有学期维度，模型
/// 只能答「我只查得到本学期」——而教务端点与缓存键本来就按学期分（见
/// `schedule_remote_datasource.dart` 的 `xn=&xq=`、`schedule_cache_repository.dart`
/// 的 `schedule|$year|$semester|$studentId`）。判据与提示走 [aiTermArg] /
/// [availableTermsHint]。
library;

import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/ai/tools/my_schedule_data.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';

/// 查我自己的课表。
class GetMyScheduleTool extends AiTool {
  const GetMyScheduleTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_my_schedule',
    description:
        '查「我自己」的课表（先读本地缓存，没有才去教务拉）。'
        '问「我今天有什么课」「这周几节课」「我什么时候没课」时用它。'
        '**默认是当下学期**；问别的学期（「上学期」「上一学年」「2025-2026 学年」）时'
        '传 xn（学年起始年）+ xq（0 第一学期 / 1 第二学期），'
        '此时默认按整学期列，要看某一教学周再传 week。'
        '注意：只想知道空档就直接用 find_free_time，那个会算好连续空闲时段。',
    parameters: aiObjectSchema({
      'scope': aiStrProp(
        '范围',
        enums: ['today', 'week', 'all'],
        fallbackHint:
            'today=今天（默认），week=当前教学周，all=整学期'
            '（查非本学期时默认 all）',
      ),
      'date': aiStrProp('指定日期（scope=today 时生效）：today/明天/2026-10-15/10-15'),
      'weekday': aiIntProp('只看星期几（1=周一 … 7=周日）'),
      'week': aiIntProp('只看第几教学周（默认当前教学周）', min: 1, max: 30),
      'course': aiStrProp('只看某门课（按课程名包含匹配）'),
      'xn': aiIntProp(
        '学年起始年（2025 = 2025-2026 学年；默认当下学期那一年）',
        min: 2000,
        max: 2100,
      ),
      'xq': aiIntProp(
        '学段（0 第一学期 / 1 第二学期 / 2 第二阶段；默认当下学期所在学段）',
        min: 0,
        max: 2,
      ),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final dateText = a.optStr('date');
    final weekdayArg = args['weekday'] == null ? null : a.intOf('weekday');
    final weekArg = args['week'] == null ? 0 : a.intOf('week');
    final courseFilter = a.optStr('course');
    final termArg = aiTermArg(ctx, a);
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final cur = aiCurrentTerm(ctx);
    final isCurrentTerm =
        termArg == null || (termArg.xn == cur.xn && termArg.xq == cur.xq);
    // 「今天」只对当下学期成立；查别的学期默认按整学期列。
    final scope =
        (a.optStr('scope') ?? (isCurrentTerm ? 'today' : 'all')).toLowerCase();

    final data = await loadMySchedule(ctx, xn: termArg?.xn, xq: termArg?.xq);
    if (data.error != null) return AiToolResult.fail(data.error!);
    if (data.isEmpty) {
      return AiToolResult.ok(
        '${myTermLabel(data.term)}的课表是空的（可能课表还没导入，或这学期没排课）。'
        '${termArg == null ? '' : '\n可选学期：${availableTermsHint(ctx)}'}',
      );
    }

    TeachingWeek? teachingWeek;
    try {
      teachingWeek = await ctx.ref.read(teachingWeekProvider.future);
    } catch (_) {
      teachingWeek = null;
    }

    final now = ctx.now;
    final today = DateTime(now.year, now.month, now.day);
    // 当下学期才用「当前教学周」兜底：别的学期的第 N 周与本周无关，
    // 直接不给周次（scope=all 时就是真·整学期，不被当前周过滤掉）。
    var week = weekArg > 0
        ? weekArg
        : (isCurrentTerm && teachingWeek != null && teachingWeek.week >= 1
              ? teachingWeek.week
              : 0);

    Set<int>? weekdayFilter;
    String scopeLabel;
    if (weekdayArg != null) {
      weekdayFilter = {weekdayArg.clamp(1, 7)};
      scopeLabel = '${cnWeekdayLabel(weekdayArg.clamp(1, 7))}'
          '${week > 0 ? ' · 第 $week 教学周' : ''}';
      if (week == 0) week = 1;
    } else if (scope == 'week') {
      weekdayFilter = const {1, 2, 3, 4, 5, 6, 7};
      // 非本学期说「本周」会误导（那是另一个学期的某一周）
      scopeLabel = '${isCurrentTerm ? '本周' : '该学期'}'
          '${week > 0 ? ' · 第 $week 教学周' : ''}';
      if (week == 0) week = 1;
    } else if (scope == 'all') {
      scopeLabel = '整学期';
    } else {
      final day = _resolveDay(today, dateText);
      weekdayFilter = {day.weekday};
      // 非本学期不能拿今天的日期当标签（那天不属于这个学期）
      scopeLabel = isCurrentTerm
          ? '${_relativeDay(today, day)}（'
                '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')} '
                '${cnWeekdayLabel(day.weekday)}）'
                '${week > 0 ? ' · 第 $week 教学周' : ''}'
          : cnWeekdayLabel(day.weekday);
      if (week == 0) week = 1;
    }

    final periodTable = await safePeriodTable(ctx);
    final rows = <_ScheduleRow>[];
    for (final entry in data.entries) {
      if (courseFilter != null && !entry.courseName.contains(courseFilter)) {
        continue;
      }
      for (final ct in entry.classTimes) {
        if (weekdayFilter != null && !weekdayFilter.contains(ct.dayOfWeek.dayIndex)) {
          continue;
        }
        if (week > 0 && !_activeInWeek(ct, week)) continue;
        rows.add(_ScheduleRow(entry: entry, time: ct));
      }
    }
    rows.sort((a, b) {
      final w = a.time.dayOfWeek.dayIndex.compareTo(b.time.dayOfWeek.dayIndex);
      if (w != 0) return w;
      return a.time.startPeriod.compareTo(b.time.startPeriod);
    });

    final buffer = StringBuffer()
      ..writeln('学期：${myTermLabel(data.term)}')
      ..writeln('范围：$scopeLabel'
          '${courseFilter == null ? '' : ' · 课程含「$courseFilter」'}');

    if (rows.isEmpty) {
      buffer.writeln();
      buffer.writeln(
        scope == 'all'
            ? '没有匹配的课程。'
            : '这段时间没有课（$scopeLabel）。',
      );
      return AiToolResult.ok(buffer.toString(), ui: const {'kind': 'schedule'});
    }

    buffer.writeln('共 ${rows.length} 节课：');
    for (final row in rows) {
      final time = periodTimeText(periodTable, row.time.startPeriod, row.time.endPeriod);
      buffer.writeln(
        '· ${periodRangeLabel(row.time.dayOfWeek.dayIndex, row.time.startPeriod, row.time.endPeriod)}'
        '${time == null ? '' : '（$time）'}'
        ' ${row.entry.courseName}'
        ' · ${row.entry.teacherName}'
        '${row.time.classroom.isEmpty ? '' : ' · ${row.time.classroom}'}'
        '${row.time.campus == null || row.time.campus!.isEmpty ? '' : '（${row.time.campus}）'}'
        ' · ${row.time.startWeek}-${row.time.endWeek} 周'
        '${row.time.weekParity == WeekParity.every ? '' : '(${row.time.weekParity.displayName})'}',
      );
    }

    return AiToolResult.ok(
      buffer.toString(),
      ui: {
        'kind': 'schedule',
        'count': rows.length,
        'week': week,
      },
    );
  }
}

class _ScheduleRow {
  final ScheduleEntry entry;
  final ClassTime time;

  const _ScheduleRow({required this.entry, required this.time});
}

/// 该时段在第 [week] 教学周是否上课（周次区间 + 单双周）。
bool _activeInWeek(ClassTime ct, int week) {
  if (week < ct.startWeek || week > ct.endWeek) return false;
  return switch (ct.weekParity) {
    WeekParity.every => true,
    WeekParity.odd => week.isOdd,
    WeekParity.even => week.isEven,
  };
}

DateTime _resolveDay(DateTime today, String? raw) {
  final text = (raw ?? '').trim().toLowerCase();
  switch (text) {
    case '':
    case 'today':
    case '今天':
      return today;
    case 'tomorrow':
    case '明天':
      return today.add(const Duration(days: 1));
    case '昨天':
    case 'yesterday':
      return today.subtract(const Duration(days: 1));
  }
  final iso = DateTime.tryParse(text);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  final md = RegExp(r'^(\d{1,2})[-/月](\d{1,2})日?$').firstMatch(text);
  if (md != null) {
    final m = int.tryParse(md.group(1)!);
    final d = int.tryParse(md.group(2)!);
    if (m != null && d != null) return DateTime(today.year, m, d);
  }
  return today;
}

String _relativeDay(DateTime today, DateTime day) {
  final diff = day.difference(today).inDays;
  return switch (diff) {
    0 => '今天',
    1 => '明天',
    -1 => '昨天',
    _ => '${day.month} 月 ${day.day} 日',
  };
}
