/// 竞赛奖励「赛事经验系数」守卫（2026-09-18 加）。
///
/// 用户原话：「竞赛奖励有一个经验系数，就是有些奖项它拿的人太多，就会导致奖金被
/// 等比例缩小，而这个比例一般是固定的，我希望可以手动设置」。
/// ask_user_question 两条拍板：
/// - **按赛事设**（一个赛事的比例固定，配一次即可，该赛事所有记录等比缩减）；
/// - **行内明算**（记录行显示「6000 元 × 0.6 = 3600 元」+ 统计口径里说明）。
///
/// 金额一律用**资料库真实文件**现解析（`assets/rules/text/r01a.md`）——解析器一旦
/// 失效本文件先红，避免"自己编一个标准再自己断言"。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/competition_award/data/award_standard_parser.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_calc.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_coefficient.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_record.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_standard.dart';
import 'package:smarter_jxufe/features/competition_award/domain/competition_catalog.dart';

String _asset(String name) => File('assets/rules/text/$name').readAsStringSync();

CompetitionAwardRecord _record({
  required String id,
  required CompetitionClass klass,
  required String name,
  String tier = '第一等次',
  AwardScope scope = AwardScope.national,
  DateTime? date,
  AwardAdjustment adjustment = AwardAdjustment.none,
}) => CompetitionAwardRecord(
  id: id,
  competitionName: name,
  klass: klass,
  tierLabel: tier,
  scope: scope,
  date: date,
  adjustment: adjustment,
);

void main() {
  late AwardStandard standard;

  setUpAll(() {
    standard = parseAwardStandard(_asset('r01a.md'));
  });

  group('系数解析', () {
    test('接受 0.6 / .6 / 60% / 6折 / 1 / 0', () {
      expect(parseAwardCoefficient('0.6'), 0.6);
      expect(parseAwardCoefficient('.6'), 0.6);
      expect(parseAwardCoefficient('60%'), closeTo(0.6, 1e-9));
      expect(parseAwardCoefficient('60％'), closeTo(0.6, 1e-9));
      expect(parseAwardCoefficient('6折'), closeTo(0.6, 1e-9));
      expect(parseAwardCoefficient('1'), 1);
      expect(parseAwardCoefficient('0'), 0);
      expect(parseAwardCoefficient(' 0.85 '), 0.85);
    });

    test('越界 / 认不出 → null（系数是缩减语义，>1 一定是用错了）', () {
      expect(parseAwardCoefficient('1.5'), isNull);
      expect(parseAwardCoefficient('120%'), isNull);
      expect(parseAwardCoefficient('11折'), isNull);
      expect(parseAwardCoefficient('-0.2'), isNull);
      expect(parseAwardCoefficient('abc'), isNull);
      expect(parseAwardCoefficient(''), isNull);
      expect(parseAwardCoefficient('%'), isNull);
    });

    test('展示：去尾零、最多两位', () {
      expect(fmtAwardCoefficient(1), '1');
      expect(fmtAwardCoefficient(0.6), '0.6');
      expect(fmtAwardCoefficient(0.85), '0.85');
      expect(fmtAwardCoefficient(0.5), '0.5');
      expect(fmtAwardCoefficient(0.625), '0.63');
      expect(fmtAwardCoefficient(0), '0');
    });
  });

  group('系数表', () {
    test('未设过的赛事一律 1.0；名字比对忽略空白与大小写', () {
      const table = AwardCoefficientTable([
        AwardCoefficient(competitionName: '蓝桥杯 全国软件大赛', factor: 0.6),
      ]);
      expect(table.factorFor('蓝桥杯 全国软件大赛'), 0.6);
      expect(table.factorFor('蓝桥杯全国软件大赛'), 0.6, reason: '空白不参与比对');
      expect(table.factorFor('蓝桥杯 全国软件大赛 '), 0.6);
      expect(table.factorFor('全国大学生数学建模竞赛'), 1.0);
      expect(table.factorFor(''), 1.0);
      expect(AwardCoefficientTable.empty.factorFor('任意赛事'), 1.0);
    });

    test('upsert 按归一后的名字覆盖，remove 删一条', () {
      var table = AwardCoefficientTable.empty;
      table = table.upsert(
        const AwardCoefficient(competitionName: 'A 赛事', factor: 0.6),
      );
      table = table.upsert(
        const AwardCoefficient(competitionName: 'B 赛事', factor: 0.5),
      );
      expect(table.entries.length, 2);
      // 同名（忽略空白）覆盖，不新增。
      table = table.upsert(
        const AwardCoefficient(competitionName: 'A赛事', factor: 0.4),
      );
      expect(table.entries.length, 2);
      expect(table.factorFor('A 赛事'), 0.4);
      table = table.remove('a 赛事');
      expect(table.entries.length, 1);
      expect(table.factorFor('A赛事'), 1.0);
      expect(table.factorFor('B 赛事'), 0.5);
    });

    test('JSON 容错：脏数据跳过、越界 clamp（旧数据不许崩页面）', () {
      expect(AwardCoefficient.fromJson(null), isNull);
      expect(AwardCoefficient.fromJson('nope'), isNull);
      expect(AwardCoefficient.fromJson({'factor': 0.6}), isNull);
      expect(
        AwardCoefficient.fromJson({'name': '   ', 'factor': 0.6}),
        isNull,
      );
      expect(AwardCoefficient.fromJson({'name': 'x', 'factor': '0.6'}), isNull);
      final high = AwardCoefficient.fromJson({'name': 'x', 'factor': 1.8})!;
      expect(high.factor, 1.0, reason: '越界往下夹');
      final low = AwardCoefficient.fromJson({'name': 'x', 'factor': -3})!;
      expect(low.factor, 0.0);
      final ok = AwardCoefficient.fromJson({'name': ' 某赛事 ', 'factor': 0.6})!;
      expect(ok.competitionName, '某赛事');
      expect(ok.factor, 0.6);
      expect(AwardCoefficient.fromJson(ok.toJson())!.factor, 0.6);
    });
  });

  group('接进计算（competitionAwardOutcomeOf）', () {
    double totalOf(
      List<CompetitionAwardRecord> records,
      AwardCoefficientTable table,
    ) => competitionAwardOutcomeOf(
      records: records,
      standard: standard,
      coefficients: table,
    ).total;

    test('资料库自检：不传系数时与旧行为逐值相同（Ⅱ类国赛一等 6000）', () {
      final r = _record(
        id: 'a',
        klass: CompetitionClass.ii,
        name: '全国大学生数学建模竞赛',
      );
      expect(totalOf([r], AwardCoefficientTable.empty), 6000);
      expect(
        competitionAwardOutcomeOf(records: [r], standard: standard).total,
        6000,
        reason: '默认参数 = 不缩减（向后兼容）',
      );
    });

    test('只缩命中的赛事，其他记录全额', () {
      final records = [
        _record(
          id: 'a',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
        ),
        _record(
          id: 'b',
          klass: CompetitionClass.iii,
          name: '中国大学生计算机设计大赛',
        ),
      ];
      const table = AwardCoefficientTable([
        AwardCoefficient(competitionName: '全国大学生数学建模竞赛', factor: 0.6),
      ]);
      final outcome = competitionAwardOutcomeOf(
        records: records,
        standard: standard,
        coefficients: table,
      );
      // Ⅱ类只取最高：6000 → 3600（仍高于Ⅲ类的 3000）。
      expect(outcome.total, 3600 + 3000);
      final a = outcome.items.firstWhere((i) => i.record.id == 'a');
      expect(a.counted, isTrue);
      expect(a.baseAmount, 6000);
      expect(a.coefficient, 0.6);
      expect(a.amount, 3600);
      expect(a.scaled, isTrue, reason: '行内明算的开关');
      final b = outcome.items.firstWhere((i) => i.record.id == 'b');
      expect(b.scaled, isFalse);
      expect(b.coefficient, 1);
      expect(b.amount, 3000);
      expect(
        outcome.appliedRules.any((s) => s.contains('赛事经验系数')),
        isTrue,
        reason: '统计口径里要说明哪条被缩减',
      );
    });

    test('乘在折减之后：国际项目 70% × 系数 0.5 = 标准的 35%', () {
      final r = _record(
        id: 'a',
        klass: CompetitionClass.ii,
        name: '全国大学生数学建模竞赛',
        adjustment: AwardAdjustment.international70,
      );
      const table = AwardCoefficientTable([
        AwardCoefficient(competitionName: '全国大学生数学建模竞赛', factor: 0.5),
      ]);
      final outcome = competitionAwardOutcomeOf(
        records: [r],
        standard: standard,
        coefficients: table,
      );
      expect(outcome.total, 6000 * 0.7 * 0.5);
      final a = outcome.items.single;
      expect(a.baseAmount, 6000 * 0.7, reason: 'base = 折减后、乘系数前');
      expect(a.amount, 6000 * 0.7 * 0.5);
    });

    test('先缩后比：被大幅缩减的高档项目会让位给未缩减的低档项目', () {
      // Ⅱ类「只奖励金额最高的 1 个项目」——比的是**实际发放金额**。
      final records = [
        _record(
          id: 'big',
          klass: CompetitionClass.ii,
          name: '蓝桥杯全国软件大赛', // 国赛第一等次 6000
        ),
        _record(
          id: 'small',
          klass: CompetitionClass.ii,
          name: '中国大学生计算机设计大赛', // 国赛第二等次 3000
          tier: '第二等次',
        ),
      ];
      // 不缩减：6000 胜出。
      expect(totalOf(records, AwardCoefficientTable.empty), 6000);
      // 蓝桥杯 ×0.3 = 1800 < 3000 → 计算机设计大赛胜出（证明系数在「取最高」之前）。
      const table = AwardCoefficientTable([
        AwardCoefficient(competitionName: '蓝桥杯全国软件大赛', factor: 0.3),
      ]);
      final outcome = competitionAwardOutcomeOf(
        records: records,
        standard: standard,
        coefficients: table,
      );
      expect(outcome.total, 3000);
      expect(
        outcome.items.firstWhere((i) => i.record.id == 'big').counted,
        isFalse,
        reason: '被缩减后不再是最高 → 不计入',
      );
      expect(
        outcome.items.firstWhere((i) => i.record.id == 'small').counted,
        isTrue,
      );
    });

    test('系数 0 = 该赛事全不发（金额 0，但仍算「已计入」一条）', () {
      final r = _record(
        id: 'a',
        klass: CompetitionClass.ii,
        name: '全国大学生数学建模竞赛',
      );
      const table = AwardCoefficientTable([
        AwardCoefficient(competitionName: '全国大学生数学建模竞赛', factor: 0),
      ]);
      final outcome = competitionAwardOutcomeOf(
        records: [r],
        standard: standard,
        coefficients: table,
      );
      expect(outcome.total, 0);
      final a = outcome.items.single;
      expect(a.counted, isTrue);
      expect(a.amount, 0);
      expect(a.baseAmount, 6000);
      expect(a.scaled, isTrue);
    });

    test('未计入的记录不受系数影响（原因仍是原来的原因）', () {
      final r = _record(
        id: 'a',
        klass: CompetitionClass.iv, // Ⅳ类不奖励学生
        name: '全国大学生数学建模竞赛',
      );
      const table = AwardCoefficientTable([
        AwardCoefficient(competitionName: '全国大学生数学建模竞赛', factor: 0.5),
      ]);
      final a = competitionAwardOutcomeOf(
        records: [r],
        standard: standard,
        coefficients: table,
      ).items.single;
      expect(a.counted, isFalse);
      expect(a.reason, contains('Ⅳ类'));
      expect(a.scaled, isFalse);
    });
  });
}
