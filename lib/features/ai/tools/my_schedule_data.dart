/// 取「我自己的课表」—— AI 工具与本地课表之间的唯一适配层。
///
/// 口径与首页仪表盘的 `dashboardTodayCoursesProvider`
/// （`lib/features/home/presentation/dashboard_panel.dart:92`）**完全一致**：
/// 账号 = `currentAccountProvider`；学年学期 = `currentSchoolTerm`
/// （校历区间优先、假期取下一学期）；请求 = `scheduleRepositoryProvider` 的
/// `getSchedule(year:, semester:, studentId:)`，其中 `semester` 传 `'${term.xq}'`
/// = `'0'/'1'`（**照抄调用方，别自己 +1**，否则与既有缓存键不命中）。
///
/// ⚠ **学期可以指定**（2026-09-27 修）：`loadMySchedule(ctx, xn:, xq:)` 给了就用给的，
/// 不给才是 `currentSchoolTerm`（当下学期）。此前这里把学期写死成当下学期，导致
/// AI 只能答「本学期课表」—— 而 data 层（`ScheduleCacheRepository` 的
/// `schedule|$year|$semester|$studentId` 键、`ScheduleRemoteDataSource` 的
/// `xn=&xq=` 参数、`scheduleCachedEntriesProvider` 的 family）本来就支持任意学期，
/// UI 的课表页也一直在用（`schedule_screen.dart` 的学年 / 学段选择器）。
/// 参数口径统一走 [aiTermArg]（`xn` = 学年起始年，`xq` = 0 第一 / 1 第二 / 2 第二阶段）。
///
/// ⚠ **两条取数路的差别很大，本文件两条都用**：
/// - `scheduleCachedEntriesProvider`（走 `ScheduleCacheRepository.readCacheAnyStudent`）
///   是 **cache-first、不联网**，读不到返回 `const []`；
/// - `ScheduleRepository.getSchedule(...)` 是 **纯在线、无缓存**，会话不在时直接抛
///   （`Exception('获取 JSESSIONID 失败')` / `Exception('JSESSIONID 为空')`）。
///
/// 所以顺序是 **先读缓存 → 缓存空才联网**：离线时照样能答「我今天几节课」，
/// 而缓存从未写过（用户没打开过课表页）时也不会被误判成「你没课」。
///
/// ⚠ 未纳入本地「调课 / 停课 / 补课」记录（`domain/reschedule.dart`）：
/// 那是用户自己手工加的东西，且对「找空档」的影响是**增加**占用。
/// 若以后要接，入口是 `reschedule_engine.dart` 的 `effectiveClasses(...)`。
library;

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/free_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_display_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/schedule_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 本人课表 + 学期信息。
class MyScheduleData {
  final List<ScheduleEntry> entries;

  /// 学年学期（`xn` = 学年起始年，`xq` = 0 第一学期 / 1 第二学期）。
  final ({int xn, int xq}) term;

  /// 数据来自本地缓存（真 = 没联网）。
  final bool fromCache;

  final String? error;

  const MyScheduleData({
    this.entries = const [],
    this.term = (xn: 0, xq: 0),
    this.fromCache = false,
    this.error,
  });

  bool get isEmpty => entries.isEmpty;
}

/// 当下学期（`currentSchoolTerm` 在 AI 工具层的唯一入口）。
///
/// 单独包一层只为一件事：**工具里要判断「用户说的学期是不是当下学期」**，
/// 而那个判据在四个地方都要用（`get_my_schedule` / `query_timetable` /
/// `find_free_time` / 快照），各写一遍 `currentSchoolTerm(ctx.now, terms: …)`
/// 迟早会漏掉 `terms:` 参数（漏了就退化成月份经验规则，学期会错一个月）。
({int xn, int xq}) aiCurrentTerm(AiToolContext ctx) => currentSchoolTerm(
  ctx.now,
  terms: ctx.ref.read(offlineSemesterTermsProvider),
);

/// 从工具参数里读「学年 + 学段」；两个都没给 → null（= 当下学期）。
///
/// - `xn` = 学年起始年（`2025-2026 学年` → `2025`），`xq` = 0 第一 / 1 第二 / 2 第二阶段；
/// - **只给一个时，另一个补当下学期的值**（模型经常只给 `xn`）；
/// - 越界一律记 [AiArgs.noteError] 并返回 null —— 调用方在 `a.hasError` 处统一拒绝，
///   免得按一个不存在的学期去拉数据、再把「查不到」当成「你没课」。
({int xn, int xq})? aiTermArg(AiToolContext ctx, AiArgs a) {
  if (a.raw['xn'] == null && a.raw['xq'] == null) return null;
  final cur = aiCurrentTerm(ctx);
  final xn = a.raw['xn'] == null ? cur.xn : a.intOf('xn', fallback: cur.xn);
  final xq = a.raw['xq'] == null ? cur.xq : a.intOf('xq', fallback: cur.xq);
  if (xn < 2000 || xn > 2100) {
    a.noteError('xn 应为学年起始年（如 2025 表示 2025-2026 学年）');
    return null;
  }
  if (xq < 0 || xq > 2) {
    a.noteError('xq 只能是 0（第一学期）/ 1（第二学期）/ 2（第二阶段）');
    return null;
  }
  return (xn: xn, xq: xq);
}

/// 可选学期清单（离线校历快照 + 当下学期；从新到旧，最多 [limit] 个）。
///
/// 用途：模型不知道「上一学年」该填什么 `xn` 时，把清单塞进提示词 / 错误文案，
/// 省掉一轮「瞎猜 → 报错 → 重试」。**纯离线**，不发请求。
///
/// [terms] 传校历学期列表（`offlineSemesterTermsProvider` 或实时校历）；
/// 只有 [Ref] 没有 [AiToolContext] 的地方（如 `ai_snapshot.dart`）用这个纯函数。
List<({int xn, int xq})> availableSchoolTermsFrom(
  List<WxSemesterArrangement> terms, {
  required ({int xn, int xq}) current,
  int limit = 6,
}) {
  final seen = <String>{};
  final out = <({int xn, int xq})>[];
  void add(({int xn, int xq}) t) {
    if (t.xn < 2000 || t.xn > 2100 || t.xq < 0 || t.xq > 2) return;
    if (seen.add('${t.xn}-${t.xq}')) out.add(t);
  }

  for (final t in terms) {
    add((xn: t.xn, xq: t.xq));
  }
  add(current);
  out.sort(
    (a, b) => a.xn != b.xn ? b.xn.compareTo(a.xn) : b.xq.compareTo(a.xq),
  );
  return out.take(limit).toList();
}

/// [availableSchoolTermsFrom] 的 `AiToolContext` 版。
List<({int xn, int xq})> availableSchoolTerms(
  AiToolContext ctx, {
  int limit = 6,
}) => availableSchoolTermsFrom(
  ctx.ref.read(offlineSemesterTermsProvider),
  current: aiCurrentTerm(ctx),
  limit: limit,
);

/// 「可选学期」一行文本（提示词与「那个学期查不到」的错误文案共用）。
String availableTermsHintFrom(
  List<({int xn, int xq})> terms, {
  required ({int xn, int xq}) current,
}) => terms
    .map(
      (t) => '${myTermLabel(t)}（xn=${t.xn}，xq=${t.xq}'
          '${t.xn == current.xn && t.xq == current.xq ? '，本学期' : ''}）',
    )
    .join(' / ');

/// [availableTermsHintFrom] 的 `AiToolContext` 版。
String availableTermsHint(AiToolContext ctx, {int limit = 6}) =>
    availableTermsHintFrom(
      availableSchoolTerms(ctx, limit: limit),
      current: aiCurrentTerm(ctx),
    );

/// 读本人课表（任何失败都变成 [MyScheduleData.error]，不抛）。
///
/// **先缓存后联网**：缓存命中就直接用（离线可用、也省一次教务请求）；
/// 缓存空（从没打开过该学期课表页）才去打教务 —— 只有这一条路会因会话失效而失败。
///
/// [xn] / [xq] 不给 = 当下学期；给了就查那个学期（过去学期通常没有缓存，
/// 会走教务联网那条路）。
Future<MyScheduleData> loadMySchedule(
  AiToolContext ctx, {
  int? xn,
  int? xq,
}) async {
  final account = ctx.ref.read(currentAccountProvider);
  if (account.isEmpty) {
    return const MyScheduleData(error: '当前没有登录账号，读不到课表。请先完成统一身份认证登录。');
  }
  final cur = aiCurrentTerm(ctx);
  final term = (xn == null && xq == null)
      ? cur
      : (xn: xn ?? cur.xn, xq: xq ?? cur.xq);

  // ① 本地缓存（不联网；失败/为空都返回空列表，不抛）
  try {
    final cached = await ctx.ref.read(
      scheduleCachedEntriesProvider((xn: term.xn, xq: term.xq)).future,
    );
    if (cached.isNotEmpty) {
      return MyScheduleData(entries: cached, term: term, fromCache: true);
    }
  } catch (_) {
    // 缓存读不出来 → 走联网那条
  }

  // ② 教务（纯在线、无缓存；会话不在会抛）
  try {
    final repository = await ctx.ref.read(scheduleRepositoryProvider.future);
    final entries = await repository.getSchedule(
      year: '${term.xn}',
      semester: '${term.xq}',
      studentId: account,
    );
    return MyScheduleData(entries: entries, term: term);
  } catch (e) {
    return MyScheduleData(
      term: term,
      error: '课表读取失败：$e（也可以先打开一次「课表」页面把数据缓存下来）',
    );
  }
}

/// 本人课表的占用槽（给「找无课时间」引擎用）。
class MyScheduleSlots {
  final List<ScheduleSlot> slots;
  final String? error;

  const MyScheduleSlots({this.slots = const [], this.error});
}

Future<MyScheduleSlots> myScheduleSlots(
  AiToolContext ctx, {
  required int week,
  int? xn,
  int? xq,
}) async {
  final data = await loadMySchedule(ctx, xn: xn, xq: xq);
  if (data.error != null) return MyScheduleSlots(error: data.error);
  final slots = <ScheduleSlot>[];
  for (final entry in data.entries) {
    slots.addAll(
      slotsFromClassTimes(
        entry.classTimes,
        owner: '我',
        courseName: entry.courseName,
      ),
    );
  }
  return MyScheduleSlots(slots: slots);
}

/// 学期显示名（`2026-2027学年第一学期` 这种；拿不到时给 `2026-0`）。
String myTermLabel(({int xn, int xq}) term) {
  if (term.xn == 0) return '未知学期';
  final name = term.xq == 0 ? '第一学期' : (term.xq == 1 ? '第二学期' : '第 $term.xq 学段');
  return '${term.xn}-${term.xn + 1}学年$name';
}

const List<String> _cnWeekdays = ['一', '二', '三', '四', '五', '六', '日'];

/// `周三`。
String cnWeekdayLabel(int weekday) =>
    weekday >= 1 && weekday <= 7 ? '周${_cnWeekdays[weekday - 1]}' : '周?';

/// 把一节次区间写成 `周一 3-4 节`。
String periodRangeLabel(int weekday, int startPeriod, int endPeriod) =>
    startPeriod == endPeriod
    ? '${cnWeekdayLabel(weekday)} 第 $startPeriod 节'
    : '${cnWeekdayLabel(weekday)} 第 $startPeriod-$endPeriod 节';

/// 作息表（缓存优先，失败返回 null —— **不联网等待**）。
///
/// 用 `cachedPeriodTableProvider` 而不是 `currentPeriodTableProvider`：
/// 对话里多等一次网络只为拿钟点不划算；缓存 + 内置兜底表已经能给出
/// `08:00-09:35` 这个量级的答案。
Future<PeriodTable?> safePeriodTable(AiToolContext ctx) async {
  try {
    return await ctx.ref.read(cachedPeriodTableProvider.future);
  } catch (_) {
    return null;
  }
}

/// 节次区间 → `08:00-09:35`（作息表缺该节次时返回 null，**不猜**）。
String? periodTimeText(PeriodTable? table, int startPeriod, int endPeriod) {
  if (table == null) return null;
  final start = table.periodOf(startPeriod);
  final end = table.periodOf(endPeriod);
  if (start == null || end == null) return null;
  return '${start.start}-${end.end}';
}
