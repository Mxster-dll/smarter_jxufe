/// 对话回答的 Markdown 渲染器。
///
/// 设计要点：
/// - **解析与渲染分离**：结构在 `domain/ai_markdown.dart`（纯 Dart、可单测），
///   本文件只负责把结构画出来；
/// - **整条消息共用一个 `SelectionArea`**：块之间能连着选中、复制，而不是每块各选各的；
/// - **递归在函数里做，不套 widget**：引用块内含块级结构，用一个 `_MdCtx` 往下传
///   就能递归，不必为嵌套再造一个有状态 widget（链接识别器要全局共用一份）。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_markdown.dart';

/// 行内代码 / 代码块用的等宽字体（`pubspec.yaml` 里已注册）。
const String kAiMdMonoFont = 'Cascadia Code';

/// 块与块之间的间距。
const double kAiMdBlockGap = 8;

/// 列表每层缩进。
const double kAiMdListIndent = 18;

/// 把一段 markdown 渲染成 widget。
///
/// [baseStyle] 是正文字号/行高/颜色等基线；标题、行内码、引用都在它之上派生。
class AiMarkdownView extends StatefulWidget {
  final String source;
  final TextStyle baseStyle;

  /// 点击链接的回调；`null` = 链接只做样式区分（不注册手势，避免空点击）。
  final void Function(String url)? onTapLink;

  const AiMarkdownView({
    super.key,
    required this.source,
    required this.baseStyle,
    this.onTapLink,
  });

  @override
  State<AiMarkdownView> createState() => _AiMarkdownViewState();
}

/// 链接手势识别器池。
///
/// 为什么要有这个：`TextSpan.recognizer` 需要在 span 被替换后释放，而流式回答**每个
/// token 都会重建**一遍 span —— 若在 `build` 里 `TapGestureRecognizer()` 新建，会以
/// 每秒几十个的速度泄漏。这里按 URL 缓存，一帧里同一个链接复用同一个识别器；回调也
/// 不写死，每次 build 刷新，所以 `onTapLink` 变化也能生效。
class _LinkRegistry {
  void Function(String url)? onTap;
  final Map<String, TapGestureRecognizer> _byUrl = {};

  TapGestureRecognizer of(String url) => _byUrl.putIfAbsent(url, () {
    final r = TapGestureRecognizer();
    r.onTap = () => onTap?.call(url);
    return r;
  });

  void dispose() {
    for (final r in _byUrl.values) {
      r.dispose();
    }
    _byUrl.clear();
  }
}

/// 渲染上下文（递归时往下传，避免每层都重新算一遍主题色）。
class _MdCtx {
  final BuildContext context;
  final TextStyle base;
  final _LinkRegistry links;
  final ColorScheme scheme;

  const _MdCtx({
    required this.context,
    required this.base,
    required this.links,
    required this.scheme,
  });

  _MdCtx withStyle(TextStyle style) =>
      _MdCtx(context: context, base: style, links: links, scheme: scheme);
}

// 解析缓存（只留最近一条）。
//
// 流式回答每来一个 token 就是一次重建，同一段文字还可能在同一帧里被布局多次；
// 缓存一条就能把这部分重复解析省掉。缓存只影响性能，不影响正确性。
String? _memoSource;
List<AiMdBlock>? _memoBlocks;

List<AiMdBlock> _blocksOf(String source) {
  if (_memoSource == source && _memoBlocks != null) return _memoBlocks!;
  final blocks = parseAiMarkdown(source);
  _memoSource = source;
  _memoBlocks = blocks;
  return blocks;
}

class _AiMarkdownViewState extends State<AiMarkdownView> {
  final _LinkRegistry _links = _LinkRegistry();

  @override
  void dispose() {
    _links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _links.onTap = widget.onTapLink;
    final blocks = _blocksOf(widget.source);
    if (blocks.isEmpty) return const SizedBox.shrink();

    final ctx = _MdCtx(
      context: context,
      base: widget.baseStyle,
      links: _links,
      scheme: Theme.of(context).colorScheme,
    );
    return SelectionArea(child: _renderBlocks(ctx, blocks));
  }
}

// ────────────────────────────── 块级 ──────────────────────────────

Widget _renderBlocks(_MdCtx ctx, List<AiMdBlock> blocks) {
  final children = <Widget>[];
  for (var i = 0; i < blocks.length; i++) {
    children.add(
      Padding(
        padding: EdgeInsets.only(
          top: i == 0 ? 0 : (blocks[i] is AiMdHeading ? 10 : kAiMdBlockGap),
        ),
        child: _renderBlock(ctx, blocks[i]),
      ),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}

Widget _renderBlock(_MdCtx ctx, AiMdBlock block) => switch (block) {
  AiMdHeading(:final level, :final spans) => _heading(ctx, level, spans),
  AiMdPara(:final spans) => _text(ctx, spans, ctx.base),
  AiMdCodeBlock() => _codeBlock(ctx, block),
  AiMdList() => _list(ctx, block),
  AiMdQuote() => _quote(ctx, block),
  AiMdTable() => _table(ctx, block),
  AiMdRule() => _rule(ctx),
};

Widget _text(_MdCtx ctx, List<AiMdSpan> spans, TextStyle style, [TextAlign? align]) =>
    Text.rich(
      TextSpan(style: style, children: _inline(ctx, spans, style)),
      style: style,
      textAlign: align,
    );

Widget _heading(_MdCtx ctx, int level, List<AiMdSpan> spans) {
  final size = switch (level) {
    1 => 19.0,
    2 => 17.0,
    3 => 15.5,
    _ => 14.8,
  };
  final style = ctx.base.copyWith(
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: 1.35,
  );
  return _text(ctx, spans, style);
}

Widget _rule(_MdCtx ctx) => Container(
  height: 1,
  width: double.infinity,
  color: AppColors.hairline(ctx.context, 0.6),
);

Widget _codeBlock(_MdCtx ctx, AiMdCodeBlock block) {
  final scheme = ctx.scheme;
  final mono = ctx.base.copyWith(
    fontFamily: kAiMdMonoFont,
    fontSize: (ctx.base.fontSize ?? 14) - 1.5,
    height: 1.5,
  );
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: AppColors.fill(ctx.context),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.hairline(ctx.context, 0.6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  block.language.isEmpty ? '代码' : block.language,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: '复制代码',
                iconSize: 15,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                padding: EdgeInsets.zero,
                color: scheme.onSurfaceVariant,
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: block.code));
                  if (!ctx.context.mounted) return;
                  ScaffoldMessenger.maybeOf(ctx.context)?.showSnackBar(
                    const SnackBar(
                      content: Text('代码已复制'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(block.code, style: mono, softWrap: false),
          ),
        ),
      ],
    ),
  );
}

Widget _list(_MdCtx ctx, AiMdList block) {
  final style = ctx.base;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final item in block.items) _listItem(ctx, item, style),
    ],
  );
}

Widget _listItem(_MdCtx ctx, AiMdListItem item, TextStyle style) {
  final marker = item.checked != null
      ? Icon(
          item.checked! ? Icons.check_box : Icons.check_box_outline_blank,
          size: 15,
          color: item.checked!
              ? ctx.scheme.primary
              : ctx.scheme.onSurfaceVariant,
        )
      : Text(
          item.ordered
              ? '${item.number}.'
              : switch (item.depth) {
                  0 => '•',
                  1 => '◦',
                  _ => '▪',
                },
          style: style.copyWith(color: ctx.scheme.onSurfaceVariant),
        );

  return Padding(
    padding: EdgeInsets.only(
      left: item.depth * kAiMdListIndent,
      top: 2,
      bottom: 2,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 20, child: Align(alignment: Alignment.topLeft, child: marker)),
        const SizedBox(width: 6),
        Expanded(child: _text(ctx, item.spans, style)),
      ],
    ),
  );
}

Widget _quote(_MdCtx ctx, AiMdQuote block) {
  final muted = ctx.base.copyWith(color: ctx.scheme.onSurfaceVariant);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
    decoration: BoxDecoration(
      color: AppColors.tint(ctx.context, ctx.scheme.onSurfaceVariant, 0.05),
      border: Border(
        left: BorderSide(
          color: AppColors.tintBorder(ctx.context, ctx.scheme.primary, 0.55),
          width: 3,
        ),
      ),
    ),
    child: _renderBlocks(
      ctx.withStyle(muted),
      block.blocks.isEmpty ? const [AiMdPara([])] : block.blocks,
    ),
  );
}

Widget _table(_MdCtx ctx, AiMdTable block) {
  final style = ctx.base.copyWith(fontSize: (ctx.base.fontSize ?? 14) - 1);
  final border = TableBorder.all(
    color: AppColors.hairline(ctx.context, 0.6),
    width: 1,
  );

  TextAlign alignOf(int col) => switch (block.align[col]) {
    AiMdAlign.center => TextAlign.center,
    AiMdAlign.right => TextAlign.right,
    AiMdAlign.left => TextAlign.left,
  };

  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: border,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (var r = 0; r < block.rows.length; r++)
          TableRow(
            decoration: r == 0
                ? BoxDecoration(color: AppColors.fill(ctx.context))
                : null,
            children: [
              for (var c = 0; c < block.columnCount; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: _text(
                    ctx,
                    block.rows[r][c],
                    r == 0
                        ? style.copyWith(fontWeight: FontWeight.w700)
                        : style,
                    alignOf(c),
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

// ────────────────────────────── 内联 ──────────────────────────────

List<InlineSpan> _inline(_MdCtx ctx, List<AiMdSpan> spans, TextStyle style) => [
  for (final s in spans) _span(ctx, s, style),
];

/// ⚠ 派生样式**显式往下传**，不依赖引擎的 span 样式继承：
/// `TextStyle.copyWith` 产出的是「字段全满」的样式，嵌套时子 span 会整体覆盖父 span，
/// 靠继承会丢掉父级的粗体/字号。所以这里每一层都把算好的完整样式传给子层。
InlineSpan _span(_MdCtx ctx, AiMdSpan span, TextStyle style) {
  switch (span) {
    case AiMdText(:final text):
      return TextSpan(text: text, style: style);
    case AiMdStrong(:final children):
      final s = style.copyWith(fontWeight: FontWeight.w700);
      return TextSpan(style: s, children: _inline(ctx, children, s));
    case AiMdEm(:final children):
      final s = style.copyWith(fontStyle: FontStyle.italic);
      return TextSpan(style: s, children: _inline(ctx, children, s));
    case AiMdStrike(:final children):
      final s = style.copyWith(decoration: TextDecoration.lineThrough);
      return TextSpan(style: s, children: _inline(ctx, children, s));
    case AiMdCode(:final text):
      return TextSpan(
        text: text,
        style: style.copyWith(
          fontFamily: kAiMdMonoFont,
          fontSize: (style.fontSize ?? 14) - 1,
          backgroundColor: AppColors.fill(ctx.context),
        ),
      );
    case AiMdLink(:final label, :final url):
      return TextSpan(
        text: label,
        style: style.copyWith(
          color: ctx.scheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.tintBorder(ctx.context, ctx.scheme.primary, 0.5),
        ),
        recognizer: ctx.links.onTap == null ? null : ctx.links.of(url),
      );
  }
}
