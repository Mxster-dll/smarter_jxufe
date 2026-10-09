/// 校历事件 → **课表效应**（这一天要不要上课 / 上哪一天的课）。
///
/// 用户 2026-10-07 原话：「关于课表的显示，应该响应校历里的事件。具体为如果是假期
/// 就不显示课程（除非是移课移到那天），然后还有诸如 xx 天补 xx 周 xx 天课程，这样的
/// 课表也要动态响应。」
///
/// ## 与 [CalendarMarkIndex] 的分工（**判定不许再写一份**）
/// - `calendar_day_mark.dart` 负责「这天是假还是班」的**角标判定**（数据源优先级、
///   人群过滤、寒暑假整段延伸、噪声排除都在那里）；
/// - 本文件只做**语义转译**：把「假」翻译成「不上课」、把「补第4周周五的课」翻译成
///   「这天按第 4 周周五的课表上课」，并给出「今天为什么没课」的文案。
///
/// 所以这里**不重新判假**，一律走 `CalendarMarkIndex.markOf`；补课目标（第几周 + 星期几）
/// 由 [parseMakeupTarget] 从官方原文里解析（教务没有结构化字段，原文就是唯一出处）。
///
/// ## 官方原文的真实形态（实测台账）
/// - `补第4周周五的课`（261 表格式，2026-10-10）：**带**周次 —— 被补的是国庆假期里
///   那一次（第 4 周周五 = 10-02，正在 10-01~10-07 假期内，自洽 ✅）；
/// - `补第10周周一的课程`（252 行式，2026-05-09）：**带**周次，同理（第 10 周周一
///   = 05-04，在劳动节假期内）；
/// - `补周五的课`（旧版整段文字，如 2018 年 `4月8日补周五的课`）：**不带**周次 →
///   按「与补课日同一教学周」处理（调休补课总是补本周被假期冲掉的那一天）。
library;

import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 校历对某一天的**上课安排**影响。
enum CalendarDayEffectKind {
  /// 普通日子：按「本教学周 + 本星期」的课表上课。
  normal,

  /// 假期：本日不上课（被移课 / 补课搬到这一天的除外）。
  holiday,

  /// 补课 / 调休上班：本日按「被补的那一周那一星期」的课表上课。
  makeup,
}

/// 某一天的课表效应（纯数据，[CalendarDayEffectIndex.effectOf] 的产物）。
class CalendarDayEffect {
  /// 归一化到 0 点的日期。
  final DateTime day;

  final CalendarDayEffectKind kind;

  /// 展示名：假期 =「国庆节假期」「寒假」；补课 =「补第4周周五的课」；普通 = 空串。
  final String name;

  /// 补课日要上的课取自哪一教学周；null = 与补课日同一周（原文没写周次）。
  final int? sourceWeek;

  /// 补课日要上的课取自星期几（**1 = 周一 … 7 = 周日**，与 `DateTime.weekday`
  /// 同口径）；null = 与补课日同一星期（原文只写了「补课」没写星期）。
  final int? sourceWeekday;

  /// 是否寒 / 暑假整段（比法定节假日长得多，界面文案不同）。
  final bool isBreak;

  /// 当天全部官方安排（已按人群过滤、已去重；首页「今日事件」直接用）。
  final List<WxCalEvent> events;

  /// 判定依据（排障用，与 [CalendarDayMark.reason] 同源）。
  final String reason;

  const CalendarDayEffect({
    required this.day,
    required this.kind,
    this.name = '',
    this.sourceWeek,
    this.sourceWeekday,
    this.isBreak = false,
    this.events = const [],
    this.reason = '',
  });

  bool get isHoliday => kind == CalendarDayEffectKind.holiday;

  bool get isMakeup => kind == CalendarDayEffectKind.makeup;

  /// 表头（课表列头 / 首页日期行）用的小字：假期名 / 补课说明；普通日为空串。
  ///
  /// 补课日的官方原文是「补第4周周五的课」，表头放不下且尾巴是废话 →
  /// 去掉「的课 / 的课程」与句末标点（列宽不够时由调用方 `FittedBox` 缩放）。
  String get badge {
    if (!isMakeup) return name;
    return name
        .replaceAll(RegExp(r'[。．.\s]+$'), '')
        .replaceAll(RegExp(r'的?(?:课程|课)$'), '');
  }

  /// 补课日「上哪一天的课」的说明，如「按第 4 周周五的课表」；非补课日为空串。
  String get sourceText {
    if (!isMakeup) return '';
    final w = sourceWeek;
    final d = sourceWeekday == null ? null : calendarWeekdayName(sourceWeekday!);
    if (w == null && d == null) return '';
    final weekPart = w == null ? '' : '第 $w 周';
    return '按$weekPart${d ?? ''}的课表';
  }

  @override
  String toString() =>
      'CalendarDayEffect(${kind.name} $name'
      '${sourceWeek == null ? '' : ' ← 第$sourceWeek周'}'
      '${sourceWeekday == null ? '' : '周$sourceWeekday'})';
}

/// 「日期 → 课表效应」索引（由全部学期官方安排一次性构建）。
///
/// 生活史：与 [CalendarMarkIndex] 一样是全量构建、按月查询的纯函数对象，
/// 故课表页可以在 `build` 里直接算（不联网、不异步）。
class CalendarDayEffectIndex {
  /// 角标判定引擎（唯一判假 / 判班的实现）。
  final CalendarMarkIndex marks;

  /// 构建它用的学期列表（「日期 → 教学周」要用学期起止）。
  final List<WxSemesterArrangement> terms;

  CalendarDayEffectIndex._(this.marks, this.terms);

  /// 空索引：任何一天都是普通日、任何一天都查不到教学周。
  factory CalendarDayEffectIndex.empty([CalendarMarkOptions options =
      const CalendarMarkOptions()]) =>
      CalendarDayEffectIndex._(CalendarMarkIndex.empty(options), const []);

  /// 由全部学期官方安排构建。
  factory CalendarDayEffectIndex.build({
    required List<WxSemesterArrangement> terms,
    CalendarMarkOptions options = const CalendarMarkOptions(),
  }) => CalendarDayEffectIndex._(
    CalendarMarkIndex.build(terms: terms, options: options),
    terms,
  );

  /// [day] 当天的课表效应。
  ///
  /// [calendarKind] 为该日在教务校历上的原始标注（可空）：只在官方安排缺席时
  /// 用于「工作日却标 nonday → 放假」的兜底（寒暑假），见 [CalendarMarkIndex.markOf]。
  CalendarDayEffect effectOf(DateTime day, {CalendarDayKind? calendarKind}) {
    final d = DateTime(day.year, day.month, day.day);
    final mark = marks.markOf(d, calendarKind: calendarKind);

    if (mark.isMakeup) {
      final target = parseMakeupTarget(mark.label);
      return CalendarDayEffect(
        day: d,
        kind: CalendarDayEffectKind.makeup,
        name: mark.label.isEmpty ? '补课' : mark.label,
        sourceWeek: target?.week,
        sourceWeekday: target?.weekday,
        events: mark.events,
        reason: mark.reason,
      );
    }
    if (mark.isHoliday) {
      return CalendarDayEffect(
        day: d,
        kind: CalendarDayEffectKind.holiday,
        name: holidayNameOf(mark.label),
        isBreak: isBreakHolidayText(mark.label),
        events: mark.events,
        reason: mark.reason,
      );
    }
    return CalendarDayEffect(
      day: d,
      kind: CalendarDayEffectKind.normal,
      events: mark.events,
      reason: mark.reason,
    );
  }

  /// [day] 所在教学周（第 1 教学周 = 学期起始日所在周，锚点口径见
  /// `teaching_week.dart`）；当天不属于任何已公布学段 → null。
  ///
  /// 与 `resolveTeachingWeek` 的区别：那个只认「此刻」（今天），这个按**任意日期**
  /// 查（课表可以翻到第 4 周看 10-10 的补课）。两者共用同一个锚点算法。
  int? weekOf(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    WxSemesterArrangement? hit;
    for (final t in terms) {
      if (d.isBefore(t.start) || d.isAfter(t.end)) continue;
      // 多个学期命中（旧数据的区间会重叠）时取 start 更晚的，更贴近当下。
      if (hit == null || t.start.isAfter(hit.start)) hit = t;
    }
    if (hit == null) return null;
    return teachingWeekOn(d, termStart: hit.start);
  }
}

/// 第 [weekday] 天的中文名（**1 = 周一 … 7 = 周日**）；越界返回 null。
String? calendarWeekdayName(int weekday) {
  const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  if (weekday < 1 || weekday > names.length) return null;
  return names[weekday - 1];
}

/// 从补课原文里解析「补的是哪一周的星期几」。
///
/// 认得 `补第4周周五的课` / `补第10周周一的课程` / `9月29日补周四的课` /
/// `4月8日补周五的课` / `补周五的课`；认不出返回 null（= 按本日处理）。
///
/// ⚠ 只认「补 …（周次）… 星期」这一种语序：官方原文一律是「补第N周周X的课」，
/// 把 `第N周` 当必需以外的形态放宽只会误伤（如「补（缓）考」）。周次与星期都是
/// **可选**：缺周次 → 同周；缺星期 → 当日。
({int? week, int? weekday})? parseMakeupTarget(String text) {
  final m = RegExp(
    r'补(?:第\s*(?<w>\d{1,2})\s*周)?\s*(?:周|星期|礼拜)\s*(?<d>[一二三四五六日天])',
  ).firstMatch(text);
  if (m == null) return null;
  final w = m.namedGroup('w');
  final d = m.namedGroup('d');
  const map = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7};
  return (week: w == null ? null : int.tryParse(w), weekday: map[d]);
}

/// 假期原文 → 展示名（「国庆节放假」→「国庆节假期」；「寒假开始」→「寒假」）。
///
/// 用于「今天为什么没课」的文案：用户 2026-10-07 要求首页无课时给原因
/// （周末 / 暑假 / 寒假 / 国庆假期…）。认不出的假期原文原样返回（去掉尾注）。
String holidayNameOf(String text) {
  var t = text.split('（').first.split('(').first.trim();
  if (t.contains('寒假')) return '寒假';
  if (t.contains('暑假')) return '暑假';
  t = t
      // 先剥句末标点，再削「放假 / 假期 / 开始」尾巴 —— 顺序反了会得到
      // 「劳动节。假期」（官方原文常带句号，实测踩到）。
      .replaceAll(RegExp(r'[。．.\s]+$'), '')
      .replaceAll('开始', '')
      .replaceAll('放假', '')
      .replaceAll('假期', '')
      .trim();
  if (t.isEmpty || t == '学期外') return '假期';
  return t.endsWith('假') ? t : '$t假期';
}

/// 是否寒 / 暑假（跨度整段的那种）文本。
bool isBreakHolidayText(String text) =>
    text.contains('寒假') || text.contains('暑假');

/// 「今天为什么没课」的文案；[effect] 为 null 且 [isWeekend] 为 false 时返回 null。
///
/// 优先级：**假期名 > 周末 > 其它**（10-03 既是周六又在国庆假期里 → 说「国庆节假期」，
/// 那才是学生真正需要知道的原因）。
String? noClassReasonText({
  CalendarDayEffect? effect,
  required bool isWeekend,
  bool beforeTermStart = false,
}) {
  if (effect != null && effect.isHoliday) {
    return effect.name.isEmpty ? '假期' : effect.name;
  }
  if (effect != null && effect.isMakeup) return null; // 补课日没课 ≠ 假期
  if (isWeekend) return '周末';
  if (beforeTermStart) return '还没开学';
  return null;
}
