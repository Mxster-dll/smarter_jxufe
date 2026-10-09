/// 首页「数据一览」的数据源 providers（**非**渲染层）。
///
/// ⚠ 为什么单独成文件（2026-09-20 · 架构审查 ⑦）：这些 provider 从前写在
/// `home/presentation/dashboard_panel.dart` 里，而桌面小组件的数据同步
/// （`features/home_widget/data/home_widget_sync.dart`，**data 层**）要复用同一口径
/// —— 于是出现了「data 层 import 别家 presentation」的越界依赖。
/// 口径本身（电费/志愿/今日课表怎么算）属于数据层，渲染（`DashboardPanel`）与
/// 「下拉刷新」编排（`refreshDashboard`，依赖 home_widget 同步）留在 presentation。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/volunteer_hours_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/domain/volunteer_hours_stats.dart';
import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';
import 'package:smarter_jxufe/features/electricity/data/providers/electricity_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/reschedule_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_board.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_effect_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/school_time_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_effect.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';

/// 今日课程条目（从课表按「今天」过滤后抽出）。
class TodayCourse {
  final String courseName;
  final int startPeriod;
  final int endPeriod;
  final String classroom;
  final String? campus;

  /// 调课标记（调 / 停 / 补）；原课表原样 = [EffectiveMark.normal]。
  final EffectiveMark mark;

  const TodayCourse({
    required this.courseName,
    required this.startPeriod,
    required this.endPeriod,
    required this.classroom,
    this.campus,
    this.mark = EffectiveMark.normal,
  });

  String get periodLabel => '$startPeriod-$endPeriod节';
}

/// 今日的校历信息：官方事件 + 「今天为什么没课」。
///
/// 用户 2026-10-07 原话：「首页的今日课程，也要显示今日的事件；并且，如果无课，
/// 要显示无课的原因（周末 / 暑假 / 寒假 / 国庆假期）这些」。
///
/// 判定全部来自 `calendarDayEffectIndexProvider`（校历角标引擎的唯一实现），
/// 这里只做投影 —— 别在首页另写一套「今天是不是假期」。
class TodayCalendarInfo {
  /// 今日全部官方安排（已按人群过滤、已去重），如「国庆节放假」「学生课程结束」。
  final List<String> events;

  /// 今日的校历小字：假期名（「国庆节假期」）或补课说明（「补第4周周五」）。
  final String effectLabel;

  /// 补课日「按第 4 周周五的课表」的提示；非补课日空串。
  final String sourceHint;

  /// 无课原因（周末 / 寒假 / 暑假 / 国庆节假期…）；今天本就有课或说不出原因时为 null。
  final String? noClassReason;

  const TodayCalendarInfo({
    this.events = const [],
    this.effectLabel = '',
    this.sourceHint = '',
    this.noClassReason,
  });

  bool get isEmpty =>
      events.isEmpty && effectLabel.isEmpty && noClassReason == null;
}

String todayLabel(DateTime now) {
  const weekCn = ['一', '二', '三', '四', '五', '六', '日'];
  return '${now.month}月${now.day}日 周${weekCn[now.weekday - 1]}';
}

/// 电费：当前账号若有本地绑定记忆，取服务端实时余额；否则为 null（未绑定）。
final dashboardElectricityProvider = FutureProvider<ElectricityBalance?>((
  ref,
) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) return null;
  final box = await ref.read(electricityBindingBoxProvider.future);
  final raw = box.get(account);
  if (raw == null || raw.isEmpty) return null;
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return null;
  final record = RoomBindingRecord.fromJson(
    decoded.map((k, v) => MapEntry(k.toString(), v)),
  );
  if (record.roomId <= 0) return null;
  final dataSource = ref.watch(electricityRemoteDataSourceProvider);
  return dataSource.fetchBalance(username: account, roomId: record.roomId);
});

/// 志愿时长：当前账号活动记录 `recognizedHours` 求和，并额外给出**本学年**口径
/// （用户 2026-09-16 要求「志愿时长的仪表盘里还要显示本学年志愿时长」）。
///
/// 本学年 = **当下教学学年**（`currentSchoolTerm` 的 `xn`，与课表/校历同口径）；
/// 学年窗口取自校历（`schoolTimeTableProvider`）—— 取不到时该 provider 内部退回
/// 固定口径 `[xn]-09-01 ~ [xn+1]-08-31`，不会让卡片卡住或抛错。
/// 活动日期来自列表逐行详情页，取不到时 `yearKnown` 为 false → 卡片显示「—」。
final dashboardVolunteerHoursProvider = FutureProvider<VolunteerHoursStats>((
  ref,
) async {
  final activities = await ref.watch(volunteerActivitiesProvider.future);
  final now = DateTime.now();
  final term = currentSchoolTerm(
    now,
    terms: ref.watch(offlineSemesterTermsProvider),
  );
  final table = await ref.watch(schoolTimeTableProvider(term.xn).future);
  return volunteerHoursStats(activities, xn: term.xn, table: table);
});

/// 今日课程：取当前学期课表，按今天（**含校历效应与本地调课**）过滤并按时段排序。
///
/// 口径与课表页、实况窗、课前提醒完全同源（`schedule_board.dart`）：
/// 假期不排课、补课日改上被补那一周那一星期的课、被移到今天的课照常显示、
/// 「已调走」的占位不显示。从前这里只按星期过滤，假期 / 补课 / 调课全都看不见。
final dashboardTodayCoursesProvider = FutureProvider<List<TodayCourse>>((
  ref,
) async {
  final account = ref.watch(currentAccountProvider);
  if (account.isEmpty) return const [];
  final now = DateTime.now();
  // 当前学期口径 = 课表页同一函数（校历区间优先，假期取下一学期）。
  final terms = ref.watch(offlineSemesterTermsProvider);
  final term = currentSchoolTerm(now, terms: terms);
  // 课表：**cache-first + 联网刷新 + 失败降级**（与实况窗 `live_class_screen`
  // 同一套口径）。教务会话过期 / 网络抖动时退回本地缓存，卡片照常显示今天
  // 有什么课；从前直接用在线仓库，一次失败就在首页摊一张红字
  // 「课表获取失败：凭证已失效，请重新登录」（用户 2026-09-19 报的问题）。
  // 缓存也为空时才把异常抛给卡片。
  final cacheRepository = await ref.watch(
    scheduleCacheRepositoryProvider.future,
  );
  final cached = await cacheRepository.load(
    year: '${term.xn}',
    semester: '${term.xq}',
    studentId: account,
    refresh: true,
  );
  final entries = cached.entries;

  // 校历效应（假期 / 补课）——与课表页同一份索引。
  final calendar = ScheduleCalendarContext(
    effects: ref.watch(calendarDayEffectIndexProvider),
  );
  // 本地调课记录（纯本地，离线可得）：调课 / 停课 / 补课一次生效。
  final rTerm = RescheduleTerm('${term.xn}', '${term.xq}');
  final rStore = ref.read(rescheduleStoreProvider);
  await rStore.ensureLoaded(rTerm);
  final reschedules = rStore.recordsOf(rTerm);

  // 教学周：能查到就按校历查（认任意日期），否则退回「按今天推」。
  final week =
      calendar.effects?.weekOf(now) ??
      resolveTeachingWeek(now, terms: terms)?.week;
  // 校历与教学周都拿不到（离线快照过旧等）→ 退回旧口径：只按星期过滤。
  if (week == null || week < 1) {
    final weekday = now.weekday; // 1=周一 … 7=周日
    final legacy = <TodayCourse>[];
    for (final entry in entries) {
      for (final ct in entry.classTimes) {
        if (ct.dayOfWeek.dayIndex == weekday) {
          legacy.add(
            TodayCourse(
              courseName: entry.courseName,
              startPeriod: ct.startPeriod,
              endPeriod: ct.endPeriod,
              classroom: ct.classroom,
              campus: ct.campus,
            ),
          );
        }
      }
    }
    legacy.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    return legacy;
  }

  final classes = effectiveClassesOfDate(
    entries: entries,
    reschedules: reschedules,
    week: week,
    date: now,
    calendar: calendar,
  );
  final result = <TodayCourse>[];
  for (final c in classes) {
    // 「已调走」占位不属于今天 —— 课已经挪到别的时段了（与实况窗同口径）。
    if (c.isMovedAway) continue;
    result.add(
      TodayCourse(
        courseName: c.courseName,
        startPeriod: c.startPeriod,
        endPeriod: c.endPeriod,
        classroom: c.classroom,
        campus: c.campus,
        mark: c.mark,
      ),
    );
  }
  result.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
  return result;
});

/// 今日校历信息（事件 + 无课原因）。
///
/// **同步 provider**：校历效应索引本身是同步可得的（实时校历没回来时用内置快照），
/// 首页 `build` 里直接读，不会为了一行小字让卡片先转圈。
final dashboardTodayCalendarProvider = Provider<TodayCalendarInfo>((ref) {
  final now = DateTime.now();
  final index = ref.watch(calendarDayEffectIndexProvider);
  final effect = index.effectOf(now);
  return TodayCalendarInfo(
    events: [for (final e in effect.events) e.text],
    effectLabel: effect.badge,
    sourceHint: effect.sourceText,
    noClassReason: noClassReasonText(
      effect: effect,
      isWeekend: now.weekday >= DateTime.saturday,
      // 落在任何已公布学段之外（且又不是假期）→ 「还没开学」。
      beforeTermStart: index.weekOf(now) == null,
    ),
  );
});
