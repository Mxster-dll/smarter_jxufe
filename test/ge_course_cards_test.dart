/// 分数估计 · 课程详情页改版（用户 2026-09-26）的界面守卫。
///
/// 用户口径（原话）：
/// - 「成绩估计功能里的总加权页面不要显示：计入明细：教务已出成绩 26 门（57 学分）、
///   本模块估计 ө 门（0 学分）/ 逐课贡献 = 分数 × 学分 ÷ 总学分… / 教务侧为成绩页全部
///   已出成绩课程… / 本模块课程的学分优先取本专业培养方案… / 已按成绩页口径排除：… /
///   另有 10 门未填期末，暂未计入合计」；
/// - 「1. 总加权平均（现有）（但是要改正一点，那就是既要计算计入当前课程的加权，也要
///   计算没有当前课程的加权，主要显示的计入当前课程的，然后显示一个胶囊，表示此门课
///   带来的提升或减少）」；
/// - 「2. 当前课程成绩现状（…不仅显示占比，还要显示各部分成绩；然后此部分还要支持
///   1.给出预估期末成绩，计算最终成绩；2.给出预估总评，反推期末成绩范围）；
///   2、3 中间要显示一个标题"平时成绩"；3. 作业成绩卡片（让用户选择，可以直接取消此
///   卡片，也就是说这门课没有作业）；4-x. 若干平时成绩构成卡片，是用户自己添加的，
///   添加按钮也是一个卡片，显示在此部分的最后一个」；
/// - 二轮自定义回答：「不默认显示『作业』了，而是重新设计添加平时分的浮窗，并在这里
///   添加一个作业项」→ 作业不再是预置卡片，而是浮窗里的一个**类型**。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_chaoxing_sync.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_engine.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_models.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_course_cards.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_dialogs.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_summary_card.dart';

// ---- 构造件 ----

GePart p({
  String id = 'p1',
  String name = '作业',
  GePartMode mode = GePartMode.score,
  int target = 100,
  int current = 0,
  double score = 0,
  double cap = 15,
  String note = '',
  String source = '',
}) => GePart(
  id: id,
  name: name,
  mode: mode,
  target: target,
  current: current,
  score: score,
  cap: cap,
  note: note,
  source: source,
);

GeCourse c({
  String id = 'c1',
  String name = '数据结构与算法',
  double dailyPercent = 30,
  double credits = 3,
  List<GePart> parts = const [],
  double? finalScore,
}) => GeCourse(
  id: id,
  name: name,
  dailyPercent: dailyPercent,
  credits: credits,
  parts: parts,
  finalScore: finalScore,
);

/// 平时 30 分：作业 15（学习通，已得 13.9）+ 考勤 10（负计数）+ 表现 5（正计数）。
List<GePart> stdParts() => [
  p(
    id: 'hw',
    name: '作业',
    mode: GePartMode.score,
    target: 100,
    score: 92.5,
    cap: 15,
    source: gePartSourceChaoxing,
  ),
  p(
    id: 'att',
    name: '考勤',
    mode: GePartMode.down,
    target: 16,
    current: 16,
    cap: 10,
  ),
  p(
    id: 'perf',
    name: '课堂表现',
    mode: GePartMode.up,
    target: 10,
    current: 5,
    cap: 5,
  ),
];

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 只留代码行（`///` 与 `//` 注释一律剥掉）—— 说明性注释里会引用被删掉的旧文案。
String codeOnly(String src) => src
    .split('\n')
    .map((line) => line.trimLeft().startsWith('//') ? '' : line)
    .join('\n');

String read(String path) => File(path).readAsStringSync();

void main() {
  group('卡片 1 · 总加权平均：既算含本课也算不含本课', () {
    final summary = geWeightedSummary(const [
      GeWeightItem(name: '高数', score: 90, credits: 3, fromGrades: true),
      GeWeightItem(name: '英语', score: 80, credits: 2, fromGrades: true),
      GeWeightItem(name: '本课', score: 70, credits: 1),
    ]);

    testWidgets('已计入：主数字是含本课的平均，右侧 Δ 胶囊 + 副行给出不含本课', (tester) async {
      // 含本课 = (90×3 + 80×2 + 95×1) / 6 = 87.5；不含本课 = (270+160)/5 = 86。
      final withCourse = geWeightedSummary(const [
        GeWeightItem(name: '高数', score: 90, credits: 3, fromGrades: true),
        GeWeightItem(name: '英语', score: 80, credits: 2, fromGrades: true),
        GeWeightItem(name: '本课', score: 95, credits: 1),
      ]);
      final without = geWeightedSummary(const [
        GeWeightItem(name: '高数', score: 90, credits: 3, fromGrades: true),
        GeWeightItem(name: '英语', score: 80, credits: 2, fromGrades: true),
      ]).average;
      await tester.pumpWidget(
        host(
          GeWeightedSummaryCard(
            summary: withCourse,
            withoutCourseAverage: without,
          ),
        ),
      );
      expect(find.text('87.5'), findsOneWidget);
      expect(find.text('▲ +1.5 本课'), findsOneWidget);
      expect(find.textContaining('不含本课 86 分'), findsOneWidget);
      // ⚠ 用户点名要删的六段说明一个都不许回来。
      for (final gone in const [
        '计入明细',
        '逐课贡献',
        '教务侧为成绩页',
        '培养方案',
        '已按成绩页口径排除',
        '未填期末，暂未计入合计',
      ]) {
        expect(find.textContaining(gone), findsNothing, reason: gone);
      }
    });

    testWidgets('降低：Δ 胶囊带负号', (tester) async {
      final low = geWeightedSummary(const [
        GeWeightItem(name: '高数', score: 90, credits: 3, fromGrades: true),
        GeWeightItem(name: '本课', score: 40, credits: 3),
      ]);
      await tester.pumpWidget(
        host(GeWeightedSummaryCard(summary: low, withoutCourseAverage: 90)),
      );
      expect(find.text('▼ −25 本课'), findsOneWidget);
    });

    testWidgets('未计入：出灰色原因胶囊，不出 Δ / 不含本课', (tester) async {
      await tester.pumpWidget(
        host(
          GeWeightedSummaryCard(
            summary: summary,
            withoutCourseAverage: 86,
            courseExcludedNote: '未填期末，暂未计入',
          ),
        ),
      );
      expect(find.text('未填期末，暂未计入'), findsOneWidget);
      // 没计入就不写「不含本课」（那时含/不含是同一个数），也不出 Δ。
      expect(find.textContaining('不含本课'), findsNothing);
      expect(find.text('教务已出 2 门 + 估计 1 门'), findsOneWidget);
      expect(find.textContaining('▲'), findsNothing);
      expect(find.textContaining('▼'), findsNothing);
    });

    testWidgets('列表页：两个对比参数都不传 → 既不显示 Δ 也不显示不含本课', (tester) async {
      await tester.pumpWidget(host(GeWeightedSummaryCard(summary: summary)));
      expect(find.textContaining('本课'), findsNothing);
      expect(find.text('教务已出 2 门 + 估计 1 门'), findsOneWidget);
    });
  });

  group('卡片 2 · 当前课程成绩现状', () {
    testWidgets('占比 + 各部分成绩 + 期末预估算总评 + 目标反推期末范围', (tester) async {
      final course = c(parts: stdParts(), finalScore: 80);
      final calc = geCalc(course);
      var finalCalls = <double?>[];
      await tester.pumpWidget(
        host(
          GeCourseStatusCard(
            course: course,
            calc: calc,
            finalCtrl: TextEditingController(text: '80'),
            goalCtrl: TextEditingController(text: '85'),
            onFinalChanged: finalCalls.add,
            onGoalChanged: () {},
            onOpenRatio: () {},
          ),
        ),
      );
      expect(find.text('当前课程成绩现状'), findsOneWidget);
      expect(find.text('3 学分 · 平时 30% / 期末 70%'), findsOneWidget);
      // 卡片标题就是改占比的入口（不必再跑到别处）。
      expect(find.byIcon(Icons.tune), findsWidgets);
      // 两块折算 + 逐分项一行读数。
      expect(find.text('平时'), findsOneWidget);
      expect(find.textContaining('均分 '), findsOneWidget);
      expect(find.text('期末'), findsOneWidget);
      expect(find.textContaining('预估 80 × 70%'), findsOneWidget);
      expect(find.text('各部分'), findsOneWidget);
      expect(find.text('作业 '), findsOneWidget);
      expect(find.text('13.88/15'), findsOneWidget); // 92.5% × 15
      expect(find.text('考勤 '), findsOneWidget);
      expect(find.text('10/10'), findsOneWidget);
      // 总评：92.5×0.15 + 10 + 2.5 = 26.375 → 均分 87.92 × 30% = 26.38
      // + 期末 80 × 70% = 56 → 82.38
      expect(find.text('82.4'), findsOneWidget);
      expect(find.text('估计总评（满分 100）'), findsOneWidget);
      // 目标 85 的反推：期末需 ≥ (85 − 26.375) / 0.7 = 83.75 分。
      expect(find.text('预估期末 · 算最终成绩'), findsOneWidget);
      expect(find.text('预估总评 · 反推期末范围'), findsOneWidget);
      expect(find.textContaining('期末需 ≥ 83.8 分'), findsOneWidget);
      expect(find.textContaining('（即 83.8 ~ 100 分）'), findsOneWidget);
      // 预设 chip 走回调（输入框由页面持有，这里只验回调）。
      // ⚠ '90' 在「期末预估」与「目标总评」两行各有一枚，取树上先出现的期末那枚。
      await tester.tap(find.widgetWithText(ActionChip, '90').first);
      await tester.pump();
      expect(finalCalls, [90.0]);
      // 「清空」只在已填期末时出现，且回传 null。
      await tester.tap(find.widgetWithText(ActionChip, '清空'));
      await tester.pump();
      expect(finalCalls, [90.0, null]);
    });

    testWidgets('未填期末：出总评区间与「期末 0~100」读法', (tester) async {
      final course = c(parts: stdParts());
      await tester.pumpWidget(
        host(
          GeCourseStatusCard(
            course: course,
            calc: geCalc(course),
            finalCtrl: TextEditingController(),
            goalCtrl: TextEditingController(text: '85'),
            onFinalChanged: (_) {},
            onGoalChanged: () {},
            onOpenRatio: () {},
          ),
        ),
      );
      expect(find.text('未填 · 按 0 ~ 100 计'), findsOneWidget);
      expect(find.text('总评区间（期末 0~100）'), findsOneWidget);
      expect(find.textContaining('26.4 ~ 96.4'), findsOneWidget);
    });

    testWidgets('没有分项：反推区提示先添加分项', (tester) async {
      final course = c();
      await tester.pumpWidget(
        host(
          GeCourseStatusCard(
            course: course,
            calc: geCalc(course),
            finalCtrl: TextEditingController(),
            goalCtrl: TextEditingController(text: '85'),
            onFinalChanged: (_) {},
            onGoalChanged: () {},
            onOpenRatio: () {},
          ),
        ),
      );
      expect(find.textContaining('先添加平时分项'), findsOneWidget);
      expect(find.text('各部分'), findsNothing);
    });
  });

  group('卡片 3 / 4-x · 分项卡与添加卡', () {
    testWidgets('作业分项：学习通芯片 + 占比读数 + 点卡改配置', (tester) async {
      final course = c(parts: stdParts());
      final hw = course.parts.first;
      var taps = 0;
      await tester.pumpWidget(
        host(
          GePartCard(
            course: course,
            part: hw,
            chaoxingCount: 4,
            chaoxingHint: '作业均分来自学习通（2026-09-26 10:00）',
            onTap: () => taps++,
            onBump: (_) {},
          ),
        ),
      );
      expect(find.text('作业'), findsOneWidget);
      expect(find.text('学习通同步'), findsOneWidget);
      expect(find.textContaining('学习通作业 4 条 · 均分 92.5'), findsOneWidget);
      expect(find.textContaining('占平时 50%（总评 15%）'), findsOneWidget);
      // 直接分数项没有步进器，只有「点击修改得分」。
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      await tester.tap(find.text('作业'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('计数分项：步进器回调 +1 / −1', (tester) async {
      final course = c(parts: stdParts());
      final perf = course.parts.last;
      final bumps = <int>[];
      await tester.pumpWidget(
        host(
          GePartCard(
            course: course,
            part: perf,
            onTap: () {},
            onBump: bumps.add,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();
      expect(bumps, [1, -1]);
      expect(find.text('已完成 5 / 10'), findsOneWidget);
    });

    testWidgets('添加卡：文案 + 点击回调；空课时带用法说明', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(GeAddPartCard(onTap: () => taps++, showEmptyHint: true)),
      );
      expect(find.text('添加平时分项'), findsOneWidget);
      expect(find.textContaining('作业 / 考勤 / 课堂表现'), findsOneWidget);
      expect(find.textContaining('还没有分项'), findsOneWidget);
      await tester.tap(find.text('添加平时分项'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('添加平时分项浮窗：类型预设（含「作业」）', () {
    Future<void> open(WidgetTester tester, {GePart? part}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showGePartDialog(context, part: part),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('新建：出类型芯片，选「作业」= 直接分数 + 满分 100 + 学习通同步开', (tester) async {
      await open(tester);
      expect(find.text('添加平时分项'), findsOneWidget);
      expect(find.text('类型'), findsOneWidget);
      for (final preset in gePartPresets) {
        expect(
          find.widgetWithText(ChoiceChip, preset.label),
          findsOneWidget,
          reason: preset.label,
        );
      }
      await tester.tap(find.widgetWithText(ChoiceChip, '作业'));
      await tester.pumpAndSettle();
      final nameField = tester.widget<TextField>(find.byType(TextField).first);
      expect(nameField.controller!.text, '作业');
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      // 「直接分数」档被选中、满分 100。
      final segment = tester.widget<SegmentedButton<GePartMode>>(
        find.byType(SegmentedButton<GePartMode>),
      );
      expect(segment.selected, {GePartMode.score});
      expect(find.widgetWithText(TextField, '100'), findsOneWidget);
    });

    testWidgets('选「作业」保存 → 分项带 chaoxing 来源（= 会被自动同步）', (tester) async {
      GePartOutcome? out;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => out = await showGePartDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '作业'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(out, isNotNull);
      final saved = out!.part;
      expect(saved.name, '作业');
      expect(saved.mode, GePartMode.score);
      expect(saved.target, 100);
      expect(saved.cap, 10);
      expect(saved.source, gePartSourceChaoxing);
      // 直接分数项不存计数。
      expect(saved.current, 0);
    });

    testWidgets('选「考勤」= 负计数 16 次、分值 5、不接学习通', (tester) async {
      GePartOutcome? out;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => out = await showGePartDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '考勤'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = out!.part;
      expect(saved.name, '考勤');
      expect(saved.mode, GePartMode.down);
      expect(saved.target, 16);
      expect(saved.current, 16);
      expect(saved.cap, 5);
      expect(saved.source, '');
    });

    testWidgets('编辑已有分项：不出现类型芯片（避免一键覆盖用户配置）', (tester) async {
      await open(
        tester,
        part: p(name: '实验报告', mode: GePartMode.score, cap: 20),
      );
      expect(find.text('编辑分项'), findsOneWidget);
      expect(find.text('类型'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('删除分项'), findsOneWidget);
    });
  });

  group('源码守卫', () {
    test('详情页 = 卡片 1/2 + 小节标题 + 分项卡 + 添加卡，旧四张卡不得复活', () {
      final src = codeOnly(
        read('lib/features/score_estimate/presentation/course_detail_screen.dart'),
      );
      for (final must in const [
        'GeWeightedSummaryCard(',
        'GeCourseStatusCard(',
        "text: '平时成绩'",
        'GePartCard(',
        'GeAddPartCard(',
        'withoutCourseAverage: _withoutCourseAverage()',
        'courseExcludedNote: _courseExcludedNote()',
      ]) {
        expect(src.contains(must), isTrue, reason: must);
      }
      for (final gone in const [
        '_ratioCard()',
        '_estimateCard(',
        '_partsCard()',
        '_goalCard(',
        '_partTile(',
        '_chaoxingPartLine(',
      ]) {
        expect(src.contains(gone), isFalse, reason: gone);
      }
      // 「作业」卡不再默认存在：分项列表由用户数据决定，详情页里不许出现写死的作业卡。
      expect(src.contains('GeChaoxingHomeworkCard'), isFalse);
    });

    test('总加权卡的六段说明文案不得复活（含列表页共用的那一份）', () {
      final src = codeOnly(
        read('lib/features/score_estimate/presentation/ge_summary_card.dart'),
      );
      for (final gone in const [
        '计入明细',
        '逐课贡献',
        '教务侧为成绩页',
        '培养方案',
        '已按成绩页口径排除',
        '暂未计入合计',
        'pendingCount',
        'planMajorName',
      ]) {
        expect(src.contains(gone), isFalse, reason: gone);
      }
      // 必须保留的三件（用户没让删的）。
      expect(src.contains("'总加权平均'"), isTrue);
      expect(src.contains('教务已出 '), isTrue);
      expect(src.contains('不含本课 '), isTrue);
    });

    test('类型预设里有且只有一个「作业」，且它接学习通自动同步', () {
      final hw = gePartPresets.where((x) => x.label == '作业').toList();
      expect(hw, hasLength(1));
      expect(hw.single.chaoxing, isTrue);
      expect(hw.single.mode, GePartMode.score);
      expect(hw.single.name, '作业');
      // 预设列表 = 浮窗里唯一的类型来源（不许各写一份）。
      final dialogs = read('lib/features/score_estimate/presentation/ge_dialogs.dart');
      expect(dialogs.contains('const List<GePartPreset> gePartPresets = ['), isTrue);
      expect(dialogs.contains('for (final p in gePartPresets)'), isTrue);
    });
  });
}
