// 资料库解析守卫（2026-09-17 加，随「推免成绩 / 竞赛奖励」两个新功能）。
//
// 为什么用**真实资产**而不是手写夹具：这两个功能的全部规则都来自
// `assets/rules/` 里的文档，手工抄一份夹具等于把「学校改版后解析失效」这件事
// 从测试里抹掉。这里的每个期望值都是从原文逐字核对过的（见注释里的原文片段）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/competition_award/data/award_standard_parser.dart';
import 'package:smarter_jxufe/features/competition_award/data/competition_catalog_parser.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_standard.dart';
import 'package:smarter_jxufe/features/competition_award/domain/competition_catalog.dart';
import 'package:smarter_jxufe/features/recommendation/data/bonus_catalog_parser.dart';
import 'package:smarter_jxufe/features/recommendation/domain/bonus_catalog.dart';
import 'package:smarter_jxufe/features/rules/data/rule_doc_parse.dart';
import 'package:smarter_jxufe/features/rules/domain/doc_blocks.dart';

String _asset(String name) => File('assets/rules/text/$name').readAsStringSync();

void main() {
  group('资料库文档通用解析（提取噪声与合并单元格）', () {
    test('词内空格必须去掉，但拉丁与中文之间的空格要保留', () {
      // 实测原文：`级 别`、`中国国际大学生创新创 业大赛`、`省优 秀共产党员`
      expect(ruleCleanText('级 别'), '级别');
      expect(ruleCleanText('中国国际大学生创新创 业大赛'), '中国国际大学生创新创业大赛');
      expect(ruleCleanText('省优 秀共产党员'), '省优秀共产党员');
      expect(ruleCleanText('分值/次'), '分值/次');
      // 拉丁 ↔ 中文的空格是正常排版，不能删
      expect(ruleCleanText('ACM-ICPC 国际大学生程序设计竞赛'), 'ACM-ICPC 国际大学生程序设计竞赛');
      expect(ruleCleanText('2026-2027 年学科竞赛目录'), '2026-2027年学科竞赛目录');
    });

    test('金额文本 → 元（表里用 `/` 表示不奖励）', () {
      expect(ruleAmountInYuan('10 万元'), 100000);
      expect(ruleAmountInYuan('3.2 万元'), 32000);
      expect(ruleAmountInYuan('8000 元'), 8000);
      expect(ruleAmountInYuan('4 万元'), 40000);
      expect(ruleAmountInYuan('/'), isNull);
      expect(ruleAmountInYuan('—'), isNull);
      expect(ruleAmountInYuan(''), isNull);
    });

    test('rowspan / colspan 锚格文本要复制到覆盖的每个槽位', () {
      // colspan：`<td colspan="2">组A</td>` → 物理表头两个槽都是「组A」
      final colspan = ruleTableOf(
        TableData(
          headers: const ['奖项', '组A', '', '组B', ''],
          rows: const [
            ['一等奖', '100', '200', '300', '400'],
          ],
          spans: {1: const TableSpan(1, 2), 3: const TableSpan(1, 2)},
        ),
      );
      expect(colspan.header, ['奖项', '组A', '组A', '组B', '组B']);
      expect(colspan.cell(1, 2), '200');

      // rowspan：`<td rowspan="3">特等奖（金奖）</td>` → 下面两行的同列被填成同值
      final rowspan = ruleTableOf(
        TableData(
          headers: const ['获奖等级', '奖励类别', '国赛'],
          rows: const [
            ['特等奖', '奖金', '40000'],
            ['', '工作量', '192'],
          ],
          spans: {3: const TableSpan(2, 1)},
        ),
      );
      expect(rowspan.cell(1, 0), '特等奖');
      expect(rowspan.cell(2, 0), '特等奖');
    });

    test('ruleSectionsOf：每个标题各成一节，段落与表格保持原顺序', () {
      final sections = ruleSectionsOf(_asset('r08a.md'));
      final contest = ruleSectionOf(sections, '竞赛类', level: 2);
      expect(contest, isNotNull);
      expect(contest!.ruleTables, hasLength(1));
      // 「注 3. 以最高分计入，不累加。」在竞赛类表之后 → 必须留在同一节里
      expect(contest.text, contains('以最高分计入，不累加'));
    });
  });

  group('推免附加分目录（r08a 附件）', () {
    late BonusCatalog catalog;
    setUpAll(() {
      catalog = parseBonusCatalog(_asset('r08a.md'));
    });

    test('出处与关键口径逐值正确', () {
      expect(catalog.hasData, isTrue);
      expect(catalog.sourceTitle, contains('免试攻读'));
      expect(catalog.attachmentTitle, contains('附加分项目审核认定'));
      // 第十条原文：「附加分总分10 分封顶（超过者以10 分计算）」
      expect(catalog.cap, 10);
      // 第十五条原文：「综合成绩=推免加权平均成绩+附加分」
      expect(catalog.formulaNote, contains('综合成绩=推免加权平均成绩+附加分'));
      // 注 2：2025 年 1 月 1 日前取得的竞赛获奖，排名第 6 及以后者为满分*0.5
      expect(catalog.legacyCutoff, DateTime(2025, 1, 1));
      expect(catalog.legacyFactor, 0.5);
      expect(catalog.notes.any((n) => n.contains('只计一项')), isTrue);
    });

    test('排名系数表逐档正确（含第 16 名及以后不加分）', () {
      expect(catalog.rankFactors, hasLength(9));
      expect(
        catalog.rankFactors.map((f) => f.factor).toList(),
        [1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.3, 0.1, 0],
      );
      expect(catalog.rankFactorOf(1), 1);
      expect(catalog.rankFactorOf(6), 0.5);
      expect(catalog.rankFactorOf(7), 0.3);
      expect(catalog.rankFactorOf(10), 0.3);
      expect(catalog.rankFactorOf(11), 0.1);
      expect(catalog.rankFactorOf(15), 0.1);
      expect(catalog.rankFactorOf(16), 0);
      expect(catalog.rankFactorOf(30), 0);
      expect(catalog.rankFactorOf(0), isNull);
      expect(catalog.rankFactors.map((f) => f.label).toList(), [
        '第 1 名',
        '第 2 名',
        '第 3 名',
        '第 4 名',
        '第 5 名',
        '第 6 名',
        '第 7-10 名',
        '第 11-15 名',
        '第 16 名及以后',
      ]);
    });

    test('2025-01-01 新旧规则分界（排名第 8：旧 0.5 / 新 0.3）', () {
      expect(
        catalog.contestFactor(rank: 8, awardDate: DateTime(2024, 12, 31)),
        0.5,
      );
      expect(
        catalog.contestFactor(rank: 8, awardDate: DateTime(2025, 1, 1)),
        0.3,
      );
      expect(catalog.contestFactor(rank: 1), 1);
      expect(catalog.contestFactor(rank: 16), 0);
    });

    test('竞赛类 4 项、分值按获奖等级分档', () {
      final contests = catalog.optionsOf(BonusCategory.contest);
      expect(contests, hasLength(4));
      expect(contests[0].label, '中国国际大学生创新创业大赛');
      expect(contests[0].detail, '国家级Ⅰ类（主体赛道）');
      expect(contests[0].tiers.map((t) => t.label).toList(), ['金奖', '银奖', '铜奖']);
      expect(contests[0].pointsOf('金奖'), 10);
      expect(contests[0].pointsOf('银奖'), 7);
      expect(contests[0].pointsOf('铜奖'), 4);
      // 挑战杯课外学术：特等奖 10 / 一等奖 7 / 二等奖 4 / 三等奖 2
      expect(contests[1].label, contains('课外学术科技作品竞赛'));
      expect(contests[1].pointsOf('特等奖'), 10);
      expect(contests[1].pointsOf('三等奖'), 2);
      // 国家级Ⅱ类：第一等次奖 2 / 第二等次奖 1 / 第三等次奖 0.5
      expect(contests[3].detail, '国家级Ⅱ类');
      expect(contests[3].pointsOf('第一等次奖'), 2);
      expect(contests[3].pointsOf('第三等次奖'), 0.5);
    });

    test('专利类 8 项含三个小类与小类上限', () {
      final patents = catalog.optionsOf(BonusCategory.patent);
      expect(patents, hasLength(8));
      expect(
        patents.map((p) => p.group).toSet(),
        {'发明专利', '实用新型专利', '外观设计专利'},
      );
      final invention = patents.firstWhere((p) => p.label.contains('发明专利第一发明人'));
      expect(invention.points, 1.5);
      final utility = patents.firstWhere((p) => p.label.contains('实用新型专利第一发明人'));
      expect(utility.points, 0.2);
      expect(utility.capNote, 0.6); // 注：实用新型专利总加分最高 0.6 分
      final design = patents.firstWhere((p) => p.label.contains('外观设计专利第一发明人'));
      expect(design.points, 0.1);
      expect(design.capNote, 1); // 注：外观设计专利总加分最高 1 分
    });

    test('著作权类 1 项（第一登记人 0.1，总上限 1）', () {
      final items = catalog.optionsOf(BonusCategory.copyright);
      expect(items, hasLength(1));
      expect(items.first.label, contains('著作权第一登记人'));
      expect(items.first.points, 0.1);
      expect(items.first.capNote, 1);
    });

    test('综合类按「分/学年」逐条拆分（国家奖学金 0.5）', () {
      final honors = catalog.optionsOf(BonusCategory.honor);
      expect(honors, hasLength(37));
      expect(honors.every((h) => h.perYear), isTrue);
      final national = honors.firstWhere((h) => h.label == '国家奖学金');
      expect(national.points, 0.5);
      expect(honors.firstWhere((h) => h.label == '全国优秀学生标兵').points, 4);
      expect(honors.firstWhere((h) => h.label == '校优秀团员').points, 0.2);
    });

    test('学术科研类含表内 5 项 + 注记里的课题组前 2-5 名', () {
      final items = catalog.optionsOf(BonusCategory.research);
      expect(items, hasLength(7));
      expect(items.firstWhere((i) => i.label.contains('CSSCI')).points, 2);
      expect(items.firstWhere((i) => i.label.contains('北大核心')).points, 1);
      expect(
        items.firstWhere((i) => i.label.startsWith('国家级') && i.label.contains('前 2-5 名')).points,
        0.15,
      );
      expect(
        items.firstWhere((i) => i.label.startsWith('省级') && i.label.contains('前 2-5 名')).points,
        0.1,
      );
    });

    test('选项 id 稳定且可按 id 回查', () {
      for (final option in catalog.options) {
        expect(catalog.optionById(option.id)?.label, option.label);
      }
      expect(catalog.optionById('contest#1')?.label, '中国国际大学生创新创业大赛');
      expect(catalog.optionById('nope'), isNull);
    });
  });

  group('学科竞赛目录（r20 / r21）', () {
    test('2025-2026 年版：Ⅰ3 / Ⅱ78 / Ⅲ75 / Ⅳ27', () {
      final edition = parseCompetitionCatalogEdition(_asset('r21.md'));
      expect(edition, isNotNull);
      expect(edition!.label, '2025-2026 年');
      expect(edition.countOf(CompetitionClass.i), 3);
      expect(edition.countOf(CompetitionClass.ii), 78);
      expect(edition.countOf(CompetitionClass.iii), 75);
      expect(edition.countOf(CompetitionClass.iv), 27);

      final first = edition.of(CompetitionClass.i).first;
      expect(first.name, '中国国际大学生创新大赛');
      expect(first.organizer, '创业教育学院');
      expect(edition.of(CompetitionClass.ii).first.name, 'ACM-ICPC 国际大学生程序设计竞赛');
      // Ⅲ类表多两列：申报学院（部门）/ 申报专业
      final iii = edition.of(CompetitionClass.iii).first;
      expect(iii.name, 'IMA 校园管理会计案例大赛');
      expect(iii.organizer, '会计学院');
      expect(iii.major, 'ACCA 方向');
      // Ⅳ类：主赛事靠 rowspan 合并，子项目在单独一列 → displayName 用「 · 」拼接
      final iv = edition.of(CompetitionClass.iv).first;
      expect(iv.name, '江西省大学生科技创新大赛');
      expect(iv.subProject, '信息技术知识');
      expect(iv.displayName, '江西省大学生科技创新大赛 · 信息技术知识');
    });

    test('2024-2025 学年版：Ⅰ3 / Ⅱ75 / Ⅲ71 / Ⅳ10', () {
      final edition = parseCompetitionCatalogEdition(_asset('r20.md'));
      expect(edition!.label, '2024-2025 年');
      expect(edition.countOf(CompetitionClass.i), 3);
      expect(edition.countOf(CompetitionClass.ii), 75);
      expect(edition.countOf(CompetitionClass.iii), 71);
      expect(edition.countOf(CompetitionClass.iv), 10);
    });

    test('两版合成目录：新版本在前，名称可反查类别', () {
      final r21 = parseCompetitionCatalogEdition(_asset('r21.md'), sourceDocId: 'r21')!;
      final r20 = parseCompetitionCatalogEdition(_asset('r20.md'), sourceDocId: 'r20')!;
      final catalog = competitionCatalogOf([r20, r21]);
      expect(catalog.editions.map((e) => e.label).toList(), [
        '2025-2026 年',
        '2024-2025 年',
      ]);
      expect(catalog.latest!.label, '2025-2026 年');
      expect(catalog.find('全国大学生数学建模竞赛')?.klass, CompetitionClass.ii);
      expect(catalog.find('中国国际大学生创新大赛')?.klass, CompetitionClass.i);
      expect(catalog.find('查无此赛'), isNull);
      final hits = catalog.search('数学建模');
      expect(hits, isNotEmpty);
      expect(hits.every((e) => e.matches('数学建模')), isTrue);
    });

    test('名称里不得再残留提取噪声空格', () {
      final edition = parseCompetitionCatalogEdition(_asset('r21.md'))!;
      for (final entry in edition.entries) {
        expect(entry.name.contains('科 技'), isFalse, reason: entry.name);
        expect(entry.name.trim(), entry.name);
      }
    });
  });

  group('学科竞赛奖励标准（r01a 第九条）', () {
    late AwardStandard standard;
    setUpAll(() {
      standard = parseAwardStandard(_asset('r01a.md'));
    });

    test('表结构：Ⅰ/Ⅱ/Ⅲ/Ⅳ 类的学生与教师标准都解析到了', () {
      expect(standard.hasData, isTrue);
      expect(standard.sourceTitle, contains('学科竞赛管理办法'));
      int count(CompetitionClass k, AwardAudience a) => [
        for (final e in standard.entries)
          if (e.klass == k && e.audience == a) e,
      ].length;
      expect(count(CompetitionClass.i, AwardAudience.student), 14);
      expect(count(CompetitionClass.i, AwardAudience.teacher), 14);
      expect(count(CompetitionClass.ii, AwardAudience.student), 6);
      expect(count(CompetitionClass.iii, AwardAudience.student), 6);
      expect(count(CompetitionClass.iv, AwardAudience.teacher), 6);
      // 竞赛组织奖（奖励单位）必须被跳过
      expect(
        standard.entries.any((e) => e.tierLabel.contains('先进集体')),
        isFalse,
      );
    });

    test('Ⅰ类学生奖励逐值（含两组赛项的 3.2 万 / 4 万之分）', () {
      double? amount(String name, String tier, AwardScope scope) =>
          standard.studentAmountFor(
            klass: CompetitionClass.i,
            competitionName: name,
            tier: tier,
            scope: scope,
          );
      // 中国国际大学生创新大赛 / 挑战杯课外学术：特等 4 万、一等 2 万、二等 1 万、三等 5000
      expect(amount('中国国际大学生创新大赛', '特等奖（金奖）', AwardScope.national), 40000);
      expect(amount('中国国际大学生创新大赛', '特等奖（金奖）', AwardScope.provincial), 10000);
      expect(amount('中国国际大学生创新大赛', '一等奖（银奖）', AwardScope.national), 20000);
      expect(amount('中国国际大学生创新大赛', '二等奖（铜奖）', AwardScope.national), 10000);
      expect(amount('中国国际大学生创新大赛', '三等奖', AwardScope.national), 5000);
      // 挑战杯创业计划单列一档：3.2 万 / 1.6 万 / 1 万，且三等奖不奖励学生
      expect(amount('“挑战杯”中国大学生创业计划大赛', '特等奖（金奖）', AwardScope.national), 32000);
      expect(amount('“挑战杯”中国大学生创业计划大赛', '一等奖（银奖）', AwardScope.national), 16000);
      expect(amount('“挑战杯”中国大学生创业计划大赛', '三等奖', AwardScope.national), isNull);
    });

    test('Ⅱ/Ⅲ类学生奖励逐值', () {
      double? amount(CompetitionClass k, String tier, AwardScope scope) =>
          standard.studentAmountFor(
            klass: k,
            competitionName: '任意竞赛',
            tier: tier,
            scope: scope,
          );
      expect(amount(CompetitionClass.ii, '第一等次', AwardScope.national), 6000);
      expect(amount(CompetitionClass.ii, '第一等次', AwardScope.provincial), 600);
      expect(amount(CompetitionClass.ii, '第二等次', AwardScope.national), 3000);
      expect(amount(CompetitionClass.ii, '第三等次', AwardScope.provincial), 200);
      expect(amount(CompetitionClass.iii, '第一等次', AwardScope.national), 3000);
      expect(amount(CompetitionClass.iii, '第一等次', AwardScope.provincial), 400);
      expect(amount(CompetitionClass.iii, '第三等次', AwardScope.national), 1000);
      expect(amount(CompetitionClass.iii, '第三等次', AwardScope.provincial), 100);
    });

    test('Ⅳ类不奖励学生（返回 0，而不是 null）', () {
      expect(CompetitionClass.iv.rewardsStudents, isFalse);
      expect(
        standard.studentAmountFor(
          klass: CompetitionClass.iv,
          competitionName: '江西省大学生科技创新大赛',
          tier: '第一等次',
          scope: AwardScope.national,
        ),
        0,
      );
      expect(standard.noteContaining('不奖励学生'), isNotNull);
      expect(standard.noteContaining('不累计'), isNotNull);
    });

    test('等次选项按类别给出（Ⅰ类 4 档 / Ⅱ Ⅲ类 3 档）', () {
      expect(standard.tierOptions(CompetitionClass.i), [
        '特等奖（金奖）',
        '一等奖（银奖）',
        '二等奖（铜奖）',
        '三等奖',
      ]);
      expect(standard.tierOptions(CompetitionClass.ii), [
        '第一等次',
        '第二等次',
        '第三等次',
      ]);
      expect(standard.groupLabels(CompetitionClass.i), hasLength(2));
    });

    test('第十条奖励等级认定折算', () {
      // 不设特等奖：一等奖 → 一等次，三等奖 → 三等次
      expect(awardTierIndex('一等奖'), 0);
      expect(awardTierIndex('二等奖'), 1);
      expect(awardTierIndex('三等奖'), 2);
      // 设特等奖：特等奖→一等次、一等奖→二等次、二等奖→三等次、三等奖落到第 4 档 → 不奖励
      expect(awardTierIndex('特等奖', hasSpecialTier: true), 0);
      expect(awardTierIndex('一等奖', hasSpecialTier: true), 1);
      expect(awardTierIndex('二等奖', hasSpecialTier: true), 2);
      expect(awardTierIndex('三等奖', hasSpecialTier: true), isNull);
      // 金奖/银奖/铜奖同义
      expect(awardTierIndex('金奖'), 0);
      expect(awardTierIndex('银奖'), 1);
      expect(awardTierIndex('铜奖'), 2);
      // 入围奖 / 晋级奖 / 参与奖 / 优秀奖不计入
      for (final raw in ['入围奖', '晋级奖', '参与奖', '优秀奖', '纪念奖']) {
        expect(awardTierIndex(raw), isNull, reason: raw);
      }
      expect(awardTierLabelOf(0), '第一等次');
      expect(awardTierLabelOf(2), '第三等次');
    });
  });
}
