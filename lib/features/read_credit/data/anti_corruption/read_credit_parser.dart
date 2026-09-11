/// 阅读学分平台 HTML 解析（学分查询页 + 明细表）。
///
/// 页面为 ASP.NET MVC 服务端渲染：学分查询页由若干 `div.title`
/// （`名称：<span class="titleTrue|titleFalse">状态</span> … 更新时间：…`）
/// 与紧随其后的 `div.info`（`电子阅读[2] 纸质阅读[0]` 或 `无信息`）组成；
/// 明细页是一张标准 `thead/th + tbody/td` 表。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'package:smarter_jxufe/features/read_credit/domain/read_credit_models.dart';

String _norm(String? raw) =>
    (raw ?? '').replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();

/// 解析学分查询页（`/Web/ReadMain/Score`）。
ReadCreditScore parseReadCreditScore(String html) {
  final doc = html_parser.parse(html);
  final items = <ReadCreditItem>[];
  var granted = false;
  var creditText = '';
  for (final el in doc.querySelectorAll('div.title')) {
    final text = _norm(el.text);
    final head = RegExp(r'^(.{2,8}?)[：:]').firstMatch(text);
    if (head == null) continue;
    final label = head.group(1)!;
    if (label == '学分状态') {
      creditText = _norm(text.replaceFirst(RegExp(r'^学分状态[：:]'), ''));
      granted = creditText.contains('获得学分') && !creditText.contains('未获得');
      continue;
    }
    final kind = ReadCreditKind.fromLabel(label);
    if (kind == null) continue;
    final statusEl =
        el.querySelector('.titleTrue') ?? el.querySelector('.titleFalse');
    final statusText = _norm(statusEl?.text);
    bool? passed;
    if (statusText.isNotEmpty) {
      passed = statusText.contains('通过') && !statusText.contains('未通过');
    }
    final updatedAt = RegExp(
      r'更新时间[：:]\s*([0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日)',
    ).firstMatch(text)?.group(1);
    String? infoRaw;
    final sibling = el.nextElementSibling;
    if (sibling != null && sibling.classes.contains('info')) {
      final raw = _norm(sibling.text);
      if (raw.isNotEmpty && !raw.contains('无信息')) infoRaw = raw;
    }
    items.add(
      ReadCreditItem(
        kind: kind,
        statusText: statusText,
        passed: passed,
        updatedAt: updatedAt,
        infoRaw: infoRaw,
        counts: parseReadCreditCounts(infoRaw),
      ),
    );
  }
  return ReadCreditScore(
    items: items,
    creditGranted: granted,
    creditText: creditText,
  );
}

/// 解析 `电子阅读[2] 纸质阅读[0]` 形式的计数摘要。
List<ReadCreditCount> parseReadCreditCounts(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final out = <ReadCreditCount>[];
  for (final m in RegExp(
    r'([^\[\]【】\s]+?)\s*[\[【]\s*(\d+)\s*[\]】]',
  ).allMatches(raw)) {
    out.add(ReadCreditCount(m.group(1)!, int.tryParse(m.group(2)!) ?? 0));
  }
  return out;
}

/// 解析某一项的明细表（`/Web/Read/Index/<segment>`）。
///
/// 列名由服务端决定，各 kind 不同（阅读类=书名/完成时间/时长/厂商；
/// 入馆教育=闯关结束时间/是否通过；信息素养=视频数量/时长/完成时间），
/// 故此处按「表头 + 行」通用解析，界面侧按列名取用。
ReadCreditDetail parseReadCreditDetail(String html, ReadCreditKind kind) {
  final doc = html_parser.parse(html);
  final table = doc.querySelector('table');
  if (table == null) {
    return ReadCreditDetail(kind: kind);
  }
  var headers = table
      .querySelectorAll('thead th')
      .map((e) => _norm(e.text))
      .toList();
  var bodyRows = table.querySelectorAll('tbody tr').toList();
  if (headers.isEmpty) {
    final firstRow = table.querySelector('tr');
    if (firstRow != null) {
      headers = firstRow
          .querySelectorAll('th')
          .map((e) => _norm(e.text))
          .toList();
      if (headers.isEmpty) {
        headers = firstRow
            .querySelectorAll('td')
            .map((e) => _norm(e.text))
            .toList();
      }
    }
  }
  if (bodyRows.isEmpty) {
    final all = table.querySelectorAll('tr').toList();
    bodyRows = all.length > 1 ? all.sublist(1) : const <Element>[];
  }
  final rows = <List<String>>[];
  for (final tr in bodyRows) {
    final cells = tr.querySelectorAll('td').map((e) => _norm(e.text)).toList();
    if (cells.isEmpty) continue;
    if (cells.every((c) => c.isEmpty)) continue;
    rows.add(cells);
  }
  return ReadCreditDetail(kind: kind, headers: headers, rows: rows);
}
