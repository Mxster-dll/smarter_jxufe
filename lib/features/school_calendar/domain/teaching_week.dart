/// 教学周推算。
///
/// 课表的每个时段都带 `startWeek/endWeek/weekParity`（如 `1-16周(单)`），
/// 要判断「今天该上哪些课」就必须先知道**现在是第几教学周**。
///
/// ## 第 1 教学周 = 学期起始日所在那一周（教务校历的「周次」口径）
/// 教务校历（`SchoolCalendar.show.jsp`）本身就是按周排的月历表，**行首即教学周次**
/// （见 `domain/school_calendar.dart` 的 `CalendarWeekRow.weekNo`），其第 1 周正是
/// 学期 `start` 所在周：261 → 09-07~09-13，252 → 03-02~03-08，251 → 09-01~09-07。
/// 课表的周次标签与校历出自同一个教务系统，故必须用同一个锚点，否则整学期错位。
///
/// ## ⚠ 历史 bug（2026-09-14 修正，勿改回去）
/// 旧实现取校历里**最早一条本科生「开始上课」事件**当第 1 周：261 命中
/// 「老生开始上课」2026-09-14 → 判 09-14 为第 1 教学周 → **整学期错位一周**，
/// 表现为开学当天课表页显示「第 1 周」且一片空白（该生所有课程都从第 2 周起）。
/// 「开始上课」是**学生第一次上课的日子**，不等于第 1 教学周 —— 261 的第 1 周是
/// 新生军训 / 老生报到周，老生从第 2 周（09-14）才开课。
///
/// 三条自洽佐证（真实数据，可复核）：
/// - 校历周次表：第 1 周 09-07~09-13、第 2 周 09-14~09-20、第 17 周 12-28~2027-01-03；
/// - 校历写「2026-10-10 补第4周周五的课」→ 第 4 周周五 = 10-02，正在国庆假（10-01~10-07）内 ✅
///   （若按 09-14 为第 1 周，第 4 周周五是 10-09，并非假日，补课无从谈起）；
/// - 课表课程的周次是 `2-17 周`（老生 09-14 开课 = 第 2 周）↔ 校历「学生课程结束 12-31」
///   = 第 17 周周四 ✅（若按旧锚点，课程要上到 2027-01-10，已过期末复习 01-04）。
///
/// 守卫测试：`test/school_term_test.dart` 的「校历周次 ↔ 教学周推算」用真实 fixture
/// `test/fixtures/_cal_261_xq0.html` 逐行核对，改锚点必炸。
library;

import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 当前所处的教学周。
class TeachingWeek {
  /// 教学周次。0 表示开学前（尚未到第一教学周）。
  final int week;

  /// 第 1 教学周的周一。
  final DateTime firstMonday;

  /// 当前所在周的周一。
  final DateTime weekMonday;

  /// 命中的学期安排。
  final WxSemesterArrangement term;

  const TeachingWeek({
    required this.week,
    required this.firstMonday,
    required this.weekMonday,
    required this.term,
  });

  /// 是否处于开学前（第 0 周）。
  bool get isBeforeTerm => week < 1;

  /// 展示文本，如「第 9 教学周」；第 0 周显示「开学前」。
  String get label => isBeforeTerm ? '开学前' : '第 $week 教学周';

  bool get isOdd => week.isOdd;

  bool get isEven => week.isEven;

  /// 本教学周是否落在 `[startWeek, endWeek]` 区间内。
  bool includesWeek(int startWeek, int endWeek) =>
      week >= startWeek && week <= endWeek;

  @override
  String toString() => 'TeachingWeek($label, firstMonday=$firstMonday)';
}

/// 由 [now] 定位所在学期与教学周。
///
/// [terms] 为校历学期列表（通常传 `wxcalOfflineToDomain()` 的结果或实时校历）。
/// 找不到任何可用学期时返回 null。
TeachingWeek? resolveTeachingWeek(
  DateTime now, {
  required List<WxSemesterArrangement> terms,
}) {
  if (terms.isEmpty) return null;

  final day = DateTime(now.year, now.month, now.day);
  final term = _pickTerm(day, terms);
  if (term == null) return null;

  final firstMonday = _firstTeachingMonday(term);
  final rawWeek = (day.difference(firstMonday).inDays / 7).floor() + 1;

  return TeachingWeek(
    week: rawWeek < 0 ? 0 : rawWeek,
    firstMonday: firstMonday,
    weekMonday: _mondayOf(day),
    term: term,
  );
}

/// 选中 [day] 所属学期。
///
/// 优先取日期区间覆盖 [day] 的学期；否则取 `start` 不晚于 [day] 中最近的一个
/// （学期刚结束、数据未及时更新时仍能给出合理周次）；再否则取最早的一个。
WxSemesterArrangement? _pickTerm(
  DateTime day,
  List<WxSemesterArrangement> terms,
) {
  WxSemesterArrangement? exact;
  WxSemesterArrangement? lastPast;
  WxSemesterArrangement? earliest;

  for (final t in terms) {
    if (earliest == null || t.start.isBefore(earliest.start)) earliest = t;
    if (!t.start.isAfter(day) && !t.end.isBefore(day)) {
      // 区间命中；多个命中时取 start 更晚的（更贴近当下）
      if (exact == null || t.start.isAfter(exact.start)) exact = t;
    }
    if (!t.start.isAfter(day)) {
      if (lastPast == null || t.start.isAfter(lastPast.start)) lastPast = t;
    }
  }

  return exact ?? lastPast ?? earliest;
}

/// 第 1 教学周的周一 = 学期 `start` 所在周的周一。
///
/// 教务校历的「周次」列以学期起始周为第 1 周（261 → 2026-09-07，252 → 2026-03-02，
/// 251 → 2025-09-01），证据与历史 bug 见文件头。
/// **不要**再用「本科生开始上课」事件当锚点：那是学生第一次上课的日子，
/// 261 的老生开课日 09-14 属于**第 2 周**。
///
/// 注：2018 年及更早的学期 `start` 有的是报到日（周六/周日），此时取所在周的周一；
/// 这些历史学期不参与「当前教学周」（调用方都有学期匹配守卫），故无影响。
DateTime _firstTeachingMonday(WxSemesterArrangement term) =>
    _mondayOf(term.start);

/// [d] 所在周的周一（当天即为周一时返回当天）。
DateTime _mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
