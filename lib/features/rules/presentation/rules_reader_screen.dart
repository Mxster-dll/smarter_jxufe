import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/JxufeTheme.dart';
import '../domain/doc_blocks.dart';
import '../domain/rule_doc.dart';
import '../data/rules_repository.dart';
import 'widgets/doc_table.dart';
import 'widgets/notice_card.dart';

/// 规则文件阅读器：按文档模板深度定制渲染。
///
/// - regulation：红头通知卡（可折叠）+ 标题横幅 + 章/条 + 正文 + 表格；
/// - catalog：官方标题 + 分类大表分区（一、二、三类…），目录侧栏直达分区。
class RulesReaderScreen extends ConsumerStatefulWidget {
  final RuleDoc doc;

  const RulesReaderScreen({super.key, required this.doc});

  @override
  ConsumerState<RulesReaderScreen> createState() => _RulesReaderScreenState();
}

class _RulesReaderScreenState extends ConsumerState<RulesReaderScreen> {
  /// 静态共享：版本切换（pushReplacement）后字号保持用户设置。
  static double _font = 16.5;
  final _keys = <String, GlobalKey>{};

  static final _chapterBody = RegExp(r'^第[一二三四五六七八九十百零]+章');
  static final _clauseBody = RegExp(r'^第[一二三四五六七八九十百零]+条');
  static final _dateBody = RegExp(r'^\d{4}年\d{1,2}月\d{1,2}日$');
  static final _wenhaoBody = RegExp(r'^.{0,24}〔.{1,20}〕.*号$');
  static final _subEnum = RegExp(r'^（[一二三四五六七八九十]+）');
  static final _subNum = RegExp(r'^\d{1,2}[.、]');
  static final _sectionBody = RegExp(r'^[一二三四五六七八九十]+、');

  /// 「第一章总则」→「第一章 总则」；已是「第一章 总则」则保持。
  static String _prettyChapter(String t) {
    final m = RegExp(r'^(第[一二三四五六七八九十百零]+章)(.*)$').firstMatch(t);
    if (m == null) return t;
    final rest = m.group(2)!.trim();
    return rest.isEmpty ? m.group(1)! : '${m.group(1)} $rest';
  }

  GlobalKey _keyFor(String label) =>
      _keys.putIfAbsent(label, () => GlobalKey(debugLabel: label));

  void _jumpTo(String label) {
    final key = _keys[label];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  Future<void> _openPdf() async {
    try {
      await openOriginalPdf(widget.doc);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开原件 PDF：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final articleAsync = ref.watch(rulesArticleProvider(widget.doc));
    final catalog = ref.watch(rulesCatalogProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.doc.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton.icon(
            onPressed: _openPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
            label: const Text('原件'),
          ),
          IconButton(
            tooltip: '减小字号',
            onPressed: _font > 13.5
                ? () => setState(() => _font -= 1)
                : null,
            icon: const Icon(Icons.text_decrease),
          ),
          IconButton(
            tooltip: '增大字号',
            onPressed: _font < 22
                ? () => setState(() => _font += 1)
                : null,
            icon: const Icon(Icons.text_increase),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: articleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('文档解析失败：$e',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ),
        data: (article) => _buildBody(article, catalog),
      ),
    );
  }

  Widget _buildBody(DocArticle article, RulesCatalog? catalog) {
    final toc = <(String, String)>[]; // (label, kind) kind: chapter/section
    final List<Widget> content;
    if (widget.doc.template == RuleTemplate.catalog) {
      final parts = _buildCatalog(article);
      toc.addAll(parts.$1);
      content = parts.$2;
    } else {
      final parts = _buildRegulation(article);
      toc.addAll(parts.$1);
      content = parts.$2;
    }
    // 拆分文档的互链：附件 → 所属通知（顶部）；通知 → 附件清单（尾部）。
    if (catalog != null) {
      final kind = widget.doc.kind;
      if (kind == RuleDocKind.attachment) {
        final parent = widget.doc.parentId == null
            ? null
            : catalog.byId(widget.doc.parentId!);
        if (parent != null) {
          content.insert(0, _parentNoticeBar(parent));
        }
      } else if (kind == RuleDocKind.notice) {
        final children = catalog.childrenOf(widget.doc.id);
        if (children.isNotEmpty) content.add(_attachmentLinksCard(children));
      }
    }

    final family = catalog?.familyOf(widget.doc.id);
    final layout = LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000 && toc.length >= 2;
        final listView = ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 80),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: content,
                  ),
                ),
              ),
            ),
          ],
        );
        if (!wide) return listView;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 236,
              margin: const EdgeInsets.only(top: 14, left: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _tocList(toc, sideRail: true),
            ),
            Expanded(child: listView),
          ],
        );
      },
    );

    // 同名家族 >1 成员 → 顶部版本条（点击切换，pushReplacement 保持返回栈）。
    if (family == null || family.members.length < 2) return layout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _versionBar(family),
        Expanded(child: layout),
      ],
    );
  }

  /// 家族版本条：横向滚动的版本胶囊，当前文档高亮，点击切换阅读文档。
  Widget _versionBar(RuleFamily family) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant, width: 0.6),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                family.name,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 1,
                height: 16,
                color: scheme.outlineVariant,
              ),
              for (final m in family.members) ...[
                const SizedBox(width: 8),
                _versionChip(family, m),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _versionChip(RuleFamily family, FamilyMember m) {
    final scheme = Theme.of(context).colorScheme;
    final active = m.doc.id == widget.doc.id;
    final label = Text(
      m.label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: active
            ? null
            : () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => RulesReaderScreen(doc: m.doc),
                  ),
                );
              },
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? scheme.primary
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: label,
        ),
      ),
    );
  }

  Widget _tocList(List<(String, String)> toc, {bool sideRail = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Text(
            '目录',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1,
            ),
          ),
        ),
        Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        if (sideRail)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: toc.length,
              itemBuilder: (context, i) {
                final (label, _) = toc[i];
                return _tocTile(label);
              },
            ),
          )
        else
          Flexible(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [for (final (label, _) in toc) _tocTile(label)],
            ),
          ),
      ],
    );
  }

  Widget _tocTile(String label) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(
        label,
        style: const TextStyle(fontSize: 13, height: 1.3),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _jumpTo(label),
    );
  }

  // ---------- 模板一：红头通知 + 办法条文 ----------

  (List<(String, String)>, List<Widget>) _buildRegulation(DocArticle article) {
    final blocks = article.blocks;
    var noticeEnd = blocks.length;
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.kind != BlockKind.heading) continue;
      final isChapter = _chapterBody.hasMatch(b.text);
      final isBigTitle = b.level == 1 &&
          !b.text.contains('通知') &&
          b.text.length >= 8;
      if (isChapter || isBigTitle) {
        noticeEnd = i;
        break;
      }
    }

    final children = <Widget>[];
    final toc = <(String, String)>[];
    if (noticeEnd > 0) {
      children.add(_buildNoticeCard(blocks.sublist(0, noticeEnd)));
      children.add(const SizedBox(height: 18));
    }

    var bannerDone = false;
    var i = noticeEnd;
    while (i < blocks.length) {
      final b = blocks[i];
      if (b.kind == BlockKind.heading) {
        final isDocBanner = !bannerDone &&
            b.level == 1 &&
            b.text.length >= 6 &&
            !b.text.contains('通知') &&
            !_chapterBody.hasMatch(b.text) &&
            !_clauseBody.hasMatch(b.text);
        if (isDocBanner) {
          bannerDone = true;
          String? sub;
          if (i + 1 < blocks.length &&
              blocks[i + 1].kind == BlockKind.para &&
              RegExp(r'^（.+修订.*）$').hasMatch(blocks[i + 1].text)) {
            sub = blocks[i + 1].text;
            i++;
          }
          children.add(_docTitleBanner(b.text, sub: sub));
          i++;
          continue;
        }
        if (_chapterBody.hasMatch(b.text)) {
          final label = _prettyChapter(b.text);
          toc.add((label, 'chapter'));
          children.add(_chapterHeader(label, key: _keyFor(label)));
          i++;
          continue;
        }
        if (_clauseBody.hasMatch(b.text)) {
          children.add(_clauseHeader(b.text));
          i++;
          continue;
        }
        children.add(_genericHead(b.text, b.level));
        i++;
        continue;
      }
      if (b.kind == BlockKind.table) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: DocTable(
            data: b.table!,
            cellFontSize: _font - 3,
          ),
        ));
        i++;
        continue;
      }
      final taken = _paraWidgetsAt(blocks, i, children);
      if (taken == 0) {
        children.add(_bodyPara(b.text));
        i++;
      } else {
        i += taken;
      }
    }
    return (toc, children);
  }

  /// 从 blocks[idx] 起生成段落部件；可消费 1..n 块（落款+日期成组等）。
  /// 返回消费块数；返回 0 表示未识别、需调用方兜底。
  int _paraWidgetsAt(
    List<DocBlock> blocks,
    int idx,
    List<Widget> out, {
    bool inNotice = false,
  }) {
    final text = blocks[idx].text;
    if (inNotice && _wenhaoBody.hasMatch(text) && text.length <= 26) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            color: JxufeTheme.primaryColor,
          ),
        ),
      ));
      return 1;
    }
    if (text == '（此页无正文）') {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _font - 4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ));
      return 1;
    }
    if (_dateBody.hasMatch(text)) return 1; // 日期由前块落款消费
    final unit = _isUnitLine(text);
    if (unit) {
      String date = '';
      var consumed = 1;
      if (idx + 1 < blocks.length &&
          blocks[idx + 1].kind == BlockKind.para &&
          _dateBody.hasMatch(blocks[idx + 1].text)) {
        date = blocks[idx + 1].text;
        consumed = 2;
      }
      out.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: _font - 1,
                fontWeight: FontWeight.w600,
                height: 1.6,
              ),
            ),
            if (date.isNotEmpty)
              Text(date, style: TextStyle(fontSize: _font - 1, height: 1.6)),
          ],
        ),
      ));
      return consumed;
    }
    if (_isRecipient(text)) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: _font - 1,
            fontWeight: FontWeight.w500,
            height: 1.7,
          ),
        ),
      ));
      return 1;
    }
    // 正文段落以「第X条」开头（v3 md 中条号未标题化）→ 内联条号样式。
    // 但「第X条 + 短条名」（如 r09 学分制2021 的"第十三条 考核方式"）与
    // 被标题化的「### 第X条 + 短条名」是同一种条目标题行：若仍按正文
    // 内联两格缩进渲染，会与 ### 版（_clauseHeader 顶格）错位。统一走
    // 同一组件；只有 rest 为长句正文（含标点或超长）才保留内联缩进样式。
    final clauseM = _clauseBody.firstMatch(text);
    if (clauseM != null) {
      final prefix = clauseM.group(0)!;
      final rest = text.substring(prefix.length).trim();
      if (_isClauseTitle(rest)) {
        out.add(_clauseHeader(text));
        return 1;
      }
      out.add(Padding(
        padding: EdgeInsets.only(top: rest.isEmpty ? 10 : 0, bottom: 9),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '\u3000\u3000$prefix',
                style: TextStyle(
                  fontSize: _font,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              if (rest.isNotEmpty)
                TextSpan(
                  text: ' $rest',
                  style: TextStyle(fontSize: _font, height: 1.8),
                ),
            ],
          ),
          textAlign: TextAlign.justify,
        ),
      ));
      return 1;
    }
    if (text.startsWith('注') && (text.length < 3 || text.contains('：'))) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: _font - 3.5,
            height: 1.7,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ));
      return 1;
    }
    if (_isSubHead(text)) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 2),
        child: Text(
          text,
          style: TextStyle(
            fontSize: _font - 1.5,
            fontWeight: FontWeight.w700,
            height: 1.5,
          ),
        ),
      ));
      return 1;
    }
    out.add(_bodyPara(text));
    return 1;
  }

  Widget _buildNoticeCard(List<DocBlock> zone) {
    final children = <Widget>[];
    String? firstTitle;
    for (var i = 0; i < zone.length; i++) {
      final b = zone[i];
      if (b.kind == BlockKind.heading) {
        firstTitle ??= b.text;
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            b.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
        ));
        continue;
      }
      _paraWidgetsAt(zone, i, children, inNotice: true);
    }
    return NoticeCard(header: widget.doc.wenhao ?? firstTitle ?? '发文通知', children: children);
  }

  // ---------- 模板二：分类目录 ----------

  (List<(String, String)>, List<Widget>) _buildCatalog(DocArticle article) {
    final blocks = article.blocks;
    final toc = <(String, String)>[];
    final children = <Widget>[];

    // 官方抬头（前 1..2 个 h1，如「附件」「江西财经大学2024-2025 年学科竞赛目录」）。
    final heads = <String>[];
    for (final b in blocks) {
      if (b.kind == BlockKind.heading && b.level == 1) {
        heads.add(b.text);
      }
    }
    children.add(_catalogBanner(
      headline: heads.isEmpty ? widget.doc.title : heads.last,
      chips: [
        if (heads.length > 1) '附件',
        if (widget.doc.year.isNotEmpty) '${widget.doc.year} 学年/年度',
        if (widget.doc.wenhao != null) widget.doc.wenhao!,
      ],
    ));
    children.add(const SizedBox(height: 14));

    // 分区标题与表格按顺序配对（提取器将标题集中在表前，顺序即对应关系）。
    final sections = <String>[];
    final tables = <TableData>[];
    var paraIntro = <String>[];
    var parasBeforeSections = true;
    for (final b in blocks) {
      if (b.kind == BlockKind.heading) {
        if (b.level >= 2 && _sectionBody.hasMatch(b.text)) {
          sections.add(b.text);
          parasBeforeSections = false;
        }
      } else if (b.kind == BlockKind.table) {
        tables.add(b.table!);
      } else if (b.kind == BlockKind.para) {
        if (parasBeforeSections && sections.isEmpty) {
          paraIntro.add(b.text);
        }
      }
    }

    if (paraIntro.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          paraIntro.join('\n'),
          style: TextStyle(
            fontSize: _font - 3,
            height: 1.8,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ));
    }

    final count = sections.length < tables.length ? sections.length : tables.length;
    final zipped = <(String, TableData)>[];
    if (sections.length == tables.length && count > 0) {
      for (var s = 0; s < sections.length; s++) {
        zipped.add((sections[s], tables[s]));
      }
    } else {
      // 数量不齐时按文档顺序归属最近分区；重名分区追加序号保证键唯一。
      final seen = <String, int>{};
      String unique(String label) {
        final n = seen.update(label, (v) => v + 1, ifAbsent: () => 0);
        return n == 0 ? label : '$label（续$n）';
      }

      var current = '';
      for (final b in blocks) {
        if (b.kind == BlockKind.heading &&
            b.level >= 2 &&
            _sectionBody.hasMatch(b.text)) {
          current = b.text;
        } else if (b.kind == BlockKind.table) {
          final label = current.isEmpty
              ? '竞赛目录'
              : unique(current);
          zipped.add((label, b.table!));
        }
      }
    }

    for (final (label, data) in zipped) {
      toc.add((label, 'section'));
      children.add(_sectionHeader(
        label,
        data,
        key: _keyFor(label),
      ));
      children.add(const SizedBox(height: 8));
      children.add(DocTable(data: data, cellFontSize: _font - 3.5));
      children.add(const SizedBox(height: 20));
    }
    return (toc, children);
  }

  // ---------- 部件工厂 ----------

  Widget _docTitleBanner(String title, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 16),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.5,
              letterSpacing: 1,
            ),
          ),
          if (sub != null)
            Text(
              sub,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _font - 2,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
        ],
      ),
    );
  }

  Widget _catalogBanner({required String headline, List<String> chips = const []}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              height: 1.5,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final c in chips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      c,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chapterHeader(String text, {Key? key}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: key,
      margin: const EdgeInsets.only(top: 18, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clauseHeader(String text) {
    final m = _clauseBody.firstMatch(text);
    final numPart = m?.group(0) ?? '';
    final rest = text.substring(numPart.length).trim();
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.ideographic,
        children: [
          Text(
            numPart,
            style: TextStyle(
              fontSize: _font,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          if (rest.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                rest,
                style: TextStyle(
                  fontSize: _font,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _genericHead(String text, int level) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: level == 1 ? 16.5 : 15,
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _sectionHeader(String label, TableData data, {Key? key}) {
    final scheme = Theme.of(context).colorScheme;
    final rows = data.rows.where((r) => r.isNotEmpty && r.first.isNotEmpty);
    final count = rows.length;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count 项',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyPara(String text) {
    final indent = RegExp(r'^[\u3400-\u9fff“（]').hasMatch(text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        indent ? '\u3000\u3000$text' : text,
        textAlign: TextAlign.justify,
        style: TextStyle(fontSize: _font, height: 1.8),
      ),
    );
  }

  bool _isRecipient(String t) {
    if (t.length > 30 || !(t.endsWith(':') || t.endsWith('：'))) return false;
    return t.contains('各单位') ||
        t.contains('各部门') ||
        t.contains('各学院') ||
        t.startsWith('校属');
  }

  bool _isUnitLine(String t) {
    if (t.isEmpty || t.length > 18) return false;
    if (RegExp(r'[，。；、：？！]').hasMatch(t)) return false;
    return RegExp(r'(大学|办公室|委员会|学院|校长|处|部|室)$').hasMatch(t);
  }

  bool _isClauseTitle(String rest) {
    // 「第X条」后是否为短条名（标题行）而非条文长句正文。
    if (rest.isEmpty) return true;
    if (rest.length > 14) return false;
    // 含句子标点视为正文长句（如"第十三条 考核分为考试和考查两类，"）。
    if (RegExp(r'[，。；：！？、…—]').hasMatch(rest)) return false;
    return true;
  }

  bool _isSubHead(String t) {
    if (t.length > 36 || RegExp(r'[。；！？]').hasMatch(t)) return false;
    if (_subEnum.hasMatch(t) ||
        _subNum.hasMatch(t) ||
        (_clauseBody.hasMatch(t) && t.length <= 24)) {
      return true;
    }
    // 短中文无标点独立行：办法中的条内小标题（如「竞赛奖励标准」）。
    if (t.length <= 12 &&
        !RegExp(r'[0-9A-Za-z，、：（）《》]').hasMatch(t) &&
        !_isUnitLine(t)) {
      return true;
    }
    return false;
  }

  // ---------- 拆分互链：通知 ↔ 附件 ----------

  void _openDoc(RuleDoc doc) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RulesReaderScreen(doc: doc)),
    );
  }

  /// 附件文档顶部的“所属通知”返回条。
  Widget _parentNoticeBar(RuleDoc parent) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: scheme.primary.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.30)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openDoc(parent),
          hoverColor: scheme.primary.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Row(
              children: [
                Icon(Icons.campaign_outlined, size: 17, color: scheme.primary),
                const SizedBox(width: 9),
                Text(
                  '所属通知',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    parent.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
                Icon(Icons.chevron_right, size: 19, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 通知文档尾部的“本通知附件”清单卡。
  Widget _attachmentLinksCard(List<RuleDoc> children) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(
                '本通知的附件',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Theme.of(context).cardTheme.color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                  side: BorderSide(color: scheme.outline),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openDoc(child),
                  hoverColor: scheme.primary.withValues(alpha: 0.04),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Icon(
                            Icons.description_outlined,
                            size: 16,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            child.title,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
