/// 工具集：志愿时长 / 综测 / 材料库 / 校历 / 电费与网费。
///
/// 这几块都是「生活与综合数据」，共同点是**大多有本地缓存**（志愿时长与网费
/// 走学校平台，需要登录；电费要绑定过宿舍）。每个工具都自己吞异常并如实
/// 回报原因 —— 网关层不该因为一个数据源挂了就整轮失败。
library;

import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/volunteer_activity.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/domain/volunteer_hours_stats.dart';
import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';
// ⚠ 电费的聚合 provider 定义在首页仪表盘里（那里已经处理了「按账号记忆绑定」
// 与「未绑定返回 null」）。复制一份到这里会变成两份口径，所以直接复用。
import 'package:smarter_jxufe/features/home/data/providers/dashboard_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/materials/domain/material_grouping.dart';
import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_calendar_providers.dart';
// 学年 / 假期的唯一出处（`domain/school_time.dart` 由它 export）。
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_time_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

/// 志愿服务时长（累计 + 本学年）。
class GetVolunteerHoursTool extends AiTool {
  const GetVolunteerHoursTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_volunteer_hours',
    description:
        '查志愿服务时长：累计认定时长、**本学年**时长（教学学年口径，'
        '窗口 9 月 1 日 ~ 次年 8 月 31 日），以及逐条活动记录。'
        '问「我志愿时长多少了」「够不够综测加分」用它。'
        '需要登录（走学校综合管理平台，在线）。',
    parameters: aiObjectSchema({
      'limit': aiIntProp('最多列多少条活动记录（默认 20）', min: 1, max: 100),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final limit = a.intOf('limit', fallback: 20);
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final List<VolunteerActivity> acts;
    try {
      acts = await ctx.ref.read(volunteerActivitiesProvider.future);
    } catch (e) {
      return AiToolResult.fail('志愿时长读取失败：$e');
    }
    if (acts.isEmpty) {
      return const AiToolResult.ok('没有查到志愿服务记录。');
    }

    final term = currentSchoolTerm(
      ctx.now,
      terms: ctx.ref.read(offlineSemesterTermsProvider),
    );
    final stats = volunteerHoursStats(acts, xn: term.xn);

    final buffer = StringBuffer()
      ..writeln('志愿服务时长：累计 ${_num(stats.total)} 小时。')
      // yearKnown = false 表示一条活动的日期都没取到 —— 这时**显示「—」而不是 0**，
      // 「取不到日期」和「本学年真的 0 小时」是两件事。
      ..writeln(
        '本学年（${stats.yearKnown ? stats.yearLabel : '起始年未知'}）：'
        '${stats.yearKnown ? '${_num(stats.currentYear)} 小时' : '—（活动日期没能取到，无法归集）'}',
      );
    if (stats.yearKnown) {
      buffer.writeln('上一学年：${_num(stats.previousYear)} 小时');
    }

    // 按日期倒序，最近的在前（没有日期的沉底）。
    final sorted = [...acts]..sort((x, y) {
      final dx = x.activityDate;
      final dy = y.activityDate;
      if (dx == null && dy == null) return 0;
      if (dx == null) return 1;
      if (dy == null) return -1;
      return dy.compareTo(dx);
    });
    buffer.writeln();
    buffer.writeln('活动记录（最近 ${sorted.length > limit ? limit : sorted.length} 条）：');
    for (final v in sorted.take(limit)) {
      buffer.writeln(
        '· ${v.activityName}'
        '${v.recognizedHours.trim().isEmpty ? '' : ' · 认定 ${v.recognizedHours} 小时'}'
        '${v.activityTimeText.trim().isEmpty ? '' : ' · ${v.activityTimeText}'}'
        '${v.activityCategory.trim().isEmpty ? '' : ' · ${v.activityCategory}'}'
        '${v.recognitionStatus.trim().isEmpty ? '' : ' · ${v.recognitionStatus}'}',
      );
    }

    return AiToolResult.ok(
      buffer.toString(),
      ui: {
        'kind': 'volunteerHours',
        'total': stats.total,
        if (stats.yearKnown) 'currentYear': stats.currentYear,
      },
    );
  }
}

/// 综合素质测评（综测）测算结果。
class GetZongceTool extends AiTool {
  const GetZongceTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_zongce',
    description:
        '查综合素质测评（综测）的测算结果：总评成绩、五育（德/智/体/美/劳）'
        '各自得分与等次、各项明细、加分材料贡献。'
        '默认查**当前测评学年**（9 月起算上一学年）。'
        '问「我综测多少分」「德育为什么被扣分」用它。'
        '注意：总评是五育**按占比加权**（占比由用户设置），不是简单平均。',
    parameters: aiObjectSchema({
      'year': aiIntProp(
        '测评学年（= 学年**结束**年，2026 表示 2025-2026 学年；不给则当前）',
        min: 2000,
        max: 2100,
      ),
      'detail': aiBoolProp('是否展开全部明细行（默认只给五育与关键明细）'),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final year = args['year'] == null
        ? zcDefaultYear(ctx.now)
        : a.intOf('year', fallback: zcDefaultYear(ctx.now));
    final detail = a.boolOf('detail');
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final List<ZcMaterial> mats;
    final ZcManual manual;
    try {
      mats = await ctx.ref.read(zcMaterialsProvider.future);
      final store = await ctx.ref.read(zcStoreProvider.future);
      manual = await store.loadManual(year);
    } catch (e) {
      return AiToolResult.fail('综测数据读取失败：$e');
    }

    // 两个自动源拿不到就是 null → 引擎回退到手动值（**别传 0**，那会变成
    // 「自动取到 0 分」而不是「没取到」）。
    double? autoWeight;
    double? autoVolunteer;
    try {
      autoWeight = await ctx.ref.read(zcAutoWeightProvider(year).future);
    } catch (_) {}
    try {
      autoVolunteer = await ctx.ref.read(zcAutoVolunteerProvider(year).future);
    } catch (_) {}

    final r = zcCalculate(
      mats,
      manual: manual,
      autoWeight: autoWeight,
      autoVolunteer: autoVolunteer,
    );

    final buffer = StringBuffer()
      ..writeln(
        '综测（测评学年 $year · ${year - 1}-$year）'
        '总评成绩 ${_num(r.total)} 分。',
      )
      ..writeln('五育占比：${r.weights.label}'
          '${r.weightMissing ? '（合计不是 100%，按填写值直接算）' : ''}');
    buffer
      ..writeln('· 德育 ${_num(r.deyu)}（${r.gD.label}）')
      ..writeln('· 智育 ${_num(r.zhiyu)}（${r.gZ.label}）')
      ..writeln('· 体育 ${_num(r.tiyu)}（${r.gT.label}）')
      ..writeln('· 美育 ${_num(r.meiyu)}（${r.gM.label}）')
      ..writeln('· 劳育 ${_num(r.laoyu)}（${r.gL.label}）')
      ..writeln(
        '智育加权 ${_num(r.weightUsed)} 分（${r.weightAuto ? '自动取自成绩' : '手动填写'}）；'
        '劳育志愿 ${_num(r.volunteerUsed)} 小时（${r.volunteerAuto ? '自动取自志愿时长' : '手动填写'}）。',
      );
    // 加分材料：按育统计条数（综测页 2026-09-27 起德育也分板块，这里给模型
    // 一个概览）；逐条「计入 / 未计入」放在 detail 分支里。
    final byDim = <String, int>{};
    for (final m in mats) {
      final dim = zcTypeSpecOf[m.typeId]?.dim ?? '';
      byDim[dim] = (byDim[dim] ?? 0) + 1;
    }
    if (mats.isEmpty) {
      buffer.writeln('还没有任何加分材料（材料库为空）。');
    } else {
      final parts = [
        for (final e in _zongceDimLabels.entries)
          if ((byDim[e.key] ?? 0) > 0) '${e.value} ${byDim[e.key]}',
      ];
      buffer.writeln('加分材料 ${mats.length} 条：${parts.join(' · ')}。');
    }
    if (r.details.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(detail ? '全部明细：' : '关键明细（前 12 条，要全部请给 detail=true）：');
      final rows = detail ? r.details : r.details.take(12).toList();
      for (final d in rows) {
        buffer.writeln(
          '· ${d.label}：${_num(d.value)}${d.auto ? '（自动）' : ''}',
        );
      }
    } else {
      buffer.writeln();
      buffer.writeln('明细为空 —— 可能这一学年还没录材料，也没填手动项。');
    }

    // 逐条材料（含「计入 / 未计入」）—— 回答「哪一条加分算进去了 / 为什么没算」
    // 靠的就是这一段，所以只在 detail 时要（默认省 token）。
    if (detail && mats.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        manual.openAccumulate
            ? '加分材料明细（本学年开了「放开所有累加」：所有「就高一次」都改'
                '多项叠加、附加分封顶全取消，因此每条有分的材料一律计入）：'
            : '加分材料明细（「计入」= 最终贡献了总分；德育按表 3~7 各板块口径，'
                '智育竞赛按「最高项 >5 只计最高，否则累加封顶 5 分」；'
                '体育 / 美育 / 劳育没有这层取舍，只给分值）：',
      );
      final lines = _zongceMaterialLines(mats, open: manual.openAccumulate);
      for (final line in lines.take(40)) {
        buffer.writeln(line);
      }
      if (lines.length > 40) {
        buffer.writeln('（还有 ${lines.length - 40} 条未列出）');
      }
    }

    return AiToolResult.ok(
      buffer.toString(),
      ui: {'kind': 'zongce', 'year': year, 'total': r.total},
    );
  }
}

/// 材料库（加分材料清单）。
class ListMaterialsTool extends AiTool {
  const ListMaterialsTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'list_materials',
    description:
        '查材料库里的加分材料（用户手工录入的竞赛获奖、论文、外语证书、'
        '荣誉、志愿服务等），按材料类型分组。'
        '问「我录了哪些材料」「有没有漏交的获奖」用它。'
        '材料**不分学年**（只有各自的手填日期）。本地数据，离线可得。',
    parameters: aiObjectSchema({
      'type': aiStrProp('只看某类材料的名称包含该关键词的（如「竞赛」「外语」）'),
      'year': aiIntProp('只看某一年的材料（按材料日期）', min: 2000, max: 2100),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final type = a.optStr('type');
    final year = args['year'] == null ? null : a.intOf('year', fallback: 0);
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final List<ZcMaterial> all;
    try {
      all = await ctx.ref.read(zcMaterialsProvider.future);
    } catch (e) {
      return AiToolResult.fail('材料库读取失败：$e');
    }
    if (all.isEmpty) {
      return const AiToolResult.ok('材料库里还没有材料。');
    }

    var mats = all;
    if (type != null) {
      mats = [
        for (final m in mats)
          if (m.displayName.contains(type) || m.spec.label.contains(type)) m,
      ];
    }
    if (year != null) {
      mats = [
        for (final m in mats)
          if (m.date?.year == year) m,
      ];
    }
    if (mats.isEmpty) {
      return AiToolResult.ok('没有符合条件的材料（本地共 ${all.length} 条）。');
    }

    final buffer = StringBuffer()
      ..writeln('材料库共 ${mats.length} 条${mats.length == all.length ? '' : '（本地总共 ${all.length} 条）'}：');
    for (final g in groupMaterialsByType(mats)) {
      buffer.writeln();
      buffer.writeln('【${g.label}】${g.count} 条');
      for (final m in g.materials) {
        buffer.writeln(
          '· ${m.displayName}'
          '${m.dateIso.trim().isEmpty ? '' : ' · ${m.dateIso}'}'
          '${m.manualScore == null ? '' : ' · 原始成绩 ${_num(m.manualScore!)}'}'
          '${m.note.trim().isEmpty ? '' : ' · ${_oneLine(m.note)}'}',
        );
      }
    }

    return AiToolResult.ok(
      buffer.toString(),
      ui: {'kind': 'materials', 'count': mats.length},
    );
  }
}

/// 校历（放假 / 补课 / 教学周）。
class GetSchoolCalendarTool extends AiTool {
  const GetSchoolCalendarTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_school_calendar',
    description:
        '查校历：当前是第几教学周、**学年的起止日**、寒假与暑假区间、某个学期'
        '有哪些**非工作日（放假）**区间、校历备注（如调休安排）。'
        '问「什么时候放假」「现在第几周」「上一学年最后一天是哪天」用它。默认查当前学期。'
        '注意：这里的「学年」= 第一学期第一天 ~ 下学年第一学期第一天**前一天**，'
        '由教务校历推导（如 2025-2026 学年 = 2025-09-01 ~ 2026-09-06）；'
        '**不是**「9 月 1 日 ~ 次年 8 月 31 日」这种固定写法，别自己按那个推。',
    parameters: aiObjectSchema({
      'xn': aiIntProp('学年起始年（如 2026 = 2026-2027 学年；不给则当前）', min: 2000, max: 2100),
      'xq': aiIntProp('学期：0 = 第一学期，1 = 第二学期（不给则当前）', min: 0, max: 1),
      'month': aiIntProp('只看某个月（1-12；不给则全部）', min: 1, max: 12),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final term = currentSchoolTerm(
      ctx.now,
      terms: ctx.ref.read(offlineSemesterTermsProvider),
    );
    final xn = args['xn'] == null ? term.xn : a.intOf('xn', fallback: term.xn);
    final xq = args['xq'] == null ? term.xq : a.intOf('xq', fallback: term.xq);
    final month = args['month'] == null ? null : a.intOf('month', fallback: 0);
    if (a.hasError) return AiToolResult.fail(a.errorText);

    String weekLabel = '';
    try {
      final tw = await ctx.ref.read(teachingWeekProvider.future);
      if (tw != null) weekLabel = tw.label;
    } catch (_) {
      // 教学周取不到 → weekLabel 保持空串：答案里少一个「今天是第 N 周」而已，
      // 不该让整个工具调用失败（下面校历取不到才 `fail`，因为那是主体数据）。
    }

    final SchoolCalendar cal;
    try {
      cal = await ctx.ref.read(schoolCalendarProvider((xn: xn, xq: xq)).future);
    } catch (e) {
      return AiToolResult.fail('校历读取失败：$e');
    }

    final StringBuffer buffer = StringBuffer();
    if (weekLabel.isNotEmpty) buffer.writeln('今天是$weekLabel。');

    // 学年（用户 2026-09-27 问「上一学年的最后一天是？」时，本工具只报学期起止，
    // 模型于是自己按「9/1 ~ 次年 8/31」硬推了一个错答案）。学年窗口的唯一出处是
    // `schoolTimeTableProvider` —— 它由教务校历推导（第一学期第一天 ~ 下学年
    // 第一天前一天），取不到就留空，**不许在这里另算一套**。
    buffer.writeln();
    try {
      final table = await ctx.ref.read(schoolTimeTableProvider(xn).future);
      final year = table.yearOf(xn);
      if (!year.isKnown) {
        buffer.writeln('学年：${year.label} —— 校历还没公布，起止日未知。');
      } else {
        buffer.writeln('学年：${year.label} = ${year.rangeText}');
        if (!year.isComplete) {
          buffer.writeln(
            '（结束日 = 下学年第一学期第一天 − 1 天，下学年校历尚未公布 → 未定；'
            '别当成 8 月 31 日，也不等于「教学周结束」那一天。）',
          );
        }
      }
      for (final b in table.breaksOf(xn)) {
        buffer.writeln(
          b.end == null
              ? '· ${b.label}：${schoolDayText(b.start)} 起（结束日待公布）'
              : '· ${b.label}：${schoolDayText(b.start)} ~ ${schoolDayText(b.end!)}'
                    '（${b.days} 天）',
        );
      }
    } catch (e) {
      buffer.writeln('学年信息读取失败：$e');
    }

    buffer.writeln();
    buffer.writeln(
      '${cal.title}（${cal.notes.isEmpty ? '无备注' : '备注 ${cal.notes.length} 条'}）',
    );
    if (cal.notes.isNotEmpty) {
      buffer.writeln();
      for (final n in cal.notes) {
        buffer.writeln('· ${_oneLine(n)}');
      }
    }

    // 把「教务标为非工作日」的连续日期合并成区间（一天一行太碎）。
    final runs = _nondayRuns(cal, month: month);
    buffer.writeln();
    if (runs.isEmpty) {
      buffer.writeln(
        month == null
            ? '这个学期的校历上没有标出非工作日（放假安排可能还没发布）。'
            : '$month 月没有标出非工作日。',
      );
    } else {
      buffer.writeln('非工作日区间（教务标注，可能是放假）：');
      for (final r in runs) {
        buffer.writeln('· ${r.label}（${r.days} 天）');
      }
    }

    return AiToolResult.ok(
      buffer.toString(),
      ui: {'kind': 'calendar', 'xn': xn, 'xq': xq, 'breaks': runs.length},
    );
  }
}

/// 电费与校园网费余额。
class GetEnergyTool extends AiTool {
  const GetEnergyTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'get_energy',
    description:
        '查宿舍电费余额与校园网费余额。问「宿舍还有多少电」「网费还能用多久」用它。'
        '电费需要用户在「电费」页绑定过宿舍（没绑定会返回未绑定）；'
        '网费走门户 / 平台 GUID。都是在线取数。',
    parameters: aiObjectSchema({}),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final buffer = StringBuffer();
    var any = false;

    try {
      final ElectricityBalance? elec = await ctx.ref.read(
        dashboardElectricityProvider.future,
      );
      any = true;
      if (elec == null) {
        buffer.writeln('电费：还没绑定宿舍，读不到余额。');
      } else {
        buffer.writeln(
          '电费：剩余 ${elec.balance} ${elec.unit}（房间编码 ${elec.roomNo}）。',
        );
      }
    } catch (e) {
      buffer.writeln('电费：读取失败（$e）。');
    }

    try {
      final net = await ctx.ref.read(netFeeSummaryProvider.future);
      any = true;
      if (net.balance == null) {
        buffer.writeln(
          '校园网费：暂无可用数据源'
          '${net.hasGuid ? '' : '（还没配置平台标识）'}'
          '${net.liveError == null ? '' : '，实时源失败：${_oneLine(net.liveError!)}'}。',
        );
      } else {
        buffer.writeln(
          '校园网费：余额 ${fmtYuan(net.balance!)} 元'
          '（来源：${net.source.label}'
          '${net.username == null ? '' : ' · 账号 ${net.username}'}）。',
        );
        if (net.records.isNotEmpty) {
          buffer.writeln('最近充值 ${net.records.length} 笔。');
        }
      }
    } catch (e) {
      buffer.writeln('校园网费：读取失败（$e）。');
    }

    if (!any) return const AiToolResult.fail('电费与网费都没能取到。');
    return AiToolResult.ok(buffer.toString(), ui: const {'kind': 'energy'});
  }
}

// ────────────────────────────── 小工具 ──────────────────────────────

/// 一段连续的非工作日。
typedef _DayRun = ({String label, int days});

/// 把一个学期（或某个月）里教务标为非工作日的日期合并成连续区间。
List<_DayRun> _nondayRuns(SchoolCalendar cal, {int? month}) {
  final days = <DateTime>[];
  for (final m in cal.months) {
    if (month != null && m.month != month) continue;
    for (final row in m.rows) {
      for (var i = 0; i < row.days.length; i++) {
        final d = row.days[i];
        if (d == null) continue;
        if (row.kindAt(i) != CalendarDayKind.nonday) continue;
        days.add(DateTime(m.year, m.month, d));
      }
    }
  }
  if (days.isEmpty) return const [];
  days.sort();
  final runs = <_DayRun>[];
  var start = days.first;
  var prev = days.first;
  void flush() {
    runs.add((
      label: _rangeLabel(start, prev),
      days: prev.difference(start).inDays + 1,
    ));
  }

  for (final d in days.skip(1)) {
    if (d.difference(prev).inDays == 1) {
      prev = d;
      continue;
    }
    flush();
    start = d;
    prev = d;
  }
  flush();
  return runs;
}

String _rangeLabel(DateTime start, DateTime end) {
  String md(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  if (start == end) return '${start.year}-${md(start)}';
  if (start.year == end.year) return '${start.year}-${md(start)} ~ ${md(end)}';
  return '${start.year}-${md(start)} ~ ${end.year}-${md(end)}';
}

/// 数字：整数不带小数点（60 → `60`），小数保留一位。
String _num(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);

String _oneLine(String raw) => raw.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 材料 `dim` → 育名（按 `zcTypeSpecOf[...].dim` 归类统计条数）。
const Map<String, String> _zongceDimLabels = {
  'd': '德育',
  'z': '智育',
  't': '体育',
  'm': '美育',
  'l': '劳育',
};

/// 综测材料类型里**有「计入 / 未计入」口径**的德育六类（= 表 3~表 7 六个板块：
/// 优秀事迹 / 思想教育·贡献度 / 思想教育·参与度 / 公共服务 / 荣誉称号·个人 /
/// 荣誉称号·集体）。
const Set<ZcTypeId> _zongceMoralTypes = {
  ZcTypeId.deed,
  ZcTypeId.eduCon,
  ZcTypeId.eduPart,
  ZcTypeId.servicePost,
  ZcTypeId.honorP,
  ZcTypeId.honorG,
};

/// 加分材料逐条明细（给模型看）：每条一行，标出它在**总分里到底算没算**。
///
/// 只有两类材料有这层口径，且与综测页的高亮**完全同源**（别再写第三套判断）：
/// - 智育 · 学科竞赛 → [zcContestContributingIds]；
/// - 德育六板块（优秀事迹 / 思想教育·贡献度 / 思想教育·参与度 / 公共服务 /
///   荣誉称号·个人 / 荣誉称号·集体）→
///   [zcMoralContributingIds]。
/// 其余类别（体育 / 美育 / 劳育）没有取舍，只给分值。
///
/// [open] = `ZcManual.openAccumulate`（「放开所有累加」开关）：放开档所有项
/// 一律累加，`contest` / `moral` 两个集合会是「全部有分的材料」，逐条明细因此
/// 一律标「计入」—— 与综测页高亮同源。
List<String> _zongceMaterialLines(List<ZcMaterial> mats, {bool open = false}) {
  final contest = zcContestContributingIds(mats, open: open);
  final moral = zcMoralContributingIds(mats, open: open);
  final out = <String>[];
  for (final m in mats) {
    final spec = zcTypeSpecOf[m.typeId];
    // '德育 · 优秀事迹（表 3）' → '德育 · 优秀事迹'
    final board = (spec?.section ?? '其它材料').split('（').first.trim();
    final v = zcMaterialValue(m);
    final String mark;
    if (v == null) {
      mark = '未计分（缺级别 / 类别，或档位越界）';
    } else if (m.typeId == ZcTypeId.contest) {
      mark = '+${_num(v)}（${contest.contains(m.id) ? '计入' : '未计入'}）';
    } else if (_zongceMoralTypes.contains(m.typeId)) {
      mark = '+${_num(v)}（${moral.contains(m.id) ? '计入' : '未计入'}）';
    } else {
      mark = '+${_num(v)}';
    }
    out.add('· [$board] ${_oneLine(m.name)}（${m.optionLabel}）$mark');
  }
  return out;
}
