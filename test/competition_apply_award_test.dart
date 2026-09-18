/// 学科竞赛「申请条目右侧的此项加分」——解析口径 + 界面守卫。
///
/// 用户 2026-09-18 原话：「我希望学科竞赛申请页面，要在每个申请条目右侧显示此项加分」。
///
/// 数据来源（**申请列表本身没有奖项与分值列**，只能按行拉详情）：
/// - `_competition_xd_detail.html`（2026-09-18 抓，现行版：首项占位 = `无`、选项不带赛别前缀、
///   带「个人得分」）；
/// - `_competition_apply_detail.html`（2026-09-16 抓，旧版申请详情：首项 = `请设置奖项`、
///   选项带 `【国赛】` 前缀）；
/// - `_competition_publicity_detail.html` / `_competition_publicity_team_detail.html`（校赛，
///   后者是团队记录 —— **没有「个人得分」字段**）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/comprehensive_service/data/anti_corruption/competition_parser.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/models/competition.dart';
import 'package:smarter_jxufe/features/comprehensive_service/data/providers/competition_providers.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/competition_screen.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/competition_widgets.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

String _source(String path) => File(path).readAsStringSync();

const _screenPath =
    'lib/features/comprehensive_service/presentation/competition_screen.dart';
const _widgetsPath =
    'lib/features/comprehensive_service/presentation/competition_widgets.dart';
const _datasourcePath =
    'lib/features/comprehensive_service/data/datasource/'
    'competition_remote_datasource.dart';

/// 一档分值表的合成片段（结构与官网一致：label 与控件同在一个 `div` 里 ——
/// `parseCompetitionDetail` 靠 `label.parent.querySelector(...)` 取控件，包错层就取不到）。
String _field(String label, String control) =>
    '<div class="col-xs-4 col-md-4"><label for="name">$label</label>$control</div>';

/// 已评定的合成页：官网把 `selected` 写在评定过的那一档上，「个人得分」才是实得分。
String _scoredHtml({
  String award = '【省赛】一等奖',
  String selected = '一等奖(4)分',
  String personal = '4分',
}) =>
    '<form id="inputForm">'
    '${_field('学生提交的奖项', '<input type="text" readonly="readonly" value="$award"/>')}'
    '${_field('最终获得奖项', '<select id="credit_id" disabled>'
        '<option value="">无</option>'
        '<option value="1" >三等奖(2)分</option>'
        '<option value="2" >二等奖(3)分</option>'
        '<option value="3" selected>$selected</option>'
        '<option value="4" >特等奖(5)分</option></select>')}'
    '${_field('个人得分', '<input type="text" readonly="readonly" value="$personal"/>')}'
    '</form>';

void main() {
  group('分值文案（competitionScoreText）', () {
    test('整数不带小数，小数最多 2 位且去尾零', () {
      expect(competitionScoreText(3), '3 分');
      expect(competitionScoreText(15), '15 分');
      expect(competitionScoreText(1.5), '1.5 分');
      expect(competitionScoreText(0.1), '0.1 分');
      expect(competitionScoreText(0), '0 分');
      expect(competitionScoreText(2.25), '2.25 分');
    });
  });

  group('官方分值文案解析（competitionScoreValue）', () {
    test('从文案里取数字；占位项返回 null', () {
      expect(competitionScoreValue('三等奖(2)分'), 2);
      expect(competitionScoreValue('特等奖(15)分'), 15);
      expect(competitionScoreValue('参与未获奖(0.1)分'), 0.1);
      expect(competitionScoreValue('0分'), 0);
      expect(competitionScoreValue('2'), 2);
      expect(competitionScoreValue('无'), isNull);
      expect(competitionScoreValue('请设置奖项'), isNull);
      expect(competitionScoreValue(''), isNull);
    });
  });

  group('奖项文案归一（competitionAwardKey）', () {
    test('去赛别前缀、去分值后缀、去空白', () {
      expect(competitionAwardKey('【国赛】三等奖'), '三等奖');
      expect(competitionAwardKey('【校赛】 参与未获奖 '), '参与未获奖');
      expect(competitionAwardKey('【国赛】三等奖(5)分'), '三等奖');
      expect(competitionAwardKey('一等奖（4）分'), '一等奖');
      expect(competitionAwardKey('无'), '无');
    });
  });

  group('该赛别的分值表（parseCompetitionAwardOptions）', () {
    test('现行版：首项占位「无」，选项不带赛别前缀', () {
      final options = parseCompetitionAwardOptions(
        _fixture('_competition_xd_detail.html'),
      );
      expect(options.map((o) => o.label), ['无', '三等奖', '二等奖', '一等奖', '特等奖']);
      expect(options.map((o) => o.score), [0, 5, 8, 10, 15]);
      expect(options.every((o) => !o.selected), isTrue);
      expect(options.first.selectable, isFalse);
      expect(
        options.where((o) => o.selectable).map((o) => o.label),
        ['三等奖', '二等奖', '一等奖', '特等奖'],
      );
    });

    test('旧版：首项「请设置奖项」+ 选项带 【国赛】 前缀 → 一样能归一', () {
      final options = parseCompetitionAwardOptions(
        _fixture('_competition_apply_detail.html'),
      );
      expect(options.first.label, '请设置奖项');
      expect(options.first.selectable, isFalse);
      expect(options.where((o) => o.selectable).map((o) => o.label), [
        '三等奖',
        '二等奖',
        '一等奖',
        '特等奖',
      ]);
      expect(options[1].score, 5);
      expect(options.last.score, 15);
    });

    test('校赛（有 0.1 分的「参与未获奖」档）', () {
      final options = parseCompetitionAwardOptions(
        _fixture('_competition_publicity_detail.html'),
      );
      expect(options.where((o) => o.selectable).map((o) => o.score), [
        2,
        1.5,
        1,
        0.5,
        0.1,
      ]);
      expect(
        competitionOptionScoreFor('参与未获奖', options),
        0.1,
      );
    });

    test('结构不符 → 空表（界面只是不显示加分，不报错）', () {
      expect(parseCompetitionAwardOptions('<html><body>没有下拉</body></html>'), isEmpty);
      expect(parseCompetitionAwardOptions(''), isEmpty);
    });
  });

  group('一条记录的加分（parseCompetitionApplyAward）', () {
    test('未评定：用申报奖项按该赛别标准算，个人得分 0 不算数', () {
      final award = parseCompetitionApplyAward(
        _fixture('_competition_xd_detail.html'),
      );
      expect(award.submitted.level, '国赛');
      expect(award.submitted.award, '三等奖');
      expect(award.granted.isEmpty, isTrue);
      expect(award.personalScore, 0);
      expect(award.scored, isFalse);
      expect(award.submittedScore, 5);
      expect(award.score, 5);
      expect(competitionScoreText(award.score!), '5 分');
      expect(award.displayAward.label, '国赛 · 三等奖');
      expect(award.tiers, hasLength(4));
    });

    test('旧版申请详情（选项带赛别前缀）同样算出分值', () {
      final award = parseCompetitionApplyAward(
        _fixture('_competition_apply_detail.html'),
      );
      expect(award.submitted.label, '国赛 · 三等奖');
      expect(award.score, 5);
      expect(award.scored, isFalse);
    });

    test('团队记录没有「个人得分」→ 回落到申报奖项分值', () {
      final award = parseCompetitionApplyAward(
        _fixture('_competition_publicity_team_detail.html'),
      );
      expect(award.personalScore, isNull);
      expect(award.submitted.label, '校赛 · 一等奖');
      expect(award.score, 1.5);
    });

    test('已评定：个人得分优先，最终奖项的赛别沿用申报的赛别', () {
      final award = parseCompetitionApplyAward(_scoredHtml());
      expect(award.scored, isTrue);
      expect(award.granted.level, '省赛');
      expect(award.granted.award, '一等奖');
      expect(award.grantedScore, 4);
      expect(award.personalScore, 4);
      expect(award.score, 4);
      expect(award.displayAward.label, '省赛 · 一等奖');
      // 分值表里被选中的那一档也能独自反推出分值（个人得分为空时用）。
      final noPersonal = parseCompetitionApplyAward(_scoredHtml(personal: ''));
      expect(noPersonal.personalScore, isNull);
      expect(noPersonal.scored, isTrue);
      expect(noPersonal.score, 4);
    });

    test('解析不到任何东西 → empty（胶囊整块不显示）', () {
      final award = parseCompetitionApplyAward('<html></html>');
      expect(award.hasData, isFalse);
      expect(award.score, isNull);
      expect(award.scored, isFalse);
      expect(CompetitionApplyAward.empty.hasData, isFalse);
    });
  });

  group('界面：申请条目右侧的加分胶囊', () {
    const applyA = CompetitionApply(
      id: 199962,
      year: '2026',
      studentId: '0000000',
      studentName: '某同学',
      gameName: '蓝桥杯全国软件和信息技术专业人才大赛',
      type: CompetitionType.individual,
      applyTime: '2026-07-06',
      status: '未审批',
    );
    const applyB = CompetitionApply(
      id: 199960,
      year: '2026',
      studentId: '0000000',
      studentName: '某同学',
      gameName: '全国大学生数学建模竞赛',
      type: CompetitionType.individual,
      applyTime: '2026-07-06',
      status: '通过',
    );

    CompetitionApplyAward awardOf({double personal = 0, double? granted}) =>
        CompetitionApplyAward(
          submitted: const CompetitionAwardLevel(level: '国赛', award: '一等奖'),
          granted: granted == null
              ? CompetitionAwardLevel.empty
              : const CompetitionAwardLevel(level: '国赛', award: '一等奖'),
          submittedScore: 10,
          grantedScore: granted,
          personalScore: personal,
          options: const [
            CompetitionAwardOption(label: '无', score: 0),
            CompetitionAwardOption(label: '三等奖', score: 5),
            CompetitionAwardOption(label: '二等奖', score: 8),
            CompetitionAwardOption(label: '一等奖', score: 10),
            CompetitionAwardOption(label: '特等奖', score: 15),
          ],
        );

    Widget app(List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: CompetitionScreen()),
    );

    testWidgets('未评定 → 右侧「预计 10 分」，点开是该赛别的分值标准', (tester) async {
      final asked = <({int id, CompetitionType type})>[];
      await tester.pumpWidget(
        app([
          competitionApplyListProvider.overrideWith(
            (ref, query) => const CompetitionPage(
              items: [applyA],
              page: 1,
              totalPages: 1,
            ),
          ),
          competitionPublicityListProvider.overrideWith(
            (ref, query) => CompetitionPage.empty<CompetitionPublicity>(),
          ),
          competitionApplyAwardProvider.overrideWith((ref, key) {
            asked.add(key);
            return awardOf();
          }),
        ]),
      );
      await tester.pumpAndSettle();

      expect(asked, [(id: applyA.id, type: applyA.type)]);
      expect(find.text('预计 10 分'), findsOneWidget);
      expect(find.text('未审批'), findsOneWidget);

      await tester.tap(find.text('预计 10 分'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('competitionAwardSheet')), findsOneWidget);
      expect(find.text('该赛别的分值标准'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('competitionAwardSheetScore')))
            .data,
        '10 分',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('competitionAwardSheetSubmitted')))
            .data,
        '国赛 · 一等奖',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('competitionAwardSheetGranted')))
            .data,
        '待评定',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('competitionAwardSheetPersonal')))
            .data,
        '0 分（待评定）',
      );
      // 四档分值（「无」不算一档）。
      expect(find.byKey(const Key('competitionAwardOption-一等奖')), findsOneWidget);
      expect(find.byKey(const Key('competitionAwardOption-无')), findsNothing);
      expect(find.text('特等奖'), findsOneWidget);
      expect(find.text('15 分'), findsOneWidget);
    });

    testWidgets('已评定 → 显示实得分（不再是「预计」）', (tester) async {
      await tester.pumpWidget(
        app([
          competitionApplyListProvider.overrideWith(
            (ref, query) => const CompetitionPage(
              items: [applyA],
              page: 1,
              totalPages: 1,
            ),
          ),
          competitionPublicityListProvider.overrideWith(
            (ref, query) => CompetitionPage.empty<CompetitionPublicity>(),
          ),
          competitionApplyAwardProvider.overrideWith(
            (ref, key) => awardOf(personal: 10, granted: 10),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('10 分'), findsOneWidget);
      expect(find.text('预计 10 分'), findsNothing);

      await tester.tap(find.text('10 分'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('competitionAwardSheetPersonal')))
            .data,
        '10 分',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('competitionAwardSheetGranted')))
            .data,
        '国赛 · 一等奖',
      );
    });

    testWidgets('两条申请各自显示自己的加分', (tester) async {
      await tester.pumpWidget(
        app([
          competitionApplyListProvider.overrideWith(
            (ref, query) => const CompetitionPage(
              items: [applyA, applyB],
              page: 1,
              totalPages: 1,
            ),
          ),
          competitionPublicityListProvider.overrideWith(
            (ref, query) => CompetitionPage.empty<CompetitionPublicity>(),
          ),
          competitionApplyAwardProvider.overrideWith(
            (ref, key) => key.id == applyA.id
                ? awardOf()
                : CompetitionApplyAward(
                    submitted: const CompetitionAwardLevel(
                      level: '省赛',
                      award: '一等奖',
                    ),
                    submittedScore: 4,
                    personalScore: 0,
                    options: const [
                      CompetitionAwardOption(label: '一等奖', score: 4),
                    ],
                  ),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('预计 10 分'), findsOneWidget);
      expect(find.text('预计 4 分'), findsOneWidget);
    });

    testWidgets('读取中显示占位「…」（不闪空、不跳版）', (tester) async {
      await tester.pumpWidget(
        app([
          competitionApplyListProvider.overrideWith(
            (ref, query) => const CompetitionPage(
              items: [applyA],
              page: 1,
              totalPages: 1,
            ),
          ),
          competitionPublicityListProvider.overrideWith(
            (ref, query) => CompetitionPage.empty<CompetitionPublicity>(),
          ),
          // 永不完成的 Future = 一直 loading。
          competitionApplyAwardProvider.overrideWith(
            (ref, key) => Completer<CompetitionApplyAward>().future,
          ),
        ]),
      );
      await tester.pump();
      expect(find.text('…'), findsOneWidget);
      expect(find.text(applyA.gameName), findsOneWidget);
    });

    testWidgets('取不到 → 整颗不显示，卡片其余内容照常', (tester) async {
      await tester.pumpWidget(
        app([
          competitionApplyListProvider.overrideWith(
            (ref, query) => const CompetitionPage(
              items: [applyA],
              page: 1,
              totalPages: 1,
            ),
          ),
          competitionPublicityListProvider.overrideWith(
            (ref, query) => CompetitionPage.empty<CompetitionPublicity>(),
          ),
          competitionApplyAwardProvider.overrideWith(
            (ref, key) =>
                Future<CompetitionApplyAward>.error(Exception('详情拉取失败')),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('…'), findsNothing);
      expect(find.text(applyA.gameName), findsOneWidget);
      expect(find.text('未审批'), findsOneWidget);
    });
  });

  group('源码守卫', () {
    test('申请卡挂上了加分胶囊 + 弹层', () {
      final screen = _source(_screenPath);
      expect(
        screen.contains(
          'competitionApplyAwardProvider((id: apply.id, type: apply.type))',
        ),
        isTrue,
        reason: '加分要按行拉，key 必须是这条申请（id + 个人/团队）',
      );
      expect(screen.contains('CompetitionApplyAwardChip('), isTrue);
      expect(screen.contains('showCompetitionApplyAwardSheet('), isTrue);
      // 胶囊排在审批状态胶囊之前（同一行的右侧）。
      expect(
        screen.indexOf('_applyAwardChip(apply)'),
        lessThan(screen.indexOf('CompetitionStatusChip(status: apply.status)')),
      );
    });

    test('加分走 xd_detail（申请详情端点已失效），解析器单独有入口', () {
      final datasource = _source(_datasourcePath);
      expect(datasource.contains('Future<CompetitionApplyAward> fetchApplyAward('), isTrue);
      expect(datasource.contains('parseCompetitionApplyAward(body)'), isTrue);
      expect(
        datasource.contains('publicityDetailPath'),
        isTrue,
        reason: 'fetchApplyAward 必须走公示详情端点（同 id 同记录）',
      );
    });

    test('申请详情端点失效时回落到公示详情（顺带修好空白详情页）', () {
      final datasource = _source(_datasourcePath);
      expect(datasource.contains('detail.fields.isNotEmpty'), isTrue);
      expect(datasource.contains('_fetchPublicityDetailBody('), isTrue);
    });

    test('胶囊与弹层不许硬编码颜色（走 AppColors / FeatureColors）', () {
      final widgets = _source(_widgetsPath);
      // 只查本次新增的那一段（文件里原有的 CompetitionTypeChip 有登记过的字面量）。
      final start = widgets.indexOf('申请条目右侧的**加分**胶囊');
      expect(start, greaterThan(0));
      final added = widgets.substring(start);
      expect(added.contains('Color(0x'), isFalse);
      expect(added.contains('AppColors.tint('), isTrue);
      expect(added.contains('fp(context).competition'), isTrue);
      expect(added.contains('AppColors.success(context)'), isTrue);
    });
  });
}
