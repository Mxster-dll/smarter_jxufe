/// 学校时间轴：**学年 / 学期 / 假期** 的唯一出处（2026-09-27 立）。
///
/// ## 用户口径（2026-09-27 请求）
/// 「我们希望可以独立出来被所有模块复用，学年的时间范围就定为该学年第一学期
/// 第一天到下学年第一天前一天；假期时间也可以从校历页查，
/// https://jwxt.jxufe.edu.cn/public/SchoolCalendar.jsp」
///
/// - **学年** `[第一学期第一天, 下学年第一学期第一天 - 1 天]`
/// - **下学年第一天取不到 → 该学年结束日留 null**（校历只公布到当前学年为止）
/// - **假期以教务校历页为准**
///
/// ## 数据来源（实测 2026-09-27，`tools/_school_calendar_dates.py` 同口径）
/// `jwxt.jxufe.edu.cn/public/SchoolCalendar.show.jsp`（免登录）每个学段一张页，
/// 右侧 `<textarea name="bz">` 备注就是**结构化日期**（已由
/// `SchoolCalendarHtmlParser` 收进 [SchoolCalendar.notes]）：
///
/// ```text
/// 学期开始日期：2026-09-07
/// 学期结束日期：2027-01-15
/// 假期开始日期：2027-01-16
/// 假期结束日期：2027-01-19
/// ```
///
/// ⚠ 该页**没有法定节假日**（逐日只有 `workday|nonday`，国庆整段标 workday），
/// 只有两个学期之间的**寒 / 暑假**；法定节假日仍由小程序校历源
/// （`wxcal_semester.dart` 的 `WxCalEvent`）负责，见 `calendar_day_mark.dart`。
///
/// ### 实测台账（已公布学年完全自洽，占位值一眼可辨）
/// | 学年 | 第一学段 | 寒假（派生） | 第二学段 | 暑期段 | 暑假（派生） | 下学年首日 |
/// |---|---|---|---|---|---|---|
/// | 2023 | 09-04~2024-01-19 | 01-20~02-25（37 天） | 02-26~07-03 | 07-04~07-10 | 07-11~09-01（53 天） | 2024-09-02 |
/// | 2024 | 09-02~2025-01-10 | 01-11~02-16（37 天） | 02-17~06-29 | 06-30~07-04 | 07-05~08-31（58 天） | 2025-09-01 |
/// | 2025 | 09-01~2026-01-15 | 01-16~03-01（45 天） | 03-02~07-05 | 07-06~07-10 | 07-11~09-06（58 天） | 2026-09-07 |
/// | 2026 | 09-07~2027-01-15 | 01-16~01-19 ← **占位** | 2027-01-20 ← 占位 | 07-06~07-31 | 08-01~? ← 下学年未公布 | **未公布** |
///
/// - `xn = 2027 / 2028` 的页面是 **723 字节空壳**（备注为空、无月份表）→ 未公布。
/// - 未公布时教务页把下一学段「学期开始日期」接在上一段「假期结束日期」后
///   串成占位值（2026 学年因此出现 4 天寒假）→ 由 [schoolMinWinterBreakDays] /
///   [schoolMinSummerBreakDays] 判为不可信：**结束日留 null，不猜**。
/// - 已公布学年的 `假期结束日期` 恒等于「下一学段学期开始日期 − 1 天」
///   （2024 学年 08-31 ↔ 2025 学年 09-01 等三处实测）→ 故本层**一律按
///   「下一段起点 − 1 天」派生**，页面那个字段只作 [SchoolTermDates.breakEnd] 存档。
library;

import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart'
    show SchoolCalendar, xnDisplayName;
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart'
    show schoolTermCode, schoolTermFromCode, schoolTermLabel;

/// 寒假可信下限（天）：小于它视为「下一学段未公布」的占位值。
const int schoolMinWinterBreakDays = 14;

/// 暑假可信下限（天）。
const int schoolMinSummerBreakDays = 21;

/// 一个学段（学年 + 学段）的官方日期，来自教务校历页备注。
class SchoolTermDates {
  const SchoolTermDates({
    required this.xn,
    required this.xq,
    this.termStart,
    this.termEnd,
    this.breakStart,
    this.breakEnd,
  });

  /// 学年起始年（2026 → 2026-2027 学年）。
  final int xn;

  /// 学段：0 第一学期 / 1 第二学期 / 2 第二阶段（暑期）。
  final int xq;

  /// 「学期开始日期」= 该学段第一天；页面为空壳时为 null。
  final DateTime? termStart;

  /// 「学期结束日期」。
  final DateTime? termEnd;

  /// 「假期开始日期」（第一学段 = 寒假、第二阶段 = 暑假）。
  final DateTime? breakStart;

  /// 「假期结束日期」（原样存档；派生见 [schoolBreaksOfYear]）。
  final DateTime? breakEnd;

  /// 该学段是否已公布（有学期开始日期）。
  bool get isPublished => termStart != null;

  /// 学期天数（起止缺一 → null）。
  int? get termDays => (termStart == null || termEnd == null)
      ? null
      : termEnd!.difference(termStart!).inDays + 1;

  /// 展示名，如 `2026-2027 学年第一学期`。
  String get label => schoolTermLabel(xn, xq);

  SchoolTermDates copyWith({
    DateTime? termStart,
    DateTime? termEnd,
    DateTime? breakStart,
    DateTime? breakEnd,
  }) =>
      SchoolTermDates(
        xn: xn,
        xq: xq,
        termStart: termStart ?? this.termStart,
        termEnd: termEnd ?? this.termEnd,
        breakStart: breakStart ?? this.breakStart,
        breakEnd: breakEnd ?? this.breakEnd,
      );

  @override
  String toString() => 'SchoolTermDates($label: $termStart~$termEnd, '
      '假期 $breakStart~$breakEnd)';
}

/// 备注行：`学期开始日期：2026-09-07`（全/半角冒号、前后空白都容错）。
final RegExp _dateNoteRe = RegExp(
  r'^(学期|假期)(开始|结束)日期\s*[：:]\s*(\d{4})-(\d{1,2})-(\d{1,2})',
);

/// 从教务校历页备注行解析一个学段的日期。
///
/// 认不出的行忽略；四行全缺 → 返回的 [SchoolTermDates.isPublished] 为 false。
SchoolTermDates schoolTermDatesFromNotes(
  Iterable<String> notes, {
  required int xn,
  required int xq,
}) {
  DateTime? termStart;
  DateTime? termEnd;
  DateTime? breakStart;
  DateTime? breakEnd;
  for (final raw in notes) {
    final m = _dateNoteRe.firstMatch(raw.trim());
    if (m == null) continue;
    final date = DateTime(
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
    );
    final isTerm = m.group(1) == '学期';
    final isStart = m.group(2) == '开始';
    if (isTerm) {
      if (isStart) {
        termStart = date;
      } else {
        termEnd = date;
      }
    } else {
      if (isStart) {
        breakStart = date;
      } else {
        breakEnd = date;
      }
    }
  }
  return SchoolTermDates(
    xn: xn,
    xq: xq,
    termStart: termStart,
    termEnd: termEnd,
    breakStart: breakStart,
    breakEnd: breakEnd,
  );
}

/// 从一个学段的校历页取日期（`SchoolCalendar.notes` 已是备注行）。
SchoolTermDates schoolTermDatesOf(SchoolCalendar calendar) =>
    schoolTermDatesFromNotes(calendar.notes, xn: calendar.xn, xq: calendar.xq);

/// **学年**：`[第一学期第一天, 下学年第一学期第一天 - 1 天]`。
class SchoolYear {
  const SchoolYear({required this.xn, this.firstDay, this.lastDay});

  /// 学年起始年（2026 → 2026-2027 学年）。
  final int xn;

  /// 该学年第一学期第一天（教务校历「学期开始日期」）；未公布 → null。
  final DateTime? firstDay;

  /// 下学年第一学期第一天 − 1 天；下学年未公布 → null（**不猜**）。
  final DateTime? lastDay;

  /// 起止都已知。
  bool get isComplete => firstDay != null && lastDay != null;

  /// 是否已知起始（[contains] 可用）。
  bool get isKnown => firstDay != null;

  /// [day] 是否属于本学年。
  ///
  /// - [firstDay] 未知 → false（无法判定）；
  /// - [lastDay] 未知（本学年尚未结束 / 下学年未公布）→ **开区间**：
  ///   只要不早于 [firstDay] 就算本学年。
  bool contains(DateTime day) {
    final first = firstDay;
    if (first == null) return false;
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(first)) return false;
    final last = lastDay;
    return last == null || !d.isAfter(last);
  }

  /// 展示名，如 `2026-2027学年`。
  String get label => xnDisplayName(xn);

  /// 区间文本，如 `2026-09-07 ~ 2027-09-06`；缺失侧如实写未知。
  String get rangeText {
    final first = firstDay;
    if (first == null) return '$label（校历未公布）';
    final last = lastDay;
    if (last == null) return '${_ymd(first)} 起（下学年校历未公布）';
    return '${_ymd(first)} ~ ${_ymd(last)}';
  }

  @override
  String toString() => 'SchoolYear($label: $rangeText)';
}

/// 由「本学年第一学段 + 下学年第一学段」拼一个学年。
///
/// [nextFirst] 缺（或未公布）→ [SchoolYear.lastDay] 为 null。
SchoolYear schoolYearOf({
  required int xn,
  SchoolTermDates? first,
  SchoolTermDates? nextFirst,
}) =>
    SchoolYear(
      xn: xn,
      firstDay: first?.termStart,
      lastDay: _minusDay(nextFirst?.termStart),
    );

/// **固定口径兜底**：`[xn]-09-01 ~ [xn+1]-08-31`（含首尾两天）。
///
/// 校历已公布的学年请用 [schoolYearOf] / [SchoolTimeTable.yearOf] —— 真实学年末 =
/// **下学年第一学期第一天 − 1 天**（实测 2025 学年到 `2026-09-06`，比 08-31 多 6 天）。
/// 本函数只服务两种场景：
/// ① 校历取不到（离线 / 该学年未收录）时当兜底 —— 见 [schoolYearOrFallback]；
/// ② 调用方是**纯函数**、拿不到 [SchoolTimeTable] 的历史口径（综测测评学年窗口）。
///
/// ⚠ 它是这条日期算法的**唯一实现**（2026-09-27 从 zongce / 志愿时长两处收上来的），
/// 但语义上只该当兜底 —— 新代码优先传校历。
SchoolYear schoolYearFallback(int xn) => SchoolYear(
  xn: xn,
  firstDay: DateTime(xn, 9, 1),
  lastDay: DateTime(xn + 1, 8, 31),
);

/// 有校历就用校历、没有就用 [schoolYearFallback]。
///
/// [table] 为 null（离线 / 未取数）或该学年未收录（未公布）→ 退回固定口径：
/// 宁可显示一个略粗的窗口，也不要因为校历没到就让整块内容显示「—」。
SchoolYear schoolYearOrFallback(SchoolTimeTable? table, int xn) {
  final year = table?.yearOf(xn);
  return year != null && year.isKnown ? year : schoolYearFallback(xn);
}

/// [day] 所属**学年**的起始年：9 月 1 日为界（2026-09-07 → 2026；2026-03-01 → 2025）。
///
/// 这是「日期 → 学年」的**唯一算术出处**（2026-09-27 从综测的 `zcDefaultYear`
/// 收上来）。⚠ 它不认识校历：界线恒取 09-01，而真实学年首日可能是 09-07
/// （见台账）—— 需要精确时用 [SchoolTimeTable.yearContaining]。
int schoolYearStartOf(DateTime day) =>
    day.month >= 9 ? day.year : day.year - 1;

/// 假期种类。
enum SchoolBreakKind {
  /// 寒假（第一学段与第二学段之间）。
  winter,

  /// 暑假（第二阶段与下学年之间）。
  summer,
}

/// 一个假期窗口。`end` 为 null = 结束日未知（下一学段未公布 / 跨度不合理）。
class SchoolBreak {
  const SchoolBreak({
    required this.kind,
    required this.start,
    this.end,
    this.certain = true,
  });

  final SchoolBreakKind kind;

  /// 第一天（教务校历「假期开始日期」）。
  final DateTime start;

  /// 最后一天；未知 → null。
  final DateTime? end;

  /// 结束日是否可信（false = 判为占位值，[end] 已被置空）。
  final bool certain;

  /// 展示名：寒假 / 暑假。
  String get label =>
      kind == SchoolBreakKind.winter ? '寒假' : '暑假';

  /// 天数（[end] 未知 → null）。
  int? get days =>
      end == null ? null : end!.difference(start).inDays + 1;

  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(start)) return false;
    final e = end;
    return e == null || !d.isAfter(e);
  }

  @override
  String toString() => 'SchoolBreak($label: $start~$end${certain ? '' : ' 未定'})';
}

/// 一个学年的寒 / 暑假。
///
/// - 寒假 = `[第一学段假期开始, 第二学段学期开始 − 1 天]`
/// - 暑假 = `[第二阶段假期开始, 下学年第一学段学期开始 − 1 天]`
///
/// 结束侧一律**派生**（页面那个 `假期结束日期` 就是它算出来的），跨度小于
/// [schoolMinWinterBreakDays] / [schoolMinSummerBreakDays] 时判为占位 →
/// 该假期 `end = null, certain = false`。
List<SchoolBreak> schoolBreaksOfYear({
  required int xn,
  SchoolTermDates? first,
  SchoolTermDates? second,
  SchoolTermDates? summer,
  SchoolTermDates? nextFirst,
}) {
  final out = <SchoolBreak>[];

  final winterStart = first?.breakStart ?? _plusDay(first?.termEnd);
  if (winterStart != null) {
    out.add(
      _breakOf(
        SchoolBreakKind.winter,
        winterStart,
        _minusDay(second?.termStart),
        schoolMinWinterBreakDays,
      ),
    );
  }

  final summerStart = summer?.breakStart ?? _plusDay(summer?.termEnd);
  if (summerStart != null) {
    out.add(
      _breakOf(
        SchoolBreakKind.summer,
        summerStart,
        _minusDay(nextFirst?.termStart),
        schoolMinSummerBreakDays,
      ),
    );
  }

  return out;
}

SchoolBreak _breakOf(
  SchoolBreakKind kind,
  DateTime start,
  DateTime? end,
  int minDays,
) {
  if (end == null) {
    return SchoolBreak(kind: kind, start: start, certain: false);
  }
  final days = end.difference(start).inDays + 1;
  if (days < minDays) {
    return SchoolBreak(kind: kind, start: start, certain: false);
  }
  return SchoolBreak(kind: kind, start: start, end: end);
}

/// 一张「学校时间表」：若干学段的官方日期，回答学年 / 假期 / 归属问题。
///
/// 这是给**其它模块**用的唯一入口（构建一次、随处查询）：
/// ```dart
/// final table = SchoolTimeTable.fromCalendars(calendars);
/// final year = table.yearOf(2026);          // 2026-09-07 起，结束日 null
/// final breaks = table.breaksOf(2025);      // 寒假 + 暑假
/// final owner = table.yearContaining(now);  // 今天属于哪个学年
/// ```
class SchoolTimeTable {
  const SchoolTimeTable(this.terms);

  /// 全部已知学段（顺序无关，按下标查找）。
  final List<SchoolTermDates> terms;

  static const SchoolTimeTable empty = SchoolTimeTable(<SchoolTermDates>[]);

  /// 由若干校历页（`schoolCalendarProvider` 的结果）构建。
  factory SchoolTimeTable.fromCalendars(Iterable<SchoolCalendar> calendars) =>
      SchoolTimeTable([for (final c in calendars) schoolTermDatesOf(c)]);

  /// 取某个学段（未收录 → null）。
  SchoolTermDates? termAt(int xn, int xq) {
    for (final t in terms) {
      if (t.xn == xn && t.xq == xq) return t;
    }
    return null;
  }

  /// 取学年（结束日取「下学年第一学段 − 1 天」，缺则 null）。
  SchoolYear yearOf(int xn) => schoolYearOf(
        xn: xn,
        first: termAt(xn, 0),
        nextFirst: termAt(xn + 1, 0),
      );

  /// 取一个学年的寒 / 暑假。
  List<SchoolBreak> breaksOf(int xn) => schoolBreaksOfYear(
        xn: xn,
        first: termAt(xn, 0),
        second: termAt(xn, 1),
        summer: termAt(xn, 2),
        nextFirst: termAt(xn + 1, 0),
      );

  /// [day] 落在哪个学年（表覆盖范围内）；覆盖不到 → null。
  ///
  /// 候选含「已收录学年 + 1」，这样最后一个学年的末尾（如 2026-09-08 起）
  /// 也能归到下一个学年 —— 但那需要下下个学年的第一学段，故只有该学段
  /// 也在表里才给得出。
  SchoolYear? yearContaining(DateTime day) {
    final starts = <int>{for (final t in terms) t.xn, for (final t in terms) t.xn + 1};
    final sorted = starts.toList()..sort();
    for (final xn in sorted) {
      final year = yearOf(xn);
      if (year.isKnown && year.contains(day)) return year;
    }
    return null;
  }

  @override
  String toString() => 'SchoolTimeTable(${terms.length} 个学段)';
}

// ─── 学期标识归一（跨模块唯一换算）────────────────────────────────────
//
// 两处历史重复实现被本文件取代：
// - `lib/features/zongce/domain/zc_year_sources.dart` 的 `zcSemesterStartYear`
// - `lib/features/ims/grades/domain/semester.dart` 的 `Semester.parse`

/// 短码 `yyy`（如 `261` → 2026-2027 学年第一学期）。
///
/// ⚠ 必须头尾锚定：不锚定的话纯年份 `2025` 会被切成 `20`+`2`。
final RegExp _shortTermRe = RegExp(r'^(\d{2})([1-3])$');

/// 完整学期名：`2025-2026学年第一学期` / `2025-2026 学年第2学期`。
///
/// 不像短码那样锚定：调用方常把「学年学期：」之后整段截下来，可能带尾巴。
final RegExp _fullTermRe =
    RegExp(r'(\d{4})\s*-\s*\d{4}\s*学年\s*第?\s*([一二三123])\s*学期');

/// 中文数字 → 学段号（1/2/3）。
const Map<String, int> _cnTermNumbers = {'一': 1, '二': 2, '三': 3};

/// 只写了学年、没写学期号：`2025-2026学年`。
final RegExp _yearOnlyRe = RegExp(r'(\d{4})\s*-\s*\d{4}\s*学年');

/// 学期标识 → **学年起始年**；认不出（空串 / 其它格式）→ null。
///
/// 接受三种写法：短码 `'251'`（成绩数据的学期字段）、完整学期名
/// `'2025-2026学年第一学期'`、只到学年的 `'2025-2026学年'`。
/// ⚠ **认不出时必须返回 null**，调用方按「不属于任何学年」处理 ——
/// 不要兜成默认年份，否则会把别学年的课算进来。
int? schoolYearOfTermText(String raw) {
  final term = schoolTermOfText(raw);
  if (term != null) return term.xn;
  final only = _yearOnlyRe.firstMatch(raw.trim());
  if (only != null) return int.parse(only.group(1)!);
  return null;
}

/// 学期标识 → `(xn, xq)`；含学期号才给得出，只认得出学年时返回 null。
({int xn, int xq})? schoolTermOfText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final short = _shortTermRe.firstMatch(text);
  if (short != null) {
    return (xn: 2000 + int.parse(short.group(1)!), xq: int.parse(short.group(2)!) - 1);
  }

  final full = _fullTermRe.firstMatch(text);
  if (full == null) return null;
  final rawTerm = full.group(2)!;
  final number = int.tryParse(rawTerm) ?? _cnTermNumbers[rawTerm];
  if (number == null || number < 1 || number > 3) return null;
  return (xn: int.parse(full.group(1)!), xq: number - 1);
}

/// 学期短码（`261`）—— 转发 [schoolTermCode]，供只认文本的调用方。
String schoolTermCodeOfText(String raw) {
  final term = schoolTermOfText(raw);
  if (term == null) return '';
  return schoolTermCode(term.xn, term.xq);
}

/// 学期全名（**教务原文格式，无空格**）：`2025-2026学年第一学期`。
///
/// 与 [schoolTermLabel]（`2025-2026 学年第一学期`，界面用、带空格）刻意分开：
/// 成绩页 / AI 文案里的教务原文是这一份，混用会改到既有文案。
String schoolTermFullName(int xn, int xq) =>
    '$xn-${xn + 1}学年第${_cnTermName(xq)}学期';

/// 学期短码 → 全名；认不出（含只给得出学年的）→ 空串。
String schoolTermTextOfCode(String code) {
  final term = schoolTermOfCode(code);
  if (term == null) return '';
  return schoolTermFullName(term.xn, term.xq);
}

/// 学段 → 中文序数（与 [xqDisplayName] 同口径：0 一 / 1 二 / 2 三）。
String _cnTermName(int xq) => switch (xq) {
  0 => '一',
  1 => '二',
  2 => '三',
  _ => '${xq + 1}',
};

/// 短码 → `(xn, xq)`（转发 [schoolTermFromCode]，语义与之一致）。
({int xn, int xq})? schoolTermOfCode(String code) => schoolTermFromCode(code);

// ─── 私有工具 ──────────────────────────────────────────────────────

DateTime? _plusDay(DateTime? day) => day?.add(const Duration(days: 1));

DateTime? _minusDay(DateTime? day) => day?.subtract(const Duration(days: 1));

String _ymd(DateTime d) => schoolDayText(d);

/// `yyyy-MM-dd`（学校时间里所有日期文本的唯一格式，界面别再自己拼）。
String schoolDayText(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
