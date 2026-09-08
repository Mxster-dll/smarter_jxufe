/// 智慧江财小程序校历 `remark`（HTML）→ [WxSemesterArrangement] 解析器。
///
/// 兼容两种版式：
/// - 行式/表格式（近两年）：<p> 短行 或 <table>（<strong> 分类节 + 日期/事件行），
///   逐行解析为 [WxCalEvent]（含日期区间合并与跨年定位）。
/// - 段落式（2017~2025 秋）：整段通知文体，保留原文为 notes，不拆事件。
///
/// 解析算法与 reverse_engineering 侧 Python 原型（tools/_wxcal_parse_events.py）
/// 保持同构，测试见 test/wxcal_remark_parser_test.dart。
library;

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';

/// 行首日期头：`2023年2月13日` / `9月2日` / `9月25日-27日` / `6月29日-7月5日` /
/// `10月1日-7日` / `元月16日`。
final _dateHead = RegExp(
  r'^(?:(?<y>\d{4})年)?(?:(?<yue>元|(?<m>\d{1,2}))月)?(?<d>\d{1,2})日',
);

/// 分类节标题词。
const _categoryWords = {
  '教职员工', '教职工', '本科生', '研究生', '全校', '全体学生', '高职学生', '专升本学生', '新生',
};

/// 编号段首（如「一、教职工8月30日正式上班」里的「一、」）。
final _numberedLead = RegExp(r'^[一二三四五六七八九十]+、?');

String _collapse(String s) => s.replaceAll(RegExp(r'[ \t\u3000\u00a0]+'), ' ').trim();

String _textOf(Element el) {
  final b = el.text;
  return _collapse(b.replaceAll(RegExp(r'\s*\n\s*'), ' '));
}

DateTime? _resolveYear(DateTime start, DateTime end, int? y, int m, int d) {
  DateTime? at(int year) {
    try {
      return DateTime(year, m, d);
    } on ArgumentError {
      return null;
    }
  }

  if (y != null) return at(y);
  final cand = <DateTime>[if (at(start.year) != null) at(start.year)!, if (at(start.year + 1) != null) at(start.year + 1)!];
  final lo = start.subtract(const Duration(days: 5));
  final hi = end.add(const Duration(days: 20));
  for (final c in cand) {
    if (!c.isBefore(lo) && !c.isAfter(hi)) return c;
  }
  return cand.isEmpty ? null : cand.first;
}

/// 把一行（可能含多个日期头）切成若干事件。
List<WxCalEvent> _eventsOfRow(String rowText, String? category, DateTime start, DateTime end) {
  final out = <WxCalEvent>[];
  final heads = _dateHead.allMatches(rowText).toList();
  for (var i = 0; i < heads.length; i++) {
    final h = heads[i];
    final segEnd = i + 1 < heads.length ? heads[i + 1].start : rowText.length;
    final seg = rowText.substring(h.start, segEnd);
    final y = h.namedGroup('y') == null ? null : int.parse(h.namedGroup('y')!);
    final mRaw = h.namedGroup('m');
    final m = mRaw != null ? int.parse(mRaw) : (h.namedGroup('yue') != null ? 1 : 0);
    if (m == 0) continue;
    final d = int.parse(h.namedGroup('d')!);
    var rest = seg.substring(h.end);
    final rng = RegExp(r'^\s*[-—~至到]\s*(?:(?<rm>\d{1,2}|元)月)?(?<rd>\d{1,2})日?').firstMatch(rest);
    final from = _resolveYear(start, end, y, m, d);
    DateTime? to;
    if (rng != null) {
      final rmRaw = rng.namedGroup('rm');
      final rm = rmRaw == null ? m : (rmRaw == '元' ? 1 : int.parse(rmRaw));
      final rd = int.parse(rng.namedGroup('rd')!);
      to = _resolveYear(start, end, rmRaw == null ? y : null, rm, rd);
      rest = rest.substring(rng.end);
    }
    if (from == null) continue;
    var body = _collapse(rest).replaceFirst(RegExp(r'^[，,、:：\s]+'), '');
    if (body.isEmpty) body = _collapse(seg).isEmpty ? rowText : _collapse(seg);
    out.add(WxCalEvent(
      from: from,
      to: to ?? from,
      text: body,
      category: category == null || category.isEmpty ? null : category,
    ));
  }
  return out;
}

/// 解析 remark HTML → 学期安排模型。
WxSemesterArrangement parseWxRemark({
  required int id,
  required String term,
  required String startDate, // yyyy-MM-dd
  required String endDate,
  required String remark,
}) {
  final start = DateTime.parse(startDate);
  final end = DateTime.parse(endDate);
  final isTable = remark.contains('<tr');
  final trimmed = remark.trim();

  if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') {
    return WxSemesterArrangement(
        id: id, term: term, start: start, end: end, style: WxArrangementStyle.empty);
  }

  final rows = <({String text, bool strong})>[];
  if (isTable) {
    final doc = html_parser.parse(remark);
    for (final tr in doc.querySelectorAll('tr')) {
      final cells = tr.querySelectorAll('td').map(_textOf).where((c) => c.isNotEmpty).toList();
      if (cells.isEmpty) continue;
      final text = cells.join(' ');
      final strong = tr.querySelector('strong') != null;
      rows.add((text: text, strong: strong));
    }
  } else {
    final rest = remark.replaceAll(
        RegExp(r'<table[^>]*>.*?</table>', caseSensitive: false, dotAll: true), '');
    final doc = html_parser.parse(rest);
    for (final p in doc.querySelectorAll('p')) {
      final t = _textOf(p);
      if (t.isNotEmpty) rows.add((text: t, strong: false));
    }
  }

  final events = <WxCalEvent>[];
  final notes = <String>[];
  String? category;
  for (final r in rows) {
    var text = r.text;
    // 分类节标题行：单独类别词（可能带空格如「本 科 生」）或编号小标题。
    final catCandidate = text.replaceAll(RegExp(r'\s+'), '');
    if (r.strong || _categoryWords.contains(catCandidate)) {
      final c = catCandidate;
      if (_categoryWords.contains(c)) {
        category = c;
        continue;
      }
    }
    final noNumber = text.replaceFirst(_numberedLead, '').trim();
    if (noNumber.isNotEmpty && _categoryWords.contains(noNumber.replaceAll(RegExp(r'\s+'), ''))) {
      category = noNumber.replaceAll(RegExp(r'\s+'), '');
      continue;
    }
    // 仅「行首即日期」的行拆事件；含日期但非行首的段落文字保留原文。
    if (_dateHead.matchAsPrefix(text) != null) {
      events.addAll(_eventsOfRow(text, category, start, end));
    } else {
      notes.add(text);
    }
  }

  final style = isTable
      ? WxArrangementStyle.table
      : (events.isNotEmpty ? WxArrangementStyle.lines : WxArrangementStyle.paragraph);
  return WxSemesterArrangement(
    id: id,
    term: term,
    start: start,
    end: end,
    style: style,
    events: events,
    notes: notes,
  );
}
