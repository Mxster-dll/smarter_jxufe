// TEMP-QA：无头渲染规则模块视图为 golden PNG（flutter test --update-goldens 后查看）。
// 验证后删除本文件与 test/goldens。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/rules/data/md_parser.dart';
import 'package:smarter_jxufe/features/rules/data/rules_repository.dart';
import 'package:smarter_jxufe/features/rules/domain/doc_blocks.dart';
import 'package:smarter_jxufe/features/rules/domain/rule_doc.dart';
import 'package:smarter_jxufe/features/rules/presentation/rules_home_screen.dart';
import 'package:smarter_jxufe/features/rules/presentation/rules_reader_screen.dart';
import 'package:smarter_jxufe/features/rules/presentation/widgets/doc_table.dart';

const _rule01 = RuleDoc(
  id: 'r01',
  file: 'r01.md',
  pdf: 'r01.pdf',
  title: '关于印发《江西财经大学学科竞赛管理办法（2024年修订）》的通知',
  group: '学科竞赛',
  template: RuleTemplate.regulation,
  kind: RuleDocKind.notice,
  wenhao: '江财字〔2024〕4号',
  year: '2024',
);

const _rule01a = RuleDoc(
  id: 'r01a',
  file: 'r01a.md',
  pdf: 'r01.pdf',
  title: '学科竞赛管理办法（2024年修订）',
  group: '学科竞赛',
  template: RuleTemplate.regulation,
  kind: RuleDocKind.attachment,
  parentId: 'r01',
  wenhao: '江财字〔2024〕4号',
  year: '2024',
);

const _rule05 = RuleDoc(
  id: 'r05',
  file: 'r05.md',
  pdf: 'r05.pdf',
  title: '关于印发《江西财经大学全日制本科生成绩管理办法（2025年修订）》的通知',
  group: '学籍成绩',
  template: RuleTemplate.regulation,
  kind: RuleDocKind.notice,
  wenhao: '江财教务字〔2026〕4号',
  year: '2025',
);

const _rule05a = RuleDoc(
  id: 'r05a',
  file: 'r05a.md',
  pdf: 'r05.pdf',
  title: '全日制本科生成绩管理办法（2025年修订）',
  group: '学籍成绩',
  template: RuleTemplate.regulation,
  kind: RuleDocKind.attachment,
  parentId: 'r05',
  wenhao: '江财教务字〔2026〕4号',
  year: '2025',
);

const _rule02 = RuleDoc(
  id: 'r02',
  file: 'r02.md',
  pdf: 'r02.pdf',
  title: '全日制本科生成绩管理办法（2017年修订通知）',
  group: '学籍成绩',
  template: RuleTemplate.regulation,
  wenhao: '江财教务字〔2017〕8号',
);

const _rule23a = RuleDoc(
  id: 'r23a',
  file: 'r23a.md',
  pdf: 'r23.pdf',
  title: '全日制本科生成绩管理办法',
  group: '学籍成绩',
  template: RuleTemplate.regulation,
  kind: RuleDocKind.attachment,
  parentId: 'r23',
  wenhao: '江财教务字〔2015〕11号',
);

const _rule23 = RuleDoc(
  id: 'r23',
  file: 'r23.md',
  pdf: 'r23.pdf',
  title: '关于印发《江西财经大学全日制本科生成绩管理办法》的通知',
  group: '学籍成绩',
  template: RuleTemplate.regulation,
  kind: RuleDocKind.notice,
  wenhao: '江财教务字〔2015〕11号',
);

/// 最小目录：学科竞赛家族（r01 通知 + r01a 附件）。
const _miniCatalog = RulesCatalog(
  groups: ['学科竞赛'],
  docs: [_rule01, _rule01a],
  families: [
    RuleFamily(
      name: '学科竞赛管理办法',
      group: '学科竞赛',
      defaultId: 'r01a',
      members: [
        FamilyMember(doc: _rule01a, label: '2024年修订'),
        FamilyMember(doc: _rule01, label: '印发通知'),
      ],
    ),
  ],
);

/// 成绩办法多版本目录（5 成员），验证版本条。
const _multiCatalog = RulesCatalog(
  groups: ['学籍成绩'],
  docs: [_rule05, _rule05a, _rule02, _rule23, _rule23a],
  families: [
    RuleFamily(
      name: '全日制本科生成绩管理办法',
      group: '学籍成绩',
      defaultId: 'r05a',
      members: [
        FamilyMember(doc: _rule05a, label: '2025年修订'),
        FamilyMember(doc: _rule05, label: '印发通知'),
        FamilyMember(doc: _rule02, label: '2017年修订通知'),
        FamilyMember(doc: _rule23a, label: '2015年版'),
        FamilyMember(doc: _rule23, label: '2015年印发通知'),
      ],
    ),
  ],
);

Future<void> _loadFont() async {
  final loader = FontLoader('QA')
    ..addFont(rootBundle.load('assets/fonts/LXGWWenKai-Medium.ttf'));
  await loader.load();
}

ThemeData _theme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF008CFF)),
      fontFamily: 'QA',
    );

/// 加载 md 资产并解析为文章（测试字体 + 资产均在 runAsync 内预取）。
Future<DocArticle> _loadArticle(String asset) async {
  await _loadFont();
  final md = await rootBundle.loadString(asset);
  return MdParser().parse(md);
}

/// 真实 reader（catalog/article 全部 override，无真实 IO）。
Widget _reader({
  required DocArticle article,
  required RuleDoc doc,
  RulesCatalog? catalog,
}) {
  return ProviderScope(
    overrides: [
      rulesArticleProvider.overrideWith((ref, d) async => article),
      rulesCatalogProvider.overrideWith(
        (ref) async => catalog ?? _miniCatalog,
      ),
    ],
    child: MaterialApp(
      theme: _theme(),
      home: RulesReaderScreen(doc: doc),
    ),
  );
}

Future<List<TableData>> _tablesOf(String asset) async {
  final article = await _loadArticle(asset);
  return [
    for (final b in article.blocks)
      if (b.kind == BlockKind.table) b.table!,
  ];
}

const _rule20 = RuleDoc(
  id: 'r20',
  file: 'r20.md',
  pdf: 'r20.pdf',
  title: '学科竞赛目录（2024-2025学年）',
  group: '学科竞赛',
  template: RuleTemplate.catalog,
  year: '2024-2025',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('r20 catalog Ⅱ类 table wide', (tester) async {
    await tester.runAsync(() async {
      await _loadFont();
      final tables = await _tablesOf('assets/rules/text/r20.md');
      tester.view.physicalSize = const Size(1500, 2300);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: Scaffold(
            backgroundColor: Colors.white,
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DocTable(data: tables[1], cellFontSize: 13),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    });
    await expectLater(
      find.byType(DocTable),
      matchesGoldenFile('goldens/qa_r20_table2.png'),
    );
  });

  testWidgets('r20 catalog Ⅲ类 table 5col', (tester) async {
    await tester.runAsync(() async {
      await _loadFont();
      final tables = await _tablesOf('assets/rules/text/r20.md');
      tester.view.physicalSize = const Size(1500, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: Scaffold(
            backgroundColor: Colors.white,
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DocTable(data: tables[2], cellFontSize: 13),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    });
    await expectLater(
      find.byType(DocTable),
      matchesGoldenFile('goldens/qa_r20_table3.png'),
    );
  });

  testWidgets('r01 notice reader top', (tester) async {
    final article = await tester.runAsync(() => _loadArticle('assets/rules/text/r01.md'));
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_reader(article: article!, doc: _rule01));
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byType(RulesReaderScreen),
      matchesGoldenFile('goldens/qa_r01_reader_top.png'),
    );
  });

  testWidgets('r01 notice tail shows attachment links', (tester) async {
    final article = await tester.runAsync(() => _loadArticle('assets/rules/text/r01.md'));
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_reader(article: article!, doc: _rule01));
    await tester.pump(const Duration(milliseconds: 100));
    // 滚到底部露出「本通知的附件」卡。
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(RulesReaderScreen),
      matchesGoldenFile('goldens/qa_r01_notice_tail_links.png'),
    );
  });

  testWidgets('r01a attachment reader top (parent notice bar)', (tester) async {
    final article = await tester.runAsync(() => _loadArticle('assets/rules/text/r01a.md'));
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_reader(article: article!, doc: _rule01a));
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byType(RulesReaderScreen),
      matchesGoldenFile('goldens/qa_r01a_reader_top.png'),
    );
  });

  testWidgets('r01 merged big table (colspan+rowspan)', (tester) async {
    await tester.runAsync(() async {
      await _loadFont();
      final tables = await _tablesOf('assets/rules/text/r01a.md');
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: Scaffold(
            backgroundColor: Colors.white,
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DocTable(data: tables[0], cellFontSize: 13),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    });
    await expectLater(
      find.byType(DocTable),
      matchesGoldenFile('goldens/qa_r01_bigtable.png'),
    );
  });

  testWidgets('r01 merged Ⅳ-class table (two-line header)', (tester) async {
    await tester.runAsync(() async {
      await _loadFont();
      final tables = await _tablesOf('assets/rules/text/r01a.md');
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          home: Scaffold(
            backgroundColor: Colors.white,
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DocTable(data: tables[2], cellFontSize: 13),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    });
    await expectLater(
      find.byType(DocTable),
      matchesGoldenFile('goldens/qa_r01_table4.png'),
    );
  });

  testWidgets('home merges same-name docs into one family tile', (tester) async {
    await tester.runAsync(() async {
      await _loadFont();
    });
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final catalog = RulesCatalog(
      groups: const ['学科竞赛', '学籍成绩'],
      docs: const [_rule01, _rule01a, _rule05, _rule05a, _rule02, _rule23, _rule23a],
      families: const [
        RuleFamily(
          name: '学科竞赛管理办法',
          group: '学科竞赛',
          defaultId: 'r01a',
          members: [
            FamilyMember(doc: _rule01a, label: '2024年修订'),
            FamilyMember(doc: _rule01, label: '印发通知'),
          ],
        ),
        RuleFamily(
          name: '全日制本科生成绩管理办法',
          group: '学籍成绩',
          defaultId: 'r05a',
          members: [
            FamilyMember(doc: _rule05a, label: '2025年修订'),
            FamilyMember(doc: _rule05, label: '印发通知'),
            FamilyMember(doc: _rule02, label: '2017年修订通知'),
            FamilyMember(doc: _rule23a, label: '2015年版'),
            FamilyMember(doc: _rule23, label: '2015年印发通知'),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rulesCatalogProvider.overrideWith((ref) async => catalog),
        ],
        child: MaterialApp(
          theme: _theme(),
          home: const RulesHomeScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byType(RulesHomeScreen),
      matchesGoldenFile('goldens/qa_home_family_tiles.png'),
    );
  });

  testWidgets('multi-version reader shows family version bar', (tester) async {
    final article = await tester.runAsync(
      () => _loadArticle('assets/rules/text/r05a.md'),
    );
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _reader(article: article!, doc: _rule05a, catalog: _multiCatalog),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(
      find.byType(RulesReaderScreen),
      matchesGoldenFile('goldens/qa_r05a_version_bar_top.png'),
    );
  });
}
