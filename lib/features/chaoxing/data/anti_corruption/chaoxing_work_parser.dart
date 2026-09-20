/// 学习通 · 作业页解析（课程「作业」tab 与作业列表）。
///
/// 两个入口：
/// 1. [chaoxingWorkEntryQuery] —— 从**课程详情页**里抠出作业列表的 query
///    （关键是每门课各不相同的 `enc` / `openc` 签名）；
/// 2. [parseChaoxingWorks] —— 解析**作业页**里的条目。
///
/// 实测 DOM（2026-09-19，`/mooc-ans/work/getAllWork` 返回 HTML 不是 JSON）：
/// ```html
/// <li style="padding:30px 0">
///   <div class="titTxt" data="0">
///     <p class="clearfix">
///       <a class="inspectTask" data="55739815" data2="0" data3="0"
///          title="9月20日24:00前提交作业">9月20日24:00前提交作…</a>
///       <i id="reddot55739815" …></i>
///     </p>
///     <span class="pt5"><span class="fl">开始时间：</span>2026-09-17 14:28</span>
///     <span class="pt5"><span class="fl">截止时间：</span>2026-09-20 23:59</span>
///     <span class="pt5"><span class="fl">作业状态：</span><strong> 待做 </strong></span>
///   </div>
///   <div class="titOper"><span style="…">90分</span> …</div>
/// </li>
/// ```
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/chaoxing/domain/chaoxing_work.dart';

/// 从课程详情页里抠出作业列表的 query（`classId=…&courseId=…&ut=s&enc=…&cpi=…&openc=…`）。
///
/// 页面里该链接出现两次（`<a href>` 与 `<a data>`），页内 JS 还有 `&status=` /
/// `&pageNum=` 的变体 —— **优先取带 `enc=` 与 `openc=` 的那条**（那才是完整签名，
/// 少了 `openc` 会被服务端拒）。
/// 认不出返回 null（调用方据此跳过该课，而不是发一个残 query 出去）。
String? chaoxingWorkEntryQuery(String html) {
  if (html.trim().isEmpty) return null;
  final doc = _parse(html);
  if (doc == null) return null;

  final candidates = <String>[];
  for (final el in doc.querySelectorAll('[data*="getAllWork"]')) {
    final v = el.attributes['data'];
    if (v != null) candidates.add(v);
  }
  for (final el in doc.querySelectorAll('[href*="getAllWork"]')) {
    final v = el.attributes['href'];
    if (v != null) candidates.add(v);
  }

  String? best;
  for (final c in candidates) {
    final q = _queryOf(c);
    if (q == null) continue;
    if (q.contains('enc=') && q.contains('openc=')) return q;
    best ??= q;
  }
  return best;
}

/// 解析作业页 → 条目列表（顺序 = 页面顺序）。
///
/// [courseId] / [courseName] 由调用方回填（作业页自己不重复课程名，除了标题栏）。
/// 空课（页面含「暂无内容」）→ 空列表。
List<ChaoxingWork> parseChaoxingWorks(
  String html, {
  required String courseId,
  required String courseName,
}) {
  if (html.trim().isEmpty) return const [];
  final doc = _parse(html);
  if (doc == null) return const [];

  final out = <ChaoxingWork>[];
  final seen = <String>{};
  for (final li in doc.querySelectorAll('li')) {
    final box = li.querySelector('.titTxt');
    if (box == null) continue;
    final anchor = box.querySelector('a.inspectTask') ?? box.querySelector('a');
    if (anchor == null) continue;

    final workId = (anchor.attributes['data'] ?? '').trim();
    final titleAttr = _clean(anchor.attributes['title'] ?? '');
    final title = titleAttr.isEmpty ? _clean(anchor.text) : titleAttr;
    if (title.isEmpty && workId.isEmpty) continue;
    final id = workId.isEmpty ? title : workId;
    if (!seen.add(id)) continue;

    DateTime? startAt;
    DateTime? dueAt;
    ChaoxingWorkStatus status = ChaoxingWorkStatus.unknown;
    for (final span in box.querySelectorAll('span.pt5')) {
      final label = _clean(span.querySelector('span.fl')?.text ?? '');
      final strong = span.querySelector('strong');
      final value = _clean(
        strong?.text ?? span.text.replaceFirst(label, ''),
      );
      if (label.startsWith('开始时间')) {
        startAt = _date(value);
      } else if (label.startsWith('截止时间')) {
        dueAt = _date(value);
      } else if (label.startsWith('作业状态')) {
        status = ChaoxingWorkStatus.fromLabel(strong?.text ?? value);
      }
    }

    out.add(
      ChaoxingWork(
        workId: id,
        title: title.isEmpty ? id : title,
        courseId: courseId,
        courseName: courseName,
        startAt: startAt,
        dueAt: dueAt,
        status: status,
        score: _scoreOf(li),
      ),
    );
  }
  return out;
}

/// 页面是否明确写着「暂无内容」（该课确实没有作业）。
///
/// 与「解析出 0 条但页面结构变了」区分开：前者是正常空态，后者要让调用方知道
/// 结果可能不可信。两者都不抛。
bool chaoxingWorkPageIsEmpty(String html) {
  final doc = _parse(html);
  if (doc == null) return false;
  return doc.body?.text.contains('暂无内容') ?? false;
}

/// `.titOper` 里的分数（`90分`）→ `90.0`；没有/认不出返回 null。
double? _scoreOf(Element li) {
  final oper = li.querySelector('.titOper');
  if (oper == null) return null;
  for (final span in oper.querySelectorAll('span')) {
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s*分$').firstMatch(_clean(span.text));
    if (m != null) return double.tryParse(m.group(1)!);
  }
  return null;
}

/// 取 `…?a=b&c=d` 里 `?` 之后的部分；没有 `?` 返回 null。
String? _queryOf(String raw) {
  final t = raw.trim();
  final i = t.indexOf('?');
  if (i < 0 || i + 1 >= t.length) return null;
  final q = t.substring(i + 1).replaceAll('&amp;', '&');
  return q.contains('courseId=') ? q : null;
}

DateTime? _date(String raw) {
  final t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  // 页面是 `2026-09-17 14:28`（Dart 的 DateTime.parse 接受空格分隔）。
  final d = DateTime.tryParse(t);
  if (d != null) return d;
  final m = RegExp(r'(\d{4}-\d{2}-\d{2})\s*(\d{2}:\d{2})').firstMatch(t);
  return m == null ? null : DateTime.tryParse('${m.group(1)} ${m.group(2)}');
}

Document? _parse(String html) {
  try {
    return html_parser.parse(html);
  } catch (_) {
    return null;
  }
}

String _clean(String raw) => raw
    .replaceAll('\u00a0', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
