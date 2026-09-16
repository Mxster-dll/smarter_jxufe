/// 公共查询报表（`/kbbp/dykb.GS1.jsp?kblx=…` 返回的 GBK HTML）的纯解析器。
///
/// 报表结构（实测四种课表完全一致）：
///
/// ```text
/// <div group="group" …>                     ← 描述块：若干 <div style="float:left…">标签：值</div>
///   <div style="float:left;width:27%;…">院(系)/部：会计学院</div>
///   <div style="float:left;width:33%;…">班级：26会计学S1班[80]</div>
/// </div>
/// <!-- 报表区 -->
/// <table class='table' id='mytable0' …>      ← 网格：一个 mytableN = 一个对象（班/教师/教室/课程）
///   <thead>…<td class='td0'>星期一</td>…</thead>
///   <tbody>
///     <tr>
///       <td class='td1' rowspan='2'><b>上<br>午</b></td>   ← 半日块（可选）
///       <td class='td1'><b>1-2节</b></td>                  ← 大节行标签
///       <td class='td' title="…"><div class='div1' id='011'>…</div></td>  ← 格子
/// ```
///
/// 关键约定（改动前先读）：
/// - 格子 `div1` 的 id = `<表序号><星期><大节序号>`（表序号 ≥10 时为两位，如 `1011`），
///   所以**星期与大节从 id 反推**，不靠行列计数（合并单元格会让列号错位）。
/// - 大节 → 实际节次用**行标签**（`1-2节` / `3-5节` / `10-12节`）还原，别硬编码 2 节一档。
/// - 教室课表一次返回**整栋楼**的对象，一个响应里有几十上百个 `mytableN`。
library;

import '../../schedule/domain/class_time.dart';
import 'free_time.dart';

/// 一个格子的内容片段（用 `&ensp;` 切开后的原文）。
class PublicTimetableCell {
  /// 星期，1 = 周一 … 7 = 周日。
  final int weekday;

  /// 大节序号（1 起，来自 `div1` id）。
  final int periodIndex;

  /// 该大节对应的实际节次区间（来自行标签，如 `1-2节` → 1..2）。
  final int startPeriod;
  final int endPeriod;

  /// 格子原文（实体已还原、首尾空白已去）。
  final String text;

  /// `&ensp;` 切开后的片段（课程名 / 学分 / 教师 / `[2-17]周` / `1-2节` / 教室 / 校区）。
  final List<String> parts;

  /// 生效周次（解析不到时 [startWeek]=1、[endWeek]=30）。
  final int startWeek;
  final int endWeek;

  /// 单双周。
  final WeekParity parity;

  const PublicTimetableCell({
    required this.weekday,
    required this.periodIndex,
    required this.startPeriod,
    required this.endPeriod,
    required this.text,
    required this.parts,
    this.startWeek = 1,
    this.endWeek = 30,
    this.parity = WeekParity.every,
  });

  /// 所在星期名（`周一`）。
  String get weekdayLabel => weekday >= 1 && weekday <= 7
      ? ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1]
      : '周?';

  /// `周三 3-4 节`。
  String get slotLabel => startPeriod == endPeriod
      ? '$weekdayLabel $startPeriod 节'
      : '$weekdayLabel $startPeriod-$endPeriod 节';

  /// 周次描述：`2-17周` / `2-17周(单)`。
  String get weekLabel {
    final base = '$startWeek-$endWeek周';
    return parity == WeekParity.every ? base : '$base(${parity.displayName})';
  }

  @override
  String toString() => 'PublicTimetableCell($slotLabel $weekLabel, $text)';
}

/// 一个对象的课表（班级 / 教师 / 教室 / 课程各一张）。
class PublicTimetable {
  /// 描述块字段（顺序保留），如 `[(label: 班级, value: 26会计学S1班[80]), …]`。
  final List<({String label, String value})> fields;

  /// 对象名（班级名 / 教师名 / 教室名 / 课程名）。
  final String owner;

  /// 非空格子。
  final List<PublicTimetableCell> cells;

  /// 表尾 `备注N[星期第X大节]：…` / `注N：…` 文本（原样，未拆行）。
  final List<String> notes;

  const PublicTimetable({
    required this.fields,
    required this.owner,
    required this.cells,
    this.notes = const [],
  });

  /// 某字段值（按标签前缀匹配）。
  String fieldOf(String labelPrefix) {
    for (final f in fields) {
      if (f.label.startsWith(labelPrefix)) return f.value;
    }
    return '';
  }

  /// 描述块的紧凑描述（`会计学院 · 2026 · 会计学` 风格）。
  String get subtitle => fields.map((f) => f.value).where((v) => v.isNotEmpty).join(' · ');

  bool get isEmpty => cells.isEmpty;

  @override
  String toString() => 'PublicTimetable($owner, ${cells.length} 格)';
}

/// 解析报表 HTML → 若干对象课表。
///
/// [ownerPrefixes] 决定对象名从哪个字段取（如班级课表传 `['班级']`）；
/// 都取不到时退化为「描述块全部值拼接」。
List<PublicTimetable> parsePublicTimetableReport(
  String html, {
  List<String> ownerPrefixes = const [],
}) {
  if (html.trim().isEmpty) return const [];
  final tables = RegExp(
    r"<table class='table' id='mytable(\d+)'(.*?)</table>",
    dotAll: true,
  ).allMatches(html).toList();
  if (tables.isEmpty) return const [];

  final notes = _parseNotes(html);
  final out = <PublicTimetable>[];
  for (final t in tables) {
    final tableText = t.group(2) ?? '';
    final fields = _parseFields(html, t.start);
    final cells = _parseCells(tableText);
    out.add(
      PublicTimetable(
        fields: fields,
        owner: _pickOwner(fields, ownerPrefixes),
        cells: cells,
        notes: notes,
      ),
    );
  }
  return out;
}

/// 解析描述块（`<div group="group">` 内的 `float:left` 项）。
List<({String label, String value})> _parseFields(String html, int tableStart) {
  final blockStart = html.lastIndexOf('<div group="group"', tableStart);
  if (blockStart < 0) return const [];
  final end = html.indexOf('<!-- 报表区 -->', blockStart);
  final block = html.substring(
    blockStart,
    end < 0 || end > tableStart ? tableStart : end,
  );
  final out = <({String label, String value})>[];
  for (final m in RegExp(
    r'<div style="float:left[^"]*">(.*?)</div>',
    dotAll: true,
  ).allMatches(block)) {
    final raw = _clean(m.group(1)!);
    if (raw.isEmpty) continue;
    final idx = raw.indexOf('：');
    if (idx < 0) {
      out.add((label: raw, value: ''));
    } else {
      final label = raw.substring(0, idx).trim();
      final value = raw.substring(idx + 1).trim();
      out.add((label: label, value: value));
    }
  }
  return out;
}

/// 解析网格格子：行标签（大节）+ `div1` id（星期/大节）+ `title`（内容）。
List<PublicTimetableCell> _parseCells(String tableText) {
  // 1) 行标签：`<td class='td1' …><b>1-2节</b>`（半日块标签是 `<b>上<br>午</b>`，不匹配）
  final marks = <({int pos, int start, int end})>[];
  for (final m in RegExp(
    r"<td class='td1'[^>]*>\s*<b>\s*(\d+)\s*(?:-\s*(\d+))?\s*节\s*</b>",
  ).allMatches(tableText)) {
    final start = int.tryParse(m.group(1) ?? '');
    if (start == null) continue;
    final end = int.tryParse(m.group(2) ?? '') ?? start;
    marks.add((pos: m.start, start: start, end: end));
  }

  // 2) 格子：`<td class='td' … title="…"><div class='div1' … id='NNN'>`
  final out = <PublicTimetableCell>[];
  for (final m in RegExp(
    r"""<td class='td'[^>]*title="([^"]*)"[^>]*>\s*<div class='div1'[^>]*id='(\d+)'\s*>""",
    dotAll: true,
  ).allMatches(tableText)) {
    final titleRaw = m.group(1) ?? '';
    final id = m.group(2) ?? '';
    if (id.length < 3) continue;
    final period = int.tryParse(id.substring(id.length - 1));
    final weekday = int.tryParse(id.substring(id.length - 2, id.length - 1));
    if (period == null || weekday == null) continue;
    if (weekday < 1 || weekday > 7 || period < 1 || period > 9) continue;

    final parts = _splitParts(titleRaw);
    if (parts.isEmpty) continue;

    // 该格所属的大节 = 它前面最近的行标签
    var span = (start: period, end: period);
    for (final mk in marks) {
      if (mk.pos < m.start) {
        span = (start: mk.start, end: mk.end);
      } else {
        break;
      }
    }
    final weeks = _parseWeeks(parts);
    out.add(
      PublicTimetableCell(
        weekday: weekday,
        periodIndex: period,
        startPeriod: span.start,
        endPeriod: span.end,
        text: parts.join(' '),
        parts: parts,
        startWeek: weeks.start,
        endWeek: weeks.end,
        parity: weeks.parity,
      ),
    );
  }
  return out;
}

/// 把 `&ensp;` 分隔的原文切成片段（实体还原、去空段）。
///
/// 真页面的 `title` 属性里是**字面** `&ensp;`；少数分支会再转义成 `&amp;ensp;`，
/// 所以两种都认，避免整格糊成一段。
List<String> _splitParts(String raw) {
  final normalized = raw.replaceAll('&amp;ensp;', '&ensp;');
  final out = <String>[];
  for (final piece in normalized.split('&ensp;')) {
    final v = _clean(piece);
    if (v.isNotEmpty) out.add(v);
  }
  return out;
}

/// 还原常见 HTML 实体并压掉空白。
String _clean(String raw) => raw
    .replaceAll('&ensp;', ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&#13;', ' ')
    .replaceAll('&#10;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'<br\s*/?>'), ' ')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// 从片段里找 `[2-17]周` / `[1-16]周(单)` / `[3]周`。
({int start, int end, WeekParity parity}) _parseWeeks(List<String> parts) {
  for (final p in parts) {
    final m = RegExp(r'\[(\d+)(?:\s*-\s*(\d+))?\]\s*周?').firstMatch(p);
    if (m == null) continue;
    final a = int.tryParse(m.group(1) ?? '');
    if (a == null) continue;
    final b = int.tryParse(m.group(2) ?? '') ?? a;
    final parity = p.contains('单')
        ? WeekParity.odd
        : p.contains('双')
        ? WeekParity.even
        : WeekParity.every;
    return (start: a, end: b, parity: parity);
  }
  return (start: 1, end: 30, parity: WeekParity.every);
}

/// 表尾备注（`备注1[…]：…`、`注1：…`），整段文本原样保留。
List<String> _parseNotes(String html) {
  final out = <String>[];
  for (final m in RegExp(
    r'<strong>\s*备注\d+\s*\[[^\]]*\]\s*</strong>',
    dotAll: true,
  ).allMatches(html)) {
    final tail = html.substring(m.end, (m.end + 400).clamp(0, html.length));
    final text = _clean(tail.split('</td>').first);
    if (text.isNotEmpty) out.add('${_clean(m.group(0)!)}：$text');
  }
  for (final m in RegExp(r'注\d+：[^<]{2,200}').allMatches(html)) {
    final text = _clean(m.group(0)!);
    if (text.isNotEmpty) out.add(text);
  }
  return out;
}

/// 对象名：先按**精确标签**取（`教室` 不能命中 `教室类型`），再退化为前缀匹配；
/// 都取不到就用描述块拼接。
String _pickOwner(
  List<({String label, String value})> fields,
  List<String> ownerPrefixes,
) {
  for (final prefix in ownerPrefixes) {
    for (final f in fields) {
      if (f.label == prefix && f.value.isNotEmpty) {
        return _stripTail(f.value);
      }
    }
    for (final f in fields) {
      if (f.label.startsWith('$prefix(') && f.value.isNotEmpty) {
        // `院(系)/部` 这类带括号的标签
        return _stripTail(f.value);
      }
    }
  }
  return fields
      .map((f) => f.value)
      .where((v) => v.isNotEmpty)
      .join(' · ');
}

/// 去掉名称尾巴上的 `[人数]` / `(容量)`。
String _stripTail(String value) =>
    value.replaceFirst(RegExp(r'(\[[^\]]*\]|\([^)]*\))\s*$'), '').trim();

/// 把一批课表格子转成「找无课时间」引擎用的占用槽。
///
/// [owner] 为空时用 `timetable.owner`；[kind] 只影响槽里课程名的取法
/// （教师课表格子第一段是课程名，班级/教室课表也是；课程课表第一段是教师名）。
List<ScheduleSlot> slotsOfTimetables(
  Iterable<PublicTimetable> timetables, {
  String Function(PublicTimetable, PublicTimetableCell)? nameOf,
  String Function(PublicTimetable)? ownerOf,
}) => [
  for (final t in timetables)
    for (final c in t.cells)
      ScheduleSlot(
        weekday: c.weekday,
        startPeriod: c.startPeriod,
        endPeriod: c.endPeriod,
        startWeek: c.startWeek,
        endWeek: c.endWeek,
        parity: c.parity,
        courseName: nameOf?.call(t, c) ?? _defaultName(t, c),
        owner: ownerOf?.call(t) ?? t.owner,
      ),
];

String _defaultName(PublicTimetable t, PublicTimetableCell c) =>
    c.parts.isEmpty ? t.owner : c.parts.first;
