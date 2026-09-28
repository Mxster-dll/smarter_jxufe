/// 工具集：规章制度检索。
///
/// 两个工具配合使用（**刻意拆成两步**）：
/// 1. `search_rules` —— 关键词 → 命中的小节（只回传摘要）；
/// 2. `read_rule` —— 文档 id + 小节 → 该节完整正文。
///
/// 不合并成一个工具的原因：427KB 正文不可能一次回传，而「先看命中的是哪几节、
/// 再决定读哪一节」正是模型擅长的事 —— 拆开后每次请求的 token 都在几百这个量级。
library;

import 'package:smarter_jxufe/features/ai/data/ai_rule_index.dart';
import 'package:smarter_jxufe/features/ai/tools/ai_tool.dart';
import 'package:smarter_jxufe/features/rules/data/rules_repository.dart';
import 'package:smarter_jxufe/features/rules/domain/rule_doc.dart';

/// 检索规章制度（返回命中摘要）。
class SearchRulesTool extends AiTool {
  const SearchRulesTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'search_rules',
    description:
        '在学校的规章制度全文库里做关键词检索，返回命中的小节摘要。'
        '凡是涉及「学校怎么规定的」的问题（学籍、成绩、奖学金、推免、处分、'
        '竞赛认定、学分、毕业要求、请假等）都先用这个工具查，'
        '不要凭常识作答。拿到结果后如果摘要不够，再用 read_rule 读完整小节。',
    parameters: aiObjectSchema(
      {
        'query': aiStrProp('检索关键词，越具体越好，如「转专业 条件」「奖学金 评定 比例」'),
        'group': aiStrProp('可选，限定分类', fallbackHint: '留空则全库检索'),
        'limit': aiIntProp('返回几条，默认 5', min: 1, max: 10),
      },
      required: ['query'],
    ),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final query = a.str('query');
    final group = a.optStr('group');
    final limit = a.intOf('limit', fallback: 5);
    if (a.hasError) return AiToolResult.fail(a.errorText);

    final RulesCatalog catalog;
    try {
      catalog = await ctx.ref.read(rulesCatalogProvider.future);
    } catch (e) {
      return AiToolResult.fail('规章制度目录加载失败：$e');
    }

    final index = await aiRuleIndexFor(catalog);
    if (index.isEmpty) return const AiToolResult.fail('规章制度库为空或资源加载失败。');

    final hits = searchAiRules(index, query, group: group, limit: limit);
    if (hits.isEmpty) {
      final groups = catalog.groups.join('、');
      return AiToolResult.fail(
        '没有检索到与「$query」相关的规章条文。可换更通用的词再试；'
        '库里的分类有：$groups。',
      );
    }

    final buffer = StringBuffer()
      ..writeln('检索到 ${hits.length} 处相关条文（共 ${index.docs.length} 篇文档）：');
    for (final hit in hits) {
      buffer
        ..writeln()
        ..writeln('【${hit.doc.group}】${hit.doc.title}'
            '${hit.doc.wenhao == null ? '' : '（${hit.doc.wenhao}）'}')
        ..writeln('· 小节：${hit.section.path}')
        ..writeln('· 摘要：${aiRuleSnippet(hit.section.body, query)}')
        ..writeln('· doc_id：${hit.doc.id}');
    }
    buffer
      ..writeln()
      ..writeln('如需条文原文，用 read_rule(doc_id, section) 读取该小节。');

    return AiToolResult.ok(
      buffer.toString(),
      ui: {
        'kind': 'rules',
        'hits': [
          for (final hit in hits)
            {
              'docId': hit.doc.id,
              'title': hit.doc.title,
              'group': hit.doc.group,
              'section': hit.section.path,
            },
        ],
      },
    );
  }
}

/// 读规章制度正文（整节）。
class ReadRuleTool extends AiTool {
  const ReadRuleTool();

  @override
  AiToolSpec get spec => AiToolSpec(
    name: 'read_rule',
    description:
        '读取某篇规章制度的内容。传 doc_id（由 search_rules 给出）或文档标题；'
        '带 section 则只读该小节（推荐，最省 token），不带 section 则返回该文档的'
        '章节目录与开头，便于你再决定读哪一节。',
    parameters: aiObjectSchema({
      'doc_id': aiStrProp('文档 id，如 r03（优先用这个）'),
      'title': aiStrProp('文档标题关键词（没有 doc_id 时用，如「学籍管理」）'),
      'section': aiStrProp('小节标题关键词，如「转专业」'),
    }),
  );

  @override
  Future<AiToolResult> run(AiToolContext ctx, Map<String, dynamic> args) async {
    final a = AiArgs(args);
    final docId = a.optStr('doc_id') ?? a.optStr('docId');
    final title = a.optStr('title');
    final section = a.optStr('section');
    if (a.hasError) return AiToolResult.fail(a.errorText);
    if (docId == null && title == null) {
      return const AiToolResult.fail('需要 doc_id 或 title 至少一个。');
    }

    final RulesCatalog catalog;
    try {
      catalog = await ctx.ref.read(rulesCatalogProvider.future);
    } catch (e) {
      return AiToolResult.fail('规章制度目录加载失败：$e');
    }
    final index = await aiRuleIndexFor(catalog);
    final entry = (docId == null ? null : index.byId(docId)) ??
        (title == null ? null : index.byTitle(title));
    if (entry == null) {
      return AiToolResult.fail(
        '没找到这篇文档（doc_id=${docId ?? '-'}，title=${title ?? '-'}）。'
        '先用 search_rules 检索。',
      );
    }

    final doc = entry.doc;
    final header = '《${doc.title}》'
        '${doc.wenhao == null ? '' : ' ${doc.wenhao}'}'
        '（分类：${doc.group}${doc.year.isEmpty ? '' : '，${doc.year}'}）';

    // 指定小节：模糊匹配小节标题
    if (section != null) {
      final matched = <RuleSection>[];
      for (final s in entry.sections) {
        if (s.path.contains(section)) matched.add(s);
      }
      if (matched.isEmpty) {
        final toc = _toc(entry);
        return AiToolResult.fail(
          '《${doc.title}》里没有标题含「$section」的小节。\n该文档的小节如下：\n$toc',
        );
      }
      final buffer = StringBuffer()
        ..writeln(header)
        ..writeln('小节：${matched.first.path}')
        ..writeln();
      // 同名小节可能有多段（超长被切开），最多拼 3 段
      for (final s in matched.take(3)) {
        buffer.writeln(s.clip(4000));
      }
      return AiToolResult.ok(
        buffer.toString(),
        ui: {'kind': 'rule', 'docId': doc.id, 'title': doc.title},
      );
    }

    // 未指定小节：给目录 + 开头
    final first = entry.sections.first;
    final buffer = StringBuffer()
      ..writeln(header)
      ..writeln('共 ${entry.sections.length} 节。')
      ..writeln()
      ..writeln('章节目录：')
      ..writeln(_toc(entry, limit: 40))
      ..writeln()
      ..writeln('开头部分（${first.path}）：')
      ..writeln(first.clip(2000))
      ..writeln()
      ..writeln('如需某一节全文，用 read_rule(doc_id: "${doc.id}", section: "小节标题")。');

    return AiToolResult.ok(
      buffer.toString(),
      ui: {'kind': 'rule', 'docId': doc.id, 'title': doc.title},
    );
  }

  String _toc(RuleDocIndex entry, {int limit = 60}) {
    final lines = <String>[];
    for (final s in entry.sections.take(limit)) {
      lines.add('- ${s.path}');
    }
    if (entry.sections.length > limit) lines.add('- …（其余省略）');
    return lines.join('\n');
  }
}
