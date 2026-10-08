/// 规章制度阅读页 · **行判定件**（顶层函数）。
///
/// 拆分自 `rules_reader_screen.dart`（2026-10-08 架构审计第三轮）：那个 State 1112 行、
/// 37 个成员。这里只放**依赖闭包最干净的一层** —— 7 个行判定正则 +
/// `rdPrettyChapter` + 4 个谓词（`rdIsRecipient` / `rdIsUnitLine` / `rdIsClauseTitle` / `rdIsSubHead`）。
/// 它们全是 `String → bool/String` 的纯函数，不碰 `context` / `widget` / `_font` / `_keys`，
/// 所以能整块搬走；命名统一 `rd` 前缀（沿用 zc / dc / Settings 的先例）。
///
/// ⚠ **下一轮再动的**：4 个只差「显式 context」的渲染件（版本胶囊 / 目录横幅 / 章头 /
/// 通用小标题）与读 `_font` / `_keys` 的那批（`_buildBody` / `_paraWidgetsAt` /
/// `_buildCatalog` / `_docTitleBanner` / `_clauseHeader` / `_bodyPara` / `_tocList` …）。
/// 教训：State 类里 **`context` / `widget` / `mounted` / `setState` 是隐式成员** ——
/// 「只引用同类成员」的闭包检查**抓不到它们**，实测把这 4 个件搬出去直接报
/// `Undefined name 'context'` / `'widget'`（口径见 AGENTS.md §33.4.4）。
library;

final rdChapterBody = RegExp(r'^第[一二三四五六七八九十百零]+章');

final rdClauseBody = RegExp(r'^第[一二三四五六七八九十百零]+条');

final rdDateBody = RegExp(r'^\d{4}年\d{1,2}月\d{1,2}日$');

final rdWenhaoBody = RegExp(r'^.{0,24}〔.{1,20}〕.*号$');

final rdSubEnum = RegExp(r'^（[一二三四五六七八九十]+）');

final rdSubNum = RegExp(r'^\d{1,2}[.、]');

final rdSectionBody = RegExp(r'^[一二三四五六七八九十]+、');

/// 「第一章总则」→「第一章 总则」；已是「第一章 总则」则保持。
String rdPrettyChapter(String t) {
  final m = RegExp(r'^(第[一二三四五六七八九十百零]+章)(.*)$').firstMatch(t);
  if (m == null) return t;
  final rest = m.group(2)!.trim();
  return rest.isEmpty ? m.group(1)! : '${m.group(1)} $rest';
}

bool rdIsRecipient(String t) {
  if (t.length > 30 || !(t.endsWith(':') || t.endsWith('：'))) return false;
  return t.contains('各单位') ||
      t.contains('各部门') ||
      t.contains('各学院') ||
      t.startsWith('校属');
}

bool rdIsUnitLine(String t) {
  if (t.isEmpty || t.length > 18) return false;
  if (RegExp(r'[，。；、：？！]').hasMatch(t)) return false;
  return RegExp(r'(大学|办公室|委员会|学院|校长|处|部|室)$').hasMatch(t);
}

bool rdIsClauseTitle(String rest) {
  // 「第X条」后是否为短条名（标题行）而非条文长句正文。
  if (rest.isEmpty) return true;
  if (rest.length > 14) return false;
  // 含句子标点视为正文长句（如"第十三条 考核分为考试和考查两类，"）。
  if (RegExp(r'[，。；：！？、…—]').hasMatch(rest)) return false;
  return true;
}

bool rdIsSubHead(String t) {
  if (t.length > 36 || RegExp(r'[。；！？]').hasMatch(t)) return false;
  if (rdSubEnum.hasMatch(t) ||
      rdSubNum.hasMatch(t) ||
      (rdClauseBody.hasMatch(t) && t.length <= 24)) {
    return true;
  }
  // 短中文无标点独立行：办法中的条内小标题（如「竞赛奖励标准」）。
  if (t.length <= 12 &&
      !RegExp(r'[0-9A-Za-z，、：（）《》]').hasMatch(t) &&
      !rdIsUnitLine(t)) {
    return true;
  }
  return false;
}
