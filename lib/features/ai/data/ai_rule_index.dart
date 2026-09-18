/// 规章制度全文索引（给 AI 工具用的「轻量 RAG」）。
///
/// 背景：`assets/rules/text/*.md` 合计 **427 KB**，整篇塞进提示词既不现实
/// （token 费钱且超过多数模型的上下文）也没必要 —— 用户问的永远是某一条。
/// 这里把每篇 md 按标题切成**小节**，检索时按关键词打分只回传命中的几节。
///
/// 为什么不用向量检索：assets 是**随包固定**的，没有增量；中文里「学籍」
/// 「奖学金」这类词表意明确，子串匹配 + 标题加权已经够准，还省掉一个模型调用
/// （那会让「问一条规定」从 1 秒变 5 秒，还得再配一个 embedding 端点）。
library;

import 'package:flutter/services.dart' show rootBundle;

import 'package:smarter_jxufe/features/rules/domain/rule_doc.dart';

/// md 载入器（默认读资产包；测试可注入）。
typedef AiAssetLoader = Future<String> Function(String assetKey);

/// 一篇文档切出的一节。
class RuleSection {
  /// 标题路径（如 `第三章 学籍异动 › 第二节 转专业`；文档开头的散段用文档名）。
  final String path;

  /// 该节正文（已去掉 markdown 装饰）。
  final String body;

  /// 标题在文档里的顺序（0 = 文档开头到第一个标题之间的前言）。
  final int index;

  const RuleSection({
    required this.path,
    required this.body,
    required this.index,
  });

  /// 给模型看的片段（超长截断 —— 单节动辄上万字时不能整段回传）。
  String clip([int max = 1800]) =>
      body.length <= max ? body : '${body.substring(0, max)}…（本节较长，已被截断）';
}

/// 一篇文档的索引。
class RuleDocIndex {
  final RuleDoc doc;
  final List<RuleSection> sections;

  const RuleDocIndex({required this.doc, required this.sections});
}

/// 全量索引。
class AiRuleIndex {
  final List<RuleDocIndex> docs;

  const AiRuleIndex(this.docs);

  bool get isEmpty => docs.isEmpty;

  RuleDocIndex? byId(String id) {
    for (final d in docs) {
      if (d.doc.id == id) return d;
    }
    return null;
  }

  /// 按标题模糊找文档（模型常只记得名字，记不住 `r03a` 这种 id）。
  RuleDocIndex? byTitle(String keyword) {
    final key = keyword.trim();
    if (key.isEmpty) return null;
    for (final d in docs) {
      if (d.doc.title == key) return d;
    }
    for (final d in docs) {
      if (d.doc.title.contains(key)) return d;
    }
    for (final d in docs) {
      if (d.doc.id == key) return d;
    }
    return null;
  }
}

/// 一条检索命中。
class RuleHit {
  final RuleDoc doc;
  final RuleSection section;

  /// 命中次数（已按标题加权）。
  final double score;

  const RuleHit({
    required this.doc,
    required this.section,
    required this.score,
  });
}

/// 把 markdown 正文切成小节。
///
/// 切分口径：**每个标题（`#`~`###`）开一节**，标题之前的正文归到第 0 节。
/// 目录类文档（`template == catalog`，正文是大表格）没有标题层级 —— 按
/// 5000 字硬切，保证单节不会超长。
List<RuleSection> splitRuleSections(String markdown, {bool tableHeavy = false}) {
  final lines = markdown.split('\n');
  final sections = <RuleSection>[];
  final headingStack = <int, String>{};
  final buffer = StringBuffer();
  var index = 0;
  var currentPath = '';

  void flush() {
    final body = _cleanMarkdown(buffer.toString());
    buffer.clear();
    if (body.trim().isEmpty) return;
    sections.add(RuleSection(path: currentPath, body: body, index: index++));
  }

  for (final line in lines) {
    final match = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(line.trimRight());
    if (match != null && !tableHeavy) {
      flush();
      final level = match.group(1)!.length;
      final text = _stripInline(match.group(2)!.trim());
      // 同级或更深的旧标题作废，浅的保留 —— 于是 path 天然是「章 › 节」
      headingStack.removeWhere((k, _) => k >= level);
      headingStack[level] = text;
      final keys = headingStack.keys.toList()..sort();
      currentPath = [for (final k in keys) headingStack[k]!].join(' › ');
      continue;
    }
    buffer.writeln(line);
  }
  flush();

  // 无标题的目录类文档 + 标题下超长的条文，统一再按长度硬切
  return _splitLong(sections);
}

/// 把超长小节再按段落硬切（避免一节 80KB 直接撑爆上下文）。
List<RuleSection> _splitLong(List<RuleSection> sections, {int maxChars = 5000}) {
  final out = <RuleSection>[];
  var index = 0;
  for (final s in sections) {
    if (s.body.length <= maxChars) {
      out.add(RuleSection(path: s.path, body: s.body, index: index++));
      continue;
    }
    var offset = 0;
    var part = 1;
    while (offset < s.body.length) {
      var end = offset + maxChars;
      if (end >= s.body.length) {
        end = s.body.length;
      } else {
        final nl = s.body.lastIndexOf('\n', end);
        if (nl > offset + maxChars ~/ 2) end = nl;
      }
      out.add(
        RuleSection(
          path: '${s.path}（第 $part 段）',
          body: s.body.substring(offset, end),
          index: index++,
        ),
      );
      offset = end;
      part++;
    }
  }
  return out;
}

/// 去掉 markdown 装饰，留下给模型读的纯文本。
String _cleanMarkdown(String raw) {
  final lines = raw.split('\n');
  final out = <String>[];
  for (var line in lines) {
    final t = line.trimRight();
    if (t.trim().isEmpty) {
      if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
      continue;
    }
    // 表格分隔行（|---|---|）没有信息量
    if (RegExp(r'^\s*\|?[\s:|-]+\|[\s:|-]*$').hasMatch(t) &&
        !RegExp(r'[A-Za-z0-9\u4e00-\u9fa5]').hasMatch(t)) {
      continue;
    }
    out.add(_stripInline(t));
  }
  // 折叠连续空行
  final text = out.join('\n');
  return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// 行内装饰（`**粗**`、`*斜*`、`` `码` ``、`[文](链接)`、`![图](链接)`、HTML 标签）。
///
/// ⚠ 必须用 `replaceAllMapped` 而不是 `replaceAll` —— **Dart 的 `replaceAll`
/// 不解释 `$1`**，直接写 `replaceAll(re, r'$1')` 会把整行替换成字面量 `$1`
/// （实测把「**粗体**」变成了「$1」）。
String _stripInline(String line) {
  var t = line;
  t = t.replaceAllMapped(RegExp(r'!\[[^\]]*\]\([^)]*\)'), (_) => '');
  t = t.replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
  t = t.replaceAllMapped(RegExp(r'\*\*([^*]*)\*\*'), (m) => m.group(1) ?? '');
  t = t.replaceAllMapped(
    RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)'),
    (m) => m.group(1) ?? '',
  );
  t = t.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1) ?? '');
  t = t.replaceAll(RegExp(r'<[^>]+>'), '');
  return t.trim();
}

/// 载入全部文档并建索引。
///
/// [loader] 默认读资产包；[onlyGroups] 非空时只索引这些分类（省时间）。
Future<AiRuleIndex> loadAiRuleIndex(
  RulesCatalog catalog, {
  AiAssetLoader? loader,
  Set<String>? onlyGroups,
}) async {
  final load = loader ?? (key) => rootBundle.loadString(key);
  final docs = <RuleDocIndex>[];
  for (final doc in catalog.docs) {
    if (onlyGroups != null && !onlyGroups.contains(doc.group)) continue;
    String raw;
    try {
      raw = await load(doc.mdAsset);
    } catch (_) {
      // 单篇读不出来不该让整次检索失败
      continue;
    }
    final sections = splitRuleSections(
      raw,
      tableHeavy: doc.template == RuleTemplate.catalog,
    );
    if (sections.isEmpty) continue;
    docs.add(RuleDocIndex(doc: doc, sections: sections));
  }
  return AiRuleIndex(docs);
}

/// 进程内缓存（assets 随包固定，进程生命周期内不会变）。
final Map<String, AiRuleIndex> _indexCache = {};

/// 取索引（带缓存）。[loader] 只在首次生效。
Future<AiRuleIndex> aiRuleIndexFor(
  RulesCatalog catalog, {
  AiAssetLoader? loader,
}) {
  const key = 'all';
  final cached = _indexCache[key];
  if (cached != null) return Future.value(cached);
  return loadAiRuleIndex(catalog, loader: loader).then((index) {
    _indexCache[key] = index;
    return index;
  });
}

/// 清空缓存（测试用）。
void clearAiRuleIndexCache() => _indexCache.clear();

/// 关键词检索。
///
/// 打分口径（简单但有效）：
/// - 查询按空白 / 标点拆成词；
/// - 正文每命中一次 +1；
/// - 标题命中 ×3（标题命中基本等于「这一节就是在讲这件事」）；
/// - 全文命中整句（未拆分时）额外 +2；
/// - 命中词种类 ≥2 时整体 ×1.5（多词同时出现比单词重复更有意义）。
List<RuleHit> searchAiRules(
  AiRuleIndex index,
  String query, {
  String? group,
  int limit = 5,
  int minScore = 1,
}) {
  final terms = _queryTerms(query);
  if (terms.isEmpty) return const [];
  final phrase = query.trim();
  final hits = <RuleHit>[];
  for (final doc in index.docs) {
    if (group != null && group.trim().isNotEmpty && doc.doc.group != group.trim()) {
      continue;
    }
    for (final section in doc.sections) {
      final haystack = section.body;
      final titleHay = section.path + doc.doc.title;
      var score = 0.0;
      var matchedTerms = 0;
      for (final term in terms) {
        final inBody = _countOccurrences(haystack, term);
        final inTitle = _countOccurrences(titleHay, term);
        if (inBody == 0 && inTitle == 0) continue;
        matchedTerms++;
        score += inBody * 1.0 + inTitle * 3.0;
      }
      if (matchedTerms == 0) continue;
      if (terms.length > 1 && phrase.length >= 2 && haystack.contains(phrase)) {
        score += 2;
      }
      if (matchedTerms >= 2) score *= 1.5;
      if (score >= minScore) {
        hits.add(RuleHit(doc: doc.doc, section: section, score: score));
      }
    }
  }
  hits.sort((a, b) => b.score.compareTo(a.score));
  return hits.length <= limit ? hits : hits.sublist(0, limit);
}

/// 查询分词用的分隔符集合。
///
/// 用**非 raw 字符串**写（`\\s` 才是正则的 `\s`，`\\\\` 才是正则的字面反斜杠）
/// —— 里面既有 `'` 又有 `"` 又有 `\`，raw 字符串在这里会写错。
final RegExp _querySeparators = RegExp(
  '[\\s,，、;；:：?？!！。./\\\\|()（）\\[\\]【】"\'“”‘’]+',
);

/// 查询分词：空白与常见标点切分；同时保留**原始整句**作为词组命中判据。
List<String> _queryTerms(String query) {
  final raw = query.trim();
  if (raw.isEmpty) return const [];
  final parts = raw
      .split(_querySeparators)
      .map((s) => s.trim())
      .where((s) => s.length >= 2)
      .toList();
  if (parts.isEmpty) {
    // 全是单字（如「奖」）：单字查询精度太差，直接放弃检索
    return const [];
  }
  return parts;
}

int _countOccurrences(String haystack, String needle) {
  if (needle.isEmpty) return 0;
  var count = 0;
  var start = 0;
  while (true) {
    final idx = haystack.indexOf(needle, start);
    if (idx < 0) break;
    count++;
    start = idx + needle.length;
    if (count > 50) break; // 命中太多次时再数没有意义
  }
  return count;
}

/// 从正文里抠出包含关键词的一小段（给模型看的摘要）。
String aiRuleSnippet(String body, String query, {int radius = 120}) {
  final terms = _queryTerms(query);
  if (terms.isEmpty) return body.length <= radius * 2 ? body : body.substring(0, radius * 2);
  var best = -1;
  for (final term in terms) {
    final idx = body.indexOf(term);
    if (idx >= 0 && (best < 0 || idx < best)) best = idx;
  }
  if (best < 0) {
    return body.length <= radius * 2 ? body : '${body.substring(0, radius * 2)}…';
  }
  final start = (best - radius).clamp(0, body.length);
  final end = (best + radius).clamp(0, body.length);
  return '${start > 0 ? '…' : ''}${body.substring(start, end)}${end < body.length ? '…' : ''}';
}
