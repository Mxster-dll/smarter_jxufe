/// AI 回答的 Markdown 解析 / 渲染 + 空卡片回归。
///
/// 用户 2026-09-19 原话：「我希望支持markdown渲染，同时AI回复中偶尔会出现空卡片」
/// —— 本文件同时守这两件事：
/// - markdown：结构断言走纯函数（`parseAiMarkdown` / `parseAiInline`），
///   画出来对不对走 widget 断言（真的加粗了 / 真的等宽了 / 真的画了表格）；
/// - 空卡片：`aiShouldRenderMessage` 的规则 + 一条**端到端**的对话页回归
///   （喂进「带 toolCalls 的空 assistant 消息」，断言它没有被画成气泡）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ai/data/ai_chat_controller.dart';
import 'package:smarter_jxufe/features/ai/data/ai_settings_store.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_config.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_markdown.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_message.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_chat_screen.dart';
import 'package:smarter_jxufe/features/ai/presentation/widgets/ai_markdown_view.dart';

const _ready = AiConfig(
  id: 'p1',
  name: '宿舍 DeepSeek',
  presetId: 'deepseek',
  baseUrl: 'https://api.deepseek.com/v1',
  model: 'deepseek-chat',
  apiKey: 'sk-1234567890abcd',
);

const _base = TextStyle(fontSize: 14.5, height: 1.6);

AiChatMessage _msg(
  AiRole role,
  String content, {
  List<AiToolCall> calls = const [],
  bool isError = false,
}) => AiChatMessage(
  id: 'm-${role.wire}-${content.hashCode}',
  role: role,
  content: content,
  toolCalls: calls,
  createdAt: DateTime(2026, 9, 19),
  isError: isError,
);

/// 把一棵 widget 树里所有 `TextSpan` 摊平 —— 用来断言「真的加粗了 / 真的等宽了」，
/// 而不是只断言「文字出现了」。
///
/// ⚠ 不要用 `span.visitChildren(...)` 做这件事：`TextSpan.visitChildren` 在
/// `text != null` 时**会拿 span 自己回调一次**，递归写下去就是无限递归（实测栈溢出）。
List<TextSpan> _allSpans(WidgetTester tester) {
  final out = <TextSpan>[];
  void walk(InlineSpan span) {
    if (span is! TextSpan) return;
    out.add(span);
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child);
    }
  }

  for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(w.text);
  }
  return out;
}

TextSpan? _spanWithText(WidgetTester tester, String text) {
  for (final s in _allSpans(tester)) {
    if (s.text == text) return s;
  }
  return null;
}

Future<void> _pumpMd(
  WidgetTester tester,
  String source, {
  void Function(String url)? onTapLink,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiMarkdownView(
            source: source,
            baseStyle: _base,
            onTapLink: onTapLink,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ────────────────────────────── 块级解析 ──────────────────────────────

  group('块级解析', () {
    test('单换行保留成换行（对话场景刻意不折叠成空格）', () {
      final blocks = parseAiMarkdown('第一行\n第二行');
      expect(blocks, hasLength(1));
      expect(blocks.single, isA<AiMdPara>());
      expect(aiMdSpansText((blocks.single as AiMdPara).spans), '第一行\n第二行');
    });

    test('空行分段', () {
      final blocks = parseAiMarkdown('甲\n\n乙');
      expect(blocks, hasLength(2));
      expect(aiMdBlocksText(blocks).trim().split('\n'), ['甲', '乙']);
    });

    test('标题 1–6 级、剥掉尾部 #；「#没有空格」不算标题', () {
      final blocks = parseAiMarkdown('# 一级\n## 二级 ##\n###### 六级\n#不是标题');
      expect((blocks[0] as AiMdHeading).level, 1);
      expect(aiMdSpansText((blocks[0] as AiMdHeading).spans), '一级');
      expect((blocks[1] as AiMdHeading).level, 2);
      expect(aiMdSpansText((blocks[1] as AiMdHeading).spans), '二级');
      expect((blocks[2] as AiMdHeading).level, 6);
      expect(blocks[3], isA<AiMdPara>());
    });

    test('围栏代码块：认语言、代码原样保留（内部标记不解析、缩进不丢）', () {
      final blocks = parseAiMarkdown(
        '```dart\nfinal a = **1**;\n   缩进两格\n```',
      );
      expect(blocks, hasLength(1));
      final code = blocks.single as AiMdCodeBlock;
      expect(code.language, 'dart');
      expect(code.code, 'final a = **1**;\n   缩进两格');
    });

    test('未闭合的围栏（流式中途）吃到结尾且不抛异常', () {
      final blocks = parseAiMarkdown('说明\n```\npart');
      expect(blocks[0], isA<AiMdPara>());
      expect((blocks[1] as AiMdCodeBlock).code, 'part');
    });

    test('无序列表：嵌套深度按缩进栈推导（2 空格与 4 空格都算下一层）', () {
      final blocks = parseAiMarkdown('- a\n  - b\n    - c\n- d');
      final list = blocks.single as AiMdList;
      expect(list.items.map((e) => e.depth), [0, 1, 2, 0]);
      expect(list.items.map((e) => aiMdSpansText(e.spans)), ['a', 'b', 'c', 'd']);
    });

    test('任务列表：- [ ] / - [x] 变勾选态', () {
      final list = parseAiMarkdown('- [ ] 未做\n- [x] 已做').single as AiMdList;
      expect(list.items[0].checked, isFalse);
      expect(list.items[1].checked, isTrue);
      expect(aiMdSpansText(list.items[1].spans), '已做');
    });

    test('有序列表保留原始序号', () {
      final list = parseAiMarkdown('3. 第三\n4. 第四').single as AiMdList;
      expect(list.items.first.ordered, isTrue);
      expect(list.items.first.number, 3);
      expect(list.items.last.number, 4);
    });

    test('引用块递归解析内部块级结构', () {
      final blocks = parseAiMarkdown('> ## 小标题\n> 引用正文');
      final quote = blocks.single as AiMdQuote;
      expect(quote.blocks, hasLength(2));
      expect(quote.blocks[0], isA<AiMdHeading>());
      expect(quote.blocks[1], isA<AiMdPara>());
    });

    test('分隔线三种写法都认，且不与无序列表混淆', () {
      for (final s in ['---', '***', '- - -', '___']) {
        expect(parseAiMarkdown(s).single, isA<AiMdRule>(), reason: s);
      }
      expect(parseAiMarkdown('- 正常项').single, isA<AiMdList>());
    });

    test('管道表格：表头 / 对齐 / 缺列补齐 / 格内内联', () {
      final blocks = parseAiMarkdown(
        '| 课程 | 分数 |\n| --- | ---: |\n| 高数 | **95** |\n| 英语 |',
      );
      final table = blocks.single as AiMdTable;
      expect(table.columnCount, 2);
      expect(table.align, [AiMdAlign.left, AiMdAlign.right]);
      expect(table.rows, hasLength(3));
      expect(aiMdSpansText(table.rows[1][0]), '高数');
      expect(table.rows[1][1].single, isA<AiMdStrong>());
      expect(aiMdSpansText(table.rows[2][1]), ''); // 缺的列补成空
    });

    test('表格对齐列三种都认', () {
      final table =
          parseAiMarkdown('| a | b | c |\n| :-- | :-: | --: |\n| 1 | 2 | 3 |')
              .single as AiMdTable;
      expect(table.align, [
        AiMdAlign.left,
        AiMdAlign.center,
        AiMdAlign.right,
      ]);
    });

    test('空输入 / 纯空白 → 空列表（不造出空段落）', () {
      expect(parseAiMarkdown(''), isEmpty);
      expect(parseAiMarkdown('   \n\n \t '), isEmpty);
      expect(parseAiInline(''), isEmpty);
    });

    test('任意半截语法都不抛异常（流式每个 token 都会重解析）', () {
      for (final s in [
        '**',
        '`',
        '~~',
        '[',
        '![x](',
        '|',
        '#',
        '>',
        '```',
        '| a |\n| --- |',
        '> > >',
        '- ',
        '***',
      ]) {
        expect(() => parseAiMarkdown(s), returnsNormally, reason: s);
      }
    });
  });

  // ────────────────────────────── 内联解析 ──────────────────────────────

  group('内联解析', () {
    test('粗体 / 斜体 / 删除线', () {
      expect(parseAiInline('**粗**').single, isA<AiMdStrong>());
      expect(parseAiInline('*斜*').single, isA<AiMdEm>());
      expect(parseAiInline('~~删~~').single, isA<AiMdStrike>());
      expect(aiMdSpansText(parseAiInline('**粗**')), '粗');
    });

    test('行内码：内容原样、不解析内部标记', () {
      final spans = parseAiInline('用 `get_grades` 查成绩');
      expect(aiMdSpansText(spans), '用 get_grades 查成绩');
      expect(spans.whereType<AiMdCode>().single.text, 'get_grades');
    });

    test('双反引号包裹含反引号的代码（``a`b``）', () {
      final spans = parseAiInline('``a`b``');
      expect((spans.single as AiMdCode).text, 'a`b');
    });

    test('⚠ `_` 只在词边界生效：snake_case / 工具名不被撕成斜体', () {
      const src = '工具 get_my_schedule 和 snake_case 都别动';
      expect(aiMdSpansText(parseAiInline(src)), src);
      expect(parseAiInline(src).whereType<AiMdEm>(), isEmpty);
      // 但成对、有边界的中文下划线仍然生效
      expect(parseAiInline('_斜体_').single, isA<AiMdEm>());
    });

    test('⚠ `*` 也不吃乘法写法（`2 * 3 * 4` 不斜体）', () {
      expect(parseAiInline('2 * 3 * 4').whereType<AiMdEm>(), isEmpty);
      expect(aiMdSpansText(parseAiInline('2 * 3 * 4')), '2 * 3 * 4');
    });

    test('链接与自动链接', () {
      final link = parseAiInline('[成绩页](https://jwxt.jxufe.edu.cn/a)').single;
      expect(link, isA<AiMdLink>());
      expect((link as AiMdLink).label, '成绩页');
      expect(link.url, 'https://jwxt.jxufe.edu.cn/a');

      final auto = parseAiInline('<https://example.com/x>').single as AiMdLink;
      expect(auto.url, 'https://example.com/x');
      expect(auto.label, 'https://example.com/x');
    });

    test('链接的可选标题被丢掉', () {
      final link =
          parseAiInline('[a](https://example.com "标题")').single as AiMdLink;
      expect(link.url, 'https://example.com');
    });

    test('反斜杠转义', () {
      expect(aiMdSpansText(parseAiInline(r'\*不是斜体\*')), '*不是斜体*');
      expect(parseAiInline(r'\*不是斜体\*').whereType<AiMdEm>(), isEmpty);
    });

    test('未闭合的强调标记原样保留（不吃掉后面的字）', () {
      expect(aiMdSpansText(parseAiInline('**还没闭合')), '**还没闭合');
      expect(aiMdSpansText(parseAiInline('`没闭合的码')), '`没闭合的码');
    });

    test('嵌套：粗体里带行内码', () {
      final strong = parseAiInline('**看 `x` 值**').single as AiMdStrong;
      expect(strong.children.whereType<AiMdCode>().single.text, 'x');
    });
  });

  // ────────────────────────────── 渲染 ──────────────────────────────

  group('渲染', () {
    testWidgets('标题 / 段落 / 粗体 / 行内码 / 列表 / 代码块都画出来了', (tester) async {
      await _pumpMd(tester, '''
## 你的课表

**周一** 有 `2` 门课

- 高等数学
- 大学英语

```dart
final a = 1;
```
''');

      expect(find.text('你的课表'), findsOneWidget);
      expect(find.text('周一 有 2 门课'), findsOneWidget);
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('大学英语'), findsOneWidget);

      // 标题真的加粗、字号更大
      final heading = _spanWithText(tester, '你的课表')!;
      expect(heading.style?.fontWeight, FontWeight.w700);
      expect(heading.style!.fontSize! > _base.fontSize!, isTrue);

      // **粗体** 真的变成 w700，而不是把星号打出来
      expect(_spanWithText(tester, '**周一**'), isNull);
      expect(_spanWithText(tester, '周一')?.style?.fontWeight, FontWeight.w700);

      // 行内码真的换等宽字体
      expect(_spanWithText(tester, '2')?.style?.fontFamily, kAiMdMonoFont);

      // 代码块：语言标注 + 内容 + 复制按钮
      expect(find.text('dart'), findsOneWidget);
      expect(find.text('final a = 1;'), findsOneWidget);
      expect(find.byTooltip('复制代码'), findsOneWidget);
    });

    testWidgets('行内码的 ` 包裹符不会被显示出来', (tester) async {
      await _pumpMd(tester, '用 `get_grades` 查成绩');
      expect(find.text('用 get_grades 查成绩'), findsOneWidget);
      expect(find.textContaining('`'), findsNothing);
    });

    testWidgets('表格画成 Table，表头加粗', (tester) async {
      await _pumpMd(tester, '| 课程 | 分数 |\n| --- | ---: |\n| 高数 | 95 |');
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('课程'), findsOneWidget);
      expect(find.text('高数'), findsOneWidget);
      expect(find.text('95'), findsOneWidget);
      expect(_spanWithText(tester, '课程')?.style?.fontWeight, FontWeight.w700);
      expect(_spanWithText(tester, '高数')?.style?.fontWeight, isNot(FontWeight.w700));
    });

    testWidgets('引用块画出左侧强调条', (tester) async {
      await _pumpMd(tester, '> 这是引用');
      expect(find.text('这是引用'), findsOneWidget);
    });

    testWidgets('任务列表画成勾选框', (tester) async {
      await _pumpMd(tester, '- [x] 已交\n- [ ] 未交');
      expect(find.byIcon(Icons.check_box), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.text('已交'), findsOneWidget);
    });

    testWidgets('链接可点，回调拿到 URL（不是把 markdown 原文显示出来）', (tester) async {
      String? tapped;
      await _pumpMd(
        tester,
        '[这里](https://example.com/a)',
        onTapLink: (url) => tapped = url,
      );

      expect(find.text('这里'), findsOneWidget);
      expect(find.textContaining('example.com'), findsNothing);

      await tester.tap(find.text('这里'));
      await tester.pumpAndSettle();
      expect(tapped, 'https://example.com/a');
    });

    testWidgets('没挂 onTapLink 时链接不注册手势（不空点）', (tester) async {
      await _pumpMd(tester, '[这里](https://example.com/a)');
      expect(find.text('这里'), findsOneWidget);
    });

    testWidgets('空回答不画任何东西（空卡片的最后一道防线）', (tester) async {
      await _pumpMd(tester, '');
      expect(find.byType(Text), findsNothing);
      expect(find.byType(SelectionArea), findsNothing);

      await _pumpMd(tester, '   \n\n  ');
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('整条消息共用一个 SelectionArea（块之间能连着选中）', (tester) async {
      await _pumpMd(tester, '# 标题\n\n正文\n\n- 项');
      expect(find.byType(SelectionArea), findsOneWidget);
    });
  });

  // ────────────────────────────── 空卡片回归 ──────────────────────────────

  group('空卡片守卫', () {
    test('⚠ 带工具调用的空 assistant 消息不渲染 —— 这正是「空卡片」的根因', () {
      final m = _msg(
        AiRole.assistant,
        '',
        calls: [const AiToolCall(id: 'c1', name: 'get_grades')],
      );
      expect(aiShouldRenderMessage(m), isFalse);
    });

    test('纯空白的回答也不渲染', () {
      expect(aiShouldRenderMessage(_msg(AiRole.assistant, '  \n\t ')), isFalse);
    });

    test('有文字的回答照常渲染（工具轮次里模型附了话也一样）', () {
      expect(aiShouldRenderMessage(_msg(AiRole.assistant, '我来查一下。')), isTrue);
      expect(
        aiShouldRenderMessage(
          _msg(
            AiRole.assistant,
            '我来查一下。',
            calls: [const AiToolCall(id: 'c1', name: 'get_grades')],
          ),
        ),
        isTrue,
      );
    });

    test('用户消息渲染', () {
      expect(aiShouldRenderMessage(_msg(AiRole.user, '今天谁没课')), isTrue);
    });

    test('tool / system 不直接渲染（工具由轨迹条代表）', () {
      expect(aiShouldRenderMessage(_msg(AiRole.tool, '{"ok":true}')), isFalse);
      expect(aiShouldRenderMessage(_msg(AiRole.system, '系统提示词')), isFalse);
    });

    test('本地提示（「已停止」「已达轮次上限」）仍要渲染', () {
      expect(
        aiShouldRenderMessage(_msg(AiRole.assistant, '（已停止）', isError: true)),
        isTrue,
      );
    });

    testWidgets('⚠ 端到端：工具轮次的空 assistant 消息在对话页里不产生气泡', (tester) async {
      // 把「一次带工具调用的问答」真实的消息序列喂给对话页：
      // user → assistant(空 content + toolCalls) → tool 结果 → assistant(最终回答)
      // 其中第 2 条以前会画出一张只有内边距的空卡片。
      final store = AiSettingsStore(persist: false);
      await store.save(const AiSettings(profiles: [_ready], activeId: 'p1'));

      final container = ProviderContainer(
        overrides: [
          aiSettingsStoreProvider.overrideWith((ref) => store),
          aiChatControllerProvider.overrideWith(
            (ref) => _FakeChatController(ref, [
              _msg(AiRole.user, '我这学期有哪些课？'),
              _msg(
                AiRole.assistant,
                '', // ← 空串：协议要求配 toolCalls 原样发回，模型没附文字
                calls: [const AiToolCall(id: 'c1', name: 'get_my_schedule')],
              ),
              _msg(AiRole.tool, '高等数学 周一 1-2 节'),
              _msg(AiRole.assistant, '这学期你有 2 门课：\n\n- 高等数学'),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AiChatScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // 只有**最终回答**那一条长出了 markdown 视图；空的工具轮次没有气泡
      expect(find.byType(AiMarkdownView), findsOneWidget);
      // 用户气泡 + 最终回答都在（回答此刻已被渲染成结构，不再是 markdown 原文）
      expect(find.text('我这学期有哪些课？'), findsOneWidget);
      expect(find.text('这学期你有 2 门课：'), findsOneWidget);
      expect(find.text('高等数学'), findsOneWidget);
      // tool 结果不直接展示（只在轨迹条里）
      expect(find.text('高等数学 周一 1-2 节'), findsNothing);
    });
  });
}

/// 只覆写「读」的几个 getter 的假控制器 —— 用来把一段**指定**的消息历史喂给对话页
/// （真控制器的 `_messages` 是私有的，只能靠 Hive 历史回灌，而 widget 测试的假异步
/// 时钟上 Hive 真实文件 IO 永不完成）。
class _FakeChatController extends AiChatController {
  _FakeChatController(super.ref, this._list);

  final List<AiChatMessage> _list;

  @override
  List<AiChatMessage> get messages => _list;

  @override
  List<AiToolTrace> get traces => const [];

  @override
  bool get busy => false;
}
