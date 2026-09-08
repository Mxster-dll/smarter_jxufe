import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';

ZcMaterial _mat(
  ZcTypeId type, {
  String cat = 'c2',
  int level = 0,
  int opt = 0,
  String dateIso = '2026-03-10',
  double qty = 0,
}) =>
    ZcMaterial(
      id: 'x',
      typeId: type,
      name: 't',
      dateIso: dateIso,
      cat: cat,
      level: level,
      opt: opt,
      qty: qty,
    );

void main() {
  group('竞赛加分口径 calcJS', () {
    test('最高项 >5 只计最高项', () {
      // Ⅱ类国家级一等奖 10 + 校级特等 2
      final r = zcCalculate([
        _mat(ZcTypeId.contest, cat: 'c2', level: 0, opt: 1),
        _mat(ZcTypeId.contest, cat: 'c2', level: 2, opt: 0),
      ], manual: const ZcManual());
      // 最高项 10 > 5 → 只计 10
      expect(
        r.details.firstWhere((d) => d.label.contains('学科竞赛')).value,
        10,
      );
    });

    test('最高项 ≤5 累加封顶 5', () {
      // 三个校级二/三等奖（Ⅲ类校 x: 0.5 + 0.25）等：III 类校级一等奖 0.5? 取多个 ≤5 分项累加
      final r = zcCalculate([
        _mat(ZcTypeId.contest, cat: 'c1', level: 2, opt: 3), // Ⅰ类校级三等奖 2
        _mat(ZcTypeId.contest, cat: 'c1', level: 2, opt: 1), // Ⅰ类校级一等奖 4
      ], manual: const ZcManual());
      expect(
        r.details.firstWhere((d) => d.label.contains('学科竞赛')).value,
        5, // 4+2 → 封顶 5
      );
    });

    test('类别需选定否则不计', () {
      final r = zcCalculate([
        _mat(ZcTypeId.contest, cat: '', level: 0, opt: 1),
      ], manual: const ZcManual());
      expect(
        r.details.firstWhere((d) => d.label.contains('学科竞赛')).value,
        0,
      );
    });
  });

  group('论文加分 calcPaper', () {
    test('无权威破格时合计封顶 5', () {
      final r = zcCalculate([
        _mat(ZcTypeId.paper, level: 4, opt: 0), // pat 1×1
        _mat(ZcTypeId.paper, level: 4, opt: 0), // pat 1×1
        _mat(ZcTypeId.paper, level: 4, opt: 0), // pat 1×1
        _mat(ZcTypeId.paper, level: 4, opt: 0), // pat 1×1
        _mat(ZcTypeId.paper, level: 4, opt: 0), // pat 1×1
        _mat(ZcTypeId.paper, level: 4, opt: 0), // pat 1×1
      ], manual: const ZcManual());
      expect(
        r.details.firstWhere((d) => d.label.contains('论文')).value,
        5,
      );
    });

    test('gen 类累计不超过 1.5；权威破格可超 5', () {
      // 国内一般 0.5×1 三篇 = 1.5（cap），再加 intl 20×0.6(二作)=12 → 13.5
      final r = zcCalculate([
        _mat(ZcTypeId.paper, level: 5, opt: 0),
        _mat(ZcTypeId.paper, level: 5, opt: 0),
        _mat(ZcTypeId.paper, level: 5, opt: 0),
        _mat(ZcTypeId.paper, level: 5, opt: 0), // 0.5×4 = 2 → cap 1.5
        _mat(ZcTypeId.paper, level: 0, opt: 1), // intl 20×0.6
      ], manual: const ZcManual());
      expect(
        r.details.firstWhere((d) => d.label.contains('论文')).value,
        13.5,
      );
    });
  });

  group('德育组合', () {
    test('荣誉称号个人+集体合计 ≤10', () {
      // 个人国家级 10（表6 max）+ 集体国家级 4 → cap 10
      final r = zcCalculate([
        _mat(ZcTypeId.honorP, level: 0),
        _mat(ZcTypeId.honorG, level: 0),
      ], manual: const ZcManual());
      expect(
        r.details.firstWhere((d) => d.label.contains('荣誉称号')).value,
        10,
      );
    });

    test('附加分合计 ≤20', () {
      final r = zcCalculate([
        _mat(ZcTypeId.deed, level: 0), // 5
        _mat(ZcTypeId.eduCon, level: 0), // 5
        _mat(ZcTypeId.servicePost, level: 0), // 5
        _mat(ZcTypeId.honorP, level: 0), // 10
      ], manual: const ZcManual());
      expect(r.deyu, closeTo(60 + 0 + 20 - 0, 1e-9));
    });
  });

  group('等次判定', () {
    test('gradeOf 门槛与 below', () {
      expect(zcGradeOf(80, ZcRank.top30), ZcGrade.ok);
      expect(zcGradeOf(80, ZcRank.below), ZcGrade.pass);
      expect(zcGradeOf(70, ZcRank.top60), ZcGrade.good);
      expect(zcGradeOf(70, ZcRank.below), ZcGrade.pass);
      expect(zcGradeOf(55, ZcRank.top30), ZcGrade.fail);
    });

    test('综合等次：d/z ok 且体美劳无 fail → ok', () {
      const man = ZcManual(
        deyuPingyi: 20,
        tScore: 100,
        meiyuPingyi: 20,
        laoyuPingyi: 20,
        rankD: ZcRank.top30,
        rankZ: ZcRank.top30,
        rankT: ZcRank.top30,
        rankM: ZcRank.top30,
        rankL: ZcRank.top30,
        weight: 90,
      );
      final r = zcCalculate(const [], manual: man);
      expect(r.gD, ZcGrade.ok);
      expect(r.gZ, ZcGrade.ok);
      expect(r.overall, ZcGrade.ok);
    });

    test('d fail 一票否决整体 fail', () {
      const man = ZcManual(vetoD: true, weight: 90);
      final r = zcCalculate(const [], manual: man);
      expect(r.overall, ZcGrade.fail);
    });
  });

  group('志愿档位', () {
    test('档位映射', () {
      expect(zcVolunteerScore(100), 10);
      expect(zcVolunteerScore(50), 8);
      expect(zcVolunteerScore(30), 6);
      expect(zcVolunteerScore(20), 4);
      expect(zcVolunteerScore(15), 2);
      expect(zcVolunteerScore(10), 1);
      expect(zcVolunteerScore(9), 0);
      expect(zcVolunteerScore(120), 10);
    });

    test('自动志愿源接入劳育附加分', () {
      const man = ZcManual(laoyuPingyi: 20);
      final r = zcCalculate(const [], manual: man, autoVolunteer: 55);
      expect(r.laoyu, closeTo(60 + 20 + 8, 1e-9));
      expect(
        r.details.firstWhere((d) => d.label.contains('志愿服务')).auto,
        true,
      );
    });
  });

  group('学年窗口与自动源', () {
    test('材料按日期归入学年窗口', () {
      final mats = [
        _mat(ZcTypeId.deed, dateIso: '2026-03-10'), // 2025-2026 学年窗口
        _mat(ZcTypeId.deed, dateIso: '2025-08-31'), // 2024-2025
        _mat(ZcTypeId.deed, dateIso: '2026-09-01'), // 2026-2027
      ];
      expect(zcFilterByYear(mats, 2026).length, 1);
      expect(zcFilterByYear(mats, 2025).length, 1);
      expect(zcFilterByYear(mats, 2027).length, 1);
      expect(zcDefaultYear(DateTime(2026, 9, 15)), 2026);
      expect(zcDefaultYear(DateTime(2026, 3, 1)), 2025);
    });

    test('外语取最高；加权手动覆盖自动', () {
      final r = zcCalculate([
        _mat(ZcTypeId.foreign, level: 0), // 雅思≥6.5 2
        _mat(ZcTypeId.foreign, level: 12), // 六级≥425 2
      ], manual: const ZcManual(), autoWeight: 80);
      expect(r.details.firstWhere((d) => d.label.contains('外语')).value, 2);
      expect(r.weightUsed, 80);
      expect(r.weightAuto, true);

      final r2 = zcCalculate(const [],
          manual: const ZcManual(weight: 88.5), autoWeight: 80);
      expect(r2.weightUsed, 88.5);
      expect(r2.weightAuto, false);
    });

    test('竞赛名自动识别', () {
      final hit1 = zcMatchContest('全国大学生数学建模竞赛');
      expect(hit1?.cat, 'c2');
      final hit2 = zcMatchContest('蓝桥杯');
      expect(hit2?.cat, 'c2');
      final hit3 = zcMatchContest('挑战杯中国大学生创业计划大赛');
      expect(hit3?.cat, 'c1');
      // 口语化子串回退
      final hit4 = zcMatchContest('数学建模国赛一等奖');
      expect(hit4?.cat, 'c2');
      // 江西省赛子项目
      final hit5 = zcMatchContest('江西省大学生科技创新竞赛程序设计竞赛');
      expect(hit5?.cat, 'c4');
      expect(zcMatchContest('完全不存在的比赛名'), isNull);
    });
  });
}
