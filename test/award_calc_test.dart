// 两个新功能的计算守卫（2026-09-17 加）。
//
// 覆盖：推免附加分的「每类只计一项 / 10 分封顶 / 排名系数 / 2025-01-01 新旧规则」
// 与竞赛奖励的「手选时间范围 / Ⅳ类不奖励学生 / Ⅱ Ⅲ类不累计 / 第十条取最高 /
// 第九条注的两个折减口径」；数据用**真实资料库资产**解析出来的目录与标准。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/competition_award/data/award_standard_parser.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_calc.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_record.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_standard.dart';
import 'package:smarter_jxufe/features/competition_award/domain/competition_catalog.dart';
import 'package:smarter_jxufe/features/recommendation/data/bonus_catalog_parser.dart';
import 'package:smarter_jxufe/features/recommendation/domain/bonus_catalog.dart';
import 'package:smarter_jxufe/features/recommendation/domain/recommendation_calc.dart';
import 'package:smarter_jxufe/features/recommendation/domain/recommendation_item.dart';

String _asset(String name) => File('assets/rules/text/$name').readAsStringSync();

BonusCatalog _bonusCatalog() => parseBonusCatalog(_asset('r08a.md'));
AwardStandard _standard() => parseAwardStandard(_asset('r01a.md'));

RecommendationBonusItem _item({
  required BonusCategory category,
  required String optionId,
  required String label,
  String? tier,
  int? rank,
  DateTime? date,
  String id = 'x',
}) => RecommendationBonusItem(
  id: id,
  category: category,
  optionId: optionId,
  optionLabel: label,
  tierLabel: tier,
  rank: rank,
  awardDate: date,
);

CompetitionAwardRecord _record({
  required CompetitionClass klass,
  required String name,
  required String tier,
  AwardScope scope = AwardScope.national,
  DateTime? date,
  bool special = false,
  AwardAdjustment adjustment = AwardAdjustment.none,
  String id = 'r',
}) => CompetitionAwardRecord(
  id: id,
  competitionName: name,
  klass: klass,
  tierLabel: tier,
  scope: scope,
  date: date,
  hasSpecialTier: special,
  adjustment: adjustment,
);

void main() {
  group('推免成绩：附加分与综合成绩', () {
    late BonusCatalog catalog;
    setUpAll(() => catalog = _bonusCatalog());

    test('综合成绩 = 推免加权 + 附加分（金奖第 1 名 = 满分）', () {
      final outcome = recommendationOutcomeOf(
        weightedAverage: 91.86,
        items: [
          _item(
            category: BonusCategory.contest,
            optionId: 'contest#1',
            label: '中国国际大学生创新大赛',
            tier: '金奖',
            rank: 1,
            date: DateTime(2026, 5, 1),
          ),
        ],
        catalog: catalog,
      );
      expect(outcome.items.single.points, 10);
      expect(outcome.bonusTotal, 10);
      expect(outcome.capped, isFalse);
      expect(outcome.total, closeTo(101.86, 1e-9));
    });

    test('排名系数作用于竞赛类（银奖第 2 名 = 7×0.9）', () {
      final outcome = recommendationOutcomeOf(
        weightedAverage: 90,
        items: [
          _item(
            category: BonusCategory.contest,
            optionId: 'contest#1',
            label: '中国国际大学生创新大赛',
            tier: '银奖',
            rank: 2,
            date: DateTime(2026, 5, 1),
          ),
        ],
        catalog: catalog,
      );
      expect(outcome.items.single.factor, 0.9);
      expect(outcome.items.single.points, closeTo(6.3, 1e-9));
      expect(outcome.total, closeTo(96.3, 1e-9));
    });

    test('2025-01-01 之前取得的获奖：排名第 8 按 ×0.5（新增则 ×0.3）', () {
      double pointsFor(DateTime date) => recommendationOutcomeOf(
        weightedAverage: 0,
        items: [
          _item(
            category: BonusCategory.contest,
            optionId: 'contest#1',
            label: '中国国际大学生创新大赛',
            tier: '铜奖', // 4 分
            rank: 8,
            date: date,
          ),
        ],
        catalog: catalog,
      ).items.single.points;
      expect(pointsFor(DateTime(2024, 12, 31)), closeTo(2.0, 1e-9));
      expect(pointsFor(DateTime(2025, 6, 1)), closeTo(1.2, 1e-9));
    });

    test('排名第 16 名及以后不加分（该条不计入并给原因）', () {
      final outcome = recommendationOutcomeOf(
        weightedAverage: 90,
        items: [
          _item(
            category: BonusCategory.contest,
            optionId: 'contest#1',
            label: '中国国际大学生创新大赛',
            tier: '金奖',
            rank: 16,
          ),
        ],
        catalog: catalog,
      );
      expect(outcome.items.single.points, 0);
      expect(outcome.items.single.counted, isFalse);
      expect(outcome.items.single.reason, contains('不加分'));
      expect(outcome.bonusTotal, 0);
    });

    test('未填排名按第 1 名计，并给出提醒', () {
      final outcome = recommendationOutcomeOf(
        weightedAverage: 0,
        items: [
          _item(
            category: BonusCategory.contest,
            optionId: 'contest#1',
            label: '中国国际大学生创新大赛',
            tier: '金奖',
          ),
        ],
        catalog: catalog,
      );
      expect(outcome.items.single.points, 10);
      expect(outcome.warnings.single, contains('未填排名'));
    });

    test('每一类别只计一项（同类取最高，其余标为不累加）', () {
      final outcome = recommendationOutcomeOf(
        weightedAverage: 0,
        items: [
          _item(
            id: 'a',
            category: BonusCategory.honor,
            optionId: catalog.optionsOf(BonusCategory.honor)
                .firstWhere((o) => o.label == '国家奖学金')
                .id,
            label: '国家奖学金', // 0.5 分/学年
          ),
          _item(
            id: 'b',
            category: BonusCategory.honor,
            optionId: catalog.optionsOf(BonusCategory.honor)
                .firstWhere((o) => o.label == '校优秀团员')
                .id,
            label: '校优秀团员', // 0.2 分/学年
          ),
        ],
        catalog: catalog,
      );
      final counted = outcome.items.where((i) => i.counted).toList();
      expect(counted, hasLength(1));
      expect(counted.single.points, 0.5);
      final dropped = outcome.items.firstWhere((i) => !i.counted);
      expect(dropped.points, 0.2);
      expect(dropped.superseded, isTrue);
      expect(dropped.reason, contains('不累加'));
      // 办法口径 0.5；对照口径（若累加）0.7
      expect(outcome.categoryBest[BonusCategory.honor], 0.5);
      expect(outcome.categorySum[BonusCategory.honor], closeTo(0.7, 1e-9));
      expect(outcome.bonusTotal, 0.5);
    });

    test('附加分总分 10 分封顶（超过者以 10 分计算）', () {
      final outcome = recommendationOutcomeOf(
        weightedAverage: 90,
        items: [
          _item(
            id: 'c',
            category: BonusCategory.contest,
            optionId: 'contest#1',
            label: '中国国际大学生创新大赛',
            tier: '金奖',
            rank: 1,
          ),
          _item(
            id: 'h',
            category: BonusCategory.honor,
            optionId: catalog.optionsOf(BonusCategory.honor)
                .firstWhere((o) => o.label == '全国优秀学生标兵')
                .id,
            label: '全国优秀学生标兵', // 4 分
          ),
        ],
        catalog: catalog,
      );
      expect(outcome.uncappedBonus, 14);
      expect(outcome.capped, isTrue);
      expect(outcome.bonusTotal, 10);
      expect(outcome.total, 100);
    });

    test('资料库里已不存在的项目：不计入且给明确原因（不静默算错）', () {
      final outcome = recommendationOutcomeOf(
        weightedAverage: 90,
        items: [
          _item(
            category: BonusCategory.contest,
            optionId: 'contest#999',
            label: '某个已下架的比赛',
            tier: '金奖',
            rank: 1,
          ),
        ],
        catalog: catalog,
      );
      expect(outcome.items.single.points, 0);
      expect(outcome.items.single.counted, isFalse);
      expect(outcome.items.single.reason, contains('找不到该项目'));
      expect(outcome.bonusTotal, 0);
    });

    test('未选获奖等级：不计入并提示', () {
      final outcome = recommendationOutcomeOf(
        weightedAverage: 0,
        items: [
          _item(
            category: BonusCategory.contest,
            optionId: 'contest#1',
            label: '中国国际大学生创新大赛',
          ),
        ],
        catalog: catalog,
      );
      expect(outcome.items.single.reason, contains('未选择获奖等级'));
    });

    test('加分项 JSON 往返与脏数据容错', () {
      final item = _item(
        id: 'rec-1',
        category: BonusCategory.contest,
        optionId: 'contest#2',
        label: '“挑战杯”全国大学生课外学术科技作品竞赛',
        tier: '特等奖',
        rank: 3,
        date: DateTime(2026, 5, 26),
      );
      final restored = RecommendationBonusItem.fromJson(item.toJson())!;
      expect(restored.id, item.id);
      expect(restored.category, BonusCategory.contest);
      expect(restored.tierLabel, '特等奖');
      expect(restored.rank, 3);
      expect(restored.awardDate, DateTime(2026, 5, 26));
      expect(restored.summary, contains('排名第 3'));
      // 脏数据：类型不对 / 类别名认不出 / 缺 id → 一律跳过该条
      expect(RecommendationBonusItem.fromJson('nonsense'), isNull);
      expect(RecommendationBonusItem.fromJson(<String, dynamic>{}), isNull);
      expect(
        RecommendationBonusItem.fromJson({
          'id': 'a',
          'category': 'unknownCategory',
          'optionId': 'x',
        }),
        isNull,
      );
    });
  });

  group('竞赛奖励：手选时间范围与合计', () {
    late AwardStandard standard;
    setUpAll(() => standard = _standard());

    test('Ⅰ类国赛特等奖 = 4 万元（计入）', () {
      final outcome = competitionAwardOutcomeOf(
        records: [
          _record(
            klass: CompetitionClass.i,
            name: '中国国际大学生创新大赛',
            tier: '特等奖（金奖）',
            date: DateTime(2026, 5, 1),
          ),
        ],
        standard: standard,
      );
      expect(outcome.items.single.amount, 40000);
      expect(outcome.items.single.counted, isTrue);
      expect(outcome.total, 40000);
      expect(outcome.countedCount, 1);
    });

    test('手选时间范围：区间外与缺日期的都明确标出、不计入', () {
      // 三条记录分属 Ⅱ/Ⅲ/Ⅰ 类：避免被「Ⅱ/Ⅲ类不累计」这条规则干扰本测试的计数断言。
      final records = [
        _record(
          id: 'in',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
          tier: '第一等次',
          date: DateTime(2026, 5, 10),
        ),
        _record(
          id: 'out',
          klass: CompetitionClass.iii,
          name: 'IMA 校园管理会计案例大赛',
          tier: '第一等次',
          date: DateTime(2024, 5, 10),
        ),
        _record(
          id: 'nodate',
          klass: CompetitionClass.i,
          name: '中国国际大学生创新大赛',
          tier: '三等奖',
        ),
      ];
      final outcome = competitionAwardOutcomeOf(
        records: records,
        standard: standard,
        range: AwardDateRange(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
      );
      expect(outcome.total, 6000);
      expect(outcome.countedCount, 1);
      expect(
        outcome.items.firstWhere((i) => i.record.id == 'out').reason,
        contains('不在所选时间范围内'),
      );
      expect(
        outcome.items.firstWhere((i) => i.record.id == 'nodate').reason,
        contains('缺获奖日期'),
      );
      // 不传区间 = 全部计入（缺日期也计入）：Ⅱ6000 + Ⅲ3000 + Ⅰ5000
      final all = competitionAwardOutcomeOf(
        records: records,
        standard: standard,
      );
      expect(all.countedCount, 3);
      expect(all.total, 14000);
    });

    test('区间含首尾两天', () {
      final range = AwardDateRange(DateTime(2026, 5, 1), DateTime(2026, 5, 31));
      expect(range.containsDate(DateTime(2026, 5, 1)), isTrue);
      expect(range.containsDate(DateTime(2026, 5, 31, 23, 59)), isTrue);
      expect(range.containsDate(DateTime(2026, 4, 30)), isFalse);
      expect(range.label, '2026-05-01 ~ 2026-05-31');
    });

    test('Ⅳ类不奖励学生（金额 0 + 注记原因）', () {
      final outcome = competitionAwardOutcomeOf(
        records: [
          _record(
            klass: CompetitionClass.iv,
            name: '江西省大学生科技创新大赛',
            tier: '第一等次',
            date: DateTime(2026, 5, 1),
          ),
        ],
        standard: standard,
      );
      expect(outcome.total, 0);
      expect(outcome.items.single.counted, isFalse);
      expect(outcome.items.single.reason, contains('不奖励学生'));
      expect(outcome.appliedRules.any((r) => r.contains('Ⅳ类')), isTrue);
    });

    test('Ⅱ/Ⅲ类只奖励金额最高的 1 个项目（按类别分别取最高）', () {
      final outcome = competitionAwardOutcomeOf(
        records: [
          _record(
            id: 'ii-1',
            klass: CompetitionClass.ii,
            name: '全国大学生数学建模竞赛',
            tier: '第一等次',
            date: DateTime(2026, 5, 1),
          ),
          _record(
            id: 'ii-2',
            klass: CompetitionClass.ii,
            name: '全国大学生电子设计竞赛',
            tier: '第二等次',
            date: DateTime(2026, 5, 2),
          ),
          _record(
            id: 'iii-1',
            klass: CompetitionClass.iii,
            name: 'IMA 校园管理会计案例大赛',
            tier: '第一等次',
            date: DateTime(2026, 5, 3),
          ),
        ],
        standard: standard,
      );
      // Ⅱ类取 6000（弃 3000）+ Ⅲ类 3000 = 9000
      expect(outcome.total, 9000);
      expect(outcome.countedCount, 2);
      final dropped = outcome.items.firstWhere((i) => i.record.id == 'ii-2');
      expect(dropped.counted, isFalse);
      expect(dropped.reason, contains('不累计'));
      // 被取最高挤掉 → 页面只变暗、不印这个 reason（用户 2026-09-18 口径）。
      expect(dropped.suppressed, isTrue);
      expect(outcome.appliedRules.any((r) => r.contains('只奖励金额最高的 1 个项目')), isTrue);
    });

    test('第十条：同一年度同一竞赛不同级别获奖取最高', () {
      final outcome = competitionAwardOutcomeOf(
        records: [
          _record(
            id: 'a',
            klass: CompetitionClass.i,
            name: '中国国际大学生创新大赛',
            tier: '一等奖（银奖）', // 2 万
            date: DateTime(2026, 5, 1),
          ),
          _record(
            id: 'b',
            klass: CompetitionClass.i,
            name: '中国国际大学生创新大赛',
            tier: '三等奖', // 5000
            date: DateTime(2026, 9, 1), // 同年
          ),
        ],
        standard: standard,
      );
      expect(outcome.total, 20000);
      expect(outcome.countedCount, 1);
      final dropped = outcome.items.firstWhere((i) => i.record.id == 'b');
      expect(dropped.reason, contains('更高奖项'));
      expect(dropped.suppressed, isTrue, reason: '第十条取最高挤掉 → 页面只变暗');
    });

    test('未计入分两类：取最高挤掉的是 suppressed，算不出来的不是', () {
      final outcome = competitionAwardOutcomeOf(
        records: [
          // ① 会被「Ⅱ类不累计」挤掉（6000 > 3000，胜负与记录顺序无关）。
          _record(
            id: 'drop',
            klass: CompetitionClass.ii,
            name: '全国大学生数学建模竞赛',
            tier: '第二等次',
            date: DateTime(2026, 5, 1),
          ),
          _record(
            id: 'win',
            klass: CompetitionClass.ii,
            name: '全国大学生电子设计竞赛',
            tier: '第一等次',
            date: DateTime(2026, 5, 2),
          ),
          // ② 缺日期（有范围筛选时）—— 算不出来，原因必须留着。
          _record(
            id: 'nodate',
            klass: CompetitionClass.iii,
            name: 'IMA 校园管理会计案例大赛',
            tier: '第一等次',
          ),
          // ③ Ⅳ类不奖励学生 —— 同理。
          _record(
            id: 'iv',
            klass: CompetitionClass.iv,
            name: '某Ⅳ类竞赛',
            tier: '第一等次',
            date: DateTime(2026, 5, 3),
          ),
        ],
        standard: standard,
        range: AwardDateRange(DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
      );

      AwardRecordOutcome of(String id) =>
          outcome.items.firstWhere((i) => i.record.id == id);
      expect(of('drop').suppressed, isTrue, reason: '取最高 → 只变暗，不解释');
      expect(of('nodate').suppressed, isFalse, reason: '缺日期要给出原因');
      expect(of('nodate').reason, contains('缺获奖日期'));
      expect(of('iv').suppressed, isFalse, reason: 'Ⅳ类要给出原因');
      expect(of('iv').reason, contains('不奖励学生'));
    });

    test('第九条注：国际项目按 70%', () {
      final outcome = competitionAwardOutcomeOf(
        records: [
          _record(
            klass: CompetitionClass.i,
            name: '中国国际大学生创新大赛',
            tier: '特等奖（金奖）',
            adjustment: AwardAdjustment.international70,
            date: DateTime(2026, 5, 1),
          ),
        ],
        standard: standard,
      );
      expect(outcome.items.single.amount, closeTo(28000, 1e-9));
      expect(outcome.appliedRules.any((r) => r.contains('70%')), isTrue);
    });

    test('第九条注：挑战杯非主体赛道按Ⅱ类标准', () {
      final outcome = competitionAwardOutcomeOf(
        records: [
          _record(
            klass: CompetitionClass.i,
            name: '“挑战杯”中国大学生创业计划大赛',
            tier: '一等奖（银奖）', // Ⅰ类 1.6 万；折成Ⅱ类一等次 = 6000
            adjustment: AwardAdjustment.nonMainTrackAsClassII,
            date: DateTime(2026, 5, 1),
          ),
        ],
        standard: standard,
      );
      expect(outcome.items.single.effectiveKlass, CompetitionClass.ii);
      expect(outcome.items.single.amount, 6000);
    });

    test('设特等奖的赛事里三等奖落到第 4 档 → 不奖励', () {
      final outcome = competitionAwardOutcomeOf(
        records: [
          _record(
            klass: CompetitionClass.ii,
            name: '全国大学生数学建模竞赛',
            tier: '三等奖',
            special: true,
            date: DateTime(2026, 5, 1),
          ),
        ],
        standard: standard,
      );
      expect(outcome.items.single.counted, isFalse);
      expect(outcome.items.single.reason, contains('设特等奖'));
    });

    test('记录 JSON 往返与脏数据容错', () {
      final record = _record(
        id: 'award-1',
        klass: CompetitionClass.i,
        name: '中国国际大学生创新大赛',
        tier: '特等奖（金奖）',
        scope: AwardScope.provincial,
        date: DateTime(2026, 5, 26),
        adjustment: AwardAdjustment.international70,
      );
      final restored = CompetitionAwardRecord.fromJson(record.toJson())!;
      expect(restored.id, 'award-1');
      expect(restored.klass, CompetitionClass.i);
      expect(restored.scope, AwardScope.provincial);
      expect(restored.adjustment, AwardAdjustment.international70);
      expect(restored.date, DateTime(2026, 5, 26));
      expect(restored.summary, contains('省赛'));
      expect(restored.yearKey, contains('2026'));
      expect(CompetitionAwardRecord.fromJson(<String, dynamic>{}), isNull);
      expect(
        CompetitionAwardRecord.fromJson({
          'id': 'x',
          'competitionName': 'y',
          'klass': 'nope',
          'scope': 'national',
        }),
        isNull,
      );
    });

    test('金额文案', () {
      expect(fmtAwardAmount(6000), '6000 元');
      expect(fmtAwardAmount(200), '200 元');
      expect(fmtAwardAmount(1500.5), '1500.5 元');
      expect(fmtAwardAmount(10000), '1 万元');
      expect(fmtAwardAmount(32000), '3.2 万元');
      expect(fmtAwardAmount(42000), '4.2 万元');
    });
  });
}
