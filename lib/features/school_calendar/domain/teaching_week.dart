/// 教学周推算。
///
/// 课表的每个时段都带 `startWeek/endWeek/weekParity`（如 `1-16周(单)`），
/// 要判断「今天该上哪些课」就必须先知道**现在是第几教学周**。
///
/// ## 为什么不用学期起始日直接算
/// 校历的学期 `start` 是**教职工上班日**，不一定是第一教学周。以 261 学期为例：
/// `start = 2026-09-07`，但那一周是**新生军训周**，老生 2026-09-14 才开始上课。
/// 若按 `start` 算，整个学期的课都会错位一周。
///
/// 故这里优先取校历中「本科生开始上课」事件的日期作为第一教学周起点
/// （261 → 2026-09-14；252 → 2026-03-02），取不到时回退到学期 `start`。
///
/// ## 口径已交叉验证
/// 以 2026-09-10 验证：按本规则得**第 0 周**（开学前），而学校数据中台
/// （`dzj.jxufe.edu.cn`）独立返回的 `weekTitle` 同为「2026 第一学期 第0周」。
/// 另 2026-12-31 落在第 16 周，与校历「本科生上课 16 周」吻合。
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

  final firstDay = _firstTeachingDay(term);
  final firstMonday = _mondayOf(firstDay);
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

/// 第一教学周的起始日。
///
/// 规则：取校历中「本科生开始上课」事件的最早日期（排除研究生事件）。
/// 261 学期命中「老生开始上课」2026-09-14（而非「新生开始上课」09-28），
/// 252 学期命中「本科生开始上课。」2026-03-02。
/// 无此类事件（paragraph 旧版校历）时回退到学期 `start`。
DateTime _firstTeachingDay(WxSemesterArrangement term) {
  DateTime? best;
  for (final e in term.events) {
    // ⚠ 分类字段带字间空格（「本 科 生」「研 究 生」），必须先去掉空白再比对，
    // 否则 contains('本科') 恒为 false，全部事件被漏掉 → 退回学期 start → 整学期错位一周。
    final category = e.category?.replaceAll(RegExp(r'\s+'), '');
    if (category != null && !category.contains('本科')) continue;
    if (!e.text.contains('开始上课')) continue;
    if (best == null || e.from.isBefore(best)) best = e.from;
  }
  return best ?? term.start;
}

/// [d] 所在周的周一（当天即为周一时返回当天）。
DateTime _mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
