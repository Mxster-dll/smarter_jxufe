/// 校历页「学年时间线」的数据口径 —— **一根单轴**上要放的段与标记（纯函数）。
///
/// 用户 2026-10-09 裁定（在否掉两版「一行一段」的卡片之后）：「直接用 fluent-design
/// 设计一根单轴时间线」——即：**一条轴 = 一个学年**，各学段 / 假期是轴上的实心段，
/// 而不是每段各占一行。于是「段」这个概念从展示层收上来，成为可单测的纯数据：
///
/// - 轴范围 = [SchoolYear]（[schoolYearOrFallback] 兜底：拿不到校历用 09-01~08-31）；
/// - 段顺序 = 时间顺序（第一学期 → 寒假 → 第二学期 → 第二阶段 → 暑假），与教务页一致；
/// - **结束日未知的段照画**（`end == null`）：起点是已知的，展示层画成虚线尾
///   ——「待公布」是**段的一种状态**，不是「没有这一段」；
/// - **整段没公布（连起点都没有）的学段不画**（如 2026 学年第二学期）：编不出位置；
/// - 假期结束日沿用 [schoolBreaksOfYear] 的派生与占位识别（跨度短于下限 → end 置空）。
library;

import 'package:smarter_jxufe/features/school_calendar/domain/school_calendar.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_time.dart';

/// 段的两态：在校（学期 / 第二阶段）与放假（寒 / 暑假）。配色与单位都由它决定。
enum SchoolTimelineKind {
  /// 在校：学期与第二阶段。
  term,

  /// 放假：寒假 / 暑假。
  holiday,
}

/// 一根轴上的一个段。
class SchoolTimelineSegment {
  const SchoolTimelineSegment({
    required this.name,
    required this.start,
    required this.end,
    required this.kind,
    this.note,
  });

  /// 段名：`第一学期` / `寒假` / `第二阶段` / `暑假`（走 [xqDisplayName] 与假期标签）。
  final String name;

  /// 起始日（已公布）。
  final DateTime start;

  /// 结束日；**null = 待公布**（教务未公布下一学段，结束日派生不出来）。
  final DateTime? end;

  final SchoolTimelineKind kind;

  /// 待公布时的短说明（`待公布` / `下学年未公布`），已公布时为 null。
  final String? note;

  bool get isOpen => end == null;

  /// 含首含尾的天数（与教务文案同口径：`01-16 ~ 03-01` = 45 天）。
  int? get days =>
      end == null ? null : end!.difference(start).inDays + 1;

  /// 起止文案：`09-07 ~ 01-15` / `01-16 起`（年份由轴头交代，段里不重复）。
  String get rangeText =>
      end == null ? '${_md(start)} 起' : '${_md(start)} ~ ${_md(end!)}';

  @override
  String toString() =>
      'SchoolTimelineSegment($name: $rangeText${note == null ? '' : ' · $note'})';
}

String _md(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 一个学年要问的三个学段（0 第一学期 / 1 第二学期 / 2 第二阶段）。
///
/// ⚠ 唯一定义在这里（原先在 `data/providers/school_time_providers.dart`，2026-10-09
/// 收上来到 domain —— 展示层与取数层都要用它，放 data 会让 domain 反向依赖）。
const List<int> schoolYearTermSegments = [0, 1, 2];

/// 把 [table] 里 [xn] 学年的段摊成一根轴上的顺序列表。
///
/// 只返回**位置可信**的段：
/// - 学期要有 [SchoolTermDates.termStart]（空壳页 → 整段不画，编不出位置）；
/// - ⚠ **占位链**：教务在未公布学段会「自洽地」编日期（§36.2）——判据 = 该学段
///   **起点之前最近的那段假期**是否被判为占位（`certain == false`，如 2026 学年
///   寒假只给 4 天）。一段不可信 → 它**后面**的整条链也不可信（寒假是编的，
///   紧接着的「第二学期 01-20 起」自然也是编的），于是从那里起一律不画 ——
///   时间线上长度是视觉编码，画一段假的 7 个月比少画一段糟得多；
/// - 假期要有起点（教务的「假期开始日期」或上一段的学期末 + 1 天）；
///   结束日未知（占位识别后置空）→ `end == null`，展示层画成虚线。
List<SchoolTimelineSegment> schoolTimelineSegments(
  SchoolTimeTable table,
  int xn,
) {
  final out = <SchoolTimelineSegment>[];
  final breaks = table.breaksOf(xn);
  var chainUsable = true;

  for (final xq in schoolYearTermSegments) {
    final term = table.termAt(xn, xq);
    final start = term?.termStart;
    // 起点之前最近的一段假期（寒假在第二学期之前、暑假在下一学年之前）
    SchoolBreak? before;
    if (start != null) {
      for (final b in breaks) {
        if (b.start.isBefore(start)) before = b;
      }
    }
    if (start == null || !chainUsable || (before != null && !before.certain)) {
      chainUsable = false; // 从这一段起后面都不可信
      continue;
    }
    out.add(
      SchoolTimelineSegment(
        name: xqDisplayName(xq),
        start: start,
        end: term!.termEnd,
        kind: SchoolTimelineKind.term,
        note: term.termEnd == null ? '结束日待公布' : null,
      ),
    );
  }

  for (final b in breaks) {
    out.add(
      SchoolTimelineSegment(
        name: b.label,
        start: b.start,
        end: b.end,
        kind: SchoolTimelineKind.holiday,
        note: b.end == null ? '待公布' : null,
      ),
    );
  }

  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// 轴的投影：把「日期 → 0..1 的轴位置」这件事收在一处（展示层只做像素换算）。
///
/// [start] / [end] 是轴的两端（含）；轴外的日期夹到端头。
class SchoolTimelineAxis {
  const SchoolTimelineAxis({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  int get totalDays => end.difference(start).inDays;

  /// [day] 在轴上的位置（0 = 轴首，1 = 轴尾）；越界夹取。
  double fractionOf(DateTime day) {
    final total = totalDays;
    if (total <= 0) return 0;
    final f = day.difference(start).inDays / total;
    return f.clamp(0.0, 1.0);
  }

  /// 段的 `(起, 止)` 位置；`止 == null`（待公布）→ 轴尾。
  (double, double) spanOf(SchoolTimelineSegment s) =>
      (fractionOf(s.start), fractionOf(s.end ?? end));

  @override
  String toString() => 'SchoolTimelineAxis($start ~ $end, $totalDays 天)';
}

/// 学年的轴：**用真实年月**（[SchoolYear.firstDay] ~ [SchoolYear.lastDay]），
/// 结束日未公布时退回固定窗口 —— 轴必须两端都有日期才画得出来。
SchoolTimelineAxis schoolTimelineAxis(SchoolTimeTable? table, int xn) {
  final year = schoolYearOrFallback(table, xn);
  return SchoolTimelineAxis(
    start: year.firstDay ?? DateTime(xn, 9, 1),
    end: year.lastDay ?? DateTime(xn + 1, 8, 31),
  );
}
