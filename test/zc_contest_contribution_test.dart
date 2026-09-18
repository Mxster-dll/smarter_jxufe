import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

/// 用户 2026-09-18：「综测智育竞赛加分要把最终贡献分数的项高亮一下」
/// + 同日「智育总分是用舍入后的加权计算的」。
ZcMaterial _contest(
  String id, {
  required String cat,
  required int level, // 0 国家级 / 1 省级 / 2 校级（zcLevelKeys g/s/x）
  required int opt, // 奖项下标
  String name = '测试竞赛',
}) => ZcMaterial(
  id: id,
  typeId: ZcTypeId.contest,
  name: name,
  dateIso: '2026-05-01',
  cat: cat,
  level: level,
  opt: opt,
);

void main() {
  group('zcContestContributingIds（竞赛「最终计入」的项）', () {
    test('最高项 > 5 分 → 只计最高那一项（其余全部未计入）', () {
      // Ⅰ类国家级一等奖 20 分 + Ⅱ类国家级一等奖 12 分
      final mats = [
        _contest('a', cat: 'c1', level: 0, opt: 0),
        _contest('b', cat: 'c2', level: 0, opt: 0),
      ];
      expect(zcMaterialValue(mats[0]), 20);
      expect(zcMaterialValue(mats[1]), 12);
      expect(zcContestContributingIds(mats), {'a'});
      expect(zcCalculate(mats, manual: const ZcManual()).zhiyu, 20, reason: '只计最高 → 智育 = 20');
    });

    test('都 ≤ 5 分 → 从高到低累加，累到 ≥ 5 为止（含跨过封顶的那一项）', () {
      // Ⅲ类国家级二等奖 4 分 + Ⅱ类校级一等奖 2 分
      final mats = [
        _contest('a', cat: 'c3', level: 0, opt: 1),
        _contest('b', cat: 'c2', level: 2, opt: 0),
      ];
      expect(zcMaterialValue(mats[0]), 4);
      expect(zcMaterialValue(mats[1]), 2);
      expect(zcContestContributingIds(mats), {'a', 'b'});
      expect(zcCalculate(mats, manual: const ZcManual()).zhiyu, 5, reason: '累加 6 → 封顶 5');
    });

    test('累加没到 5 → 全部计入', () {
      final mats = [
        _contest('a', cat: 'c3', level: 2, opt: 0), // 校级一等奖 1 分
        _contest('b', cat: 'c3', level: 2, opt: 0),
      ];
      expect(zcContestContributingIds(mats), {'a', 'b'});
      expect(zcCalculate(mats, manual: const ZcManual()).zhiyu, 2);
    });

    test('封顶之后的分值不再计入（只高亮到跨顶那一项）', () {
      final mats = [
        _contest('a', cat: 'c3', level: 0, opt: 0), // 5 分（正好封顶）
        _contest('b', cat: 'c3', level: 2, opt: 0), // 1 分，超出上限
      ];
      expect(zcContestContributingIds(mats), {'a'});
      expect(zcCalculate(mats, manual: const ZcManual()).zhiyu, 5);
    });

    test('未识别类别（cat 空）/ 无分材料不进集合', () {
      final mats = [
        _contest('a', cat: '', level: 0, opt: 0),
        _contest('b', cat: 'c2', level: 0, opt: 0),
      ];
      expect(zcMaterialValue(mats[0]), isNull);
      expect(zcContestContributingIds(mats), {'b'});
    });

    test('没有竞赛材料 → 空集合；非竞赛材料被忽略', () {
      expect(zcContestContributingIds(const []), isEmpty);
      final foreign = ZcMaterial(
        id: 'f',
        typeId: ZcTypeId.foreign,
        name: '大学英语四级',
        dateIso: '2026-05-01',
        manualScore: 489,
      );
      expect(zcContestContributingIds([foreign]), isEmpty);
    });
  });

  group('智育总分用舍入后的加权（用户 2026-09-18）', () {
    test('zcRound2 取 2 位小数', () {
      expect(zcRound2(91.85964912280701), 91.86);
      expect(zcRound2(91.8), 91.8);
      expect(zcRound2(91.005), 91.01);
      expect(zcRound2(0), 0);
    });

    test('autoWeight 的原始 double 先舍入到 2 位，再进智育总分', () {
      final r = zcCalculate(
        const [],
        manual: const ZcManual(),
        autoWeight: 91.85964912280701,
      );
      expect(r.weightUsed, 91.86, reason: '界面显示 2 位 → 参与计算的也必须是它');
      expect(r.zhiyu, 91.86, reason: '智育 = 加权 + 附加 − 扣分（无材料时等于加权）');
    });

    test('手动覆盖的加权同样按 2 位参与计算', () {
      final r = zcCalculate(
        const [],
        manual: const ZcManual(weight: 88.888),
      );
      expect(r.weightUsed, 88.89);
      expect(r.zhiyu, 88.89);
    });
  });

  group('源码守卫：综测页控件形态（用户 2026-09-18 四条）', () {
    final src = File(
      'lib/features/zongce/presentation/zongce_screen.dart',
    ).readAsStringSync();

    test('全页统一刷新按钮，字段级输入框 / 刷新按钮全部撤掉', () {
      expect(src, contains("tooltip: '刷新数据'"));
      expect(src, contains('onPressed: _refreshAll'));
      expect(src, contains('void _refreshAll()'));
      expect(src, contains('gePriorGradesProvider'));
      expect(src, contains('volunteerActivitiesProvider'));
      expect(src, contains('unawaited(_autoTice())'));
      expect(src.contains('_numField('), isFalse, reason: '常驻输入框已撤掉');
      expect(src.contains('_refreshAutoWeight'), isFalse);
      expect(src.contains('_refreshAutoVolunteer'), isFalse);
      expect(src.contains('suffixIcon: IconButton'), isFalse);
      expect(
        src.contains(r"ValueKey('$_year-num-"),
        isFalse,
        reason: '旧数字输入框的 Key 不该再出现',
      );
    });

    test('次数字段走 CountStepper；评议/体测/加权/志愿走点击才输入', () {
      expect('CountStepper('.allMatches(src).length, greaterThanOrEqualTo(8));
      for (final label in const [
        '缺课节数',
        '缺席次数',
        '未参加实习实训次数',
        '扰乱秩序次数',
        '体育弃权次数',
        '文艺扰乱次数',
        '退团次数',
        '文艺弃权次数',
        '未参加劳育活动次数',
      ]) {
        expect(src, contains("label: '$label'"), reason: '缺 $label 的步进器');
      }
      expect('_tapNumber('.allMatches(src).length, greaterThanOrEqualTo(4));
      expect(src, contains('_tapNumberOpt('));
      expect(
        "label: '民主评议分'".allMatches(src).length,
        greaterThanOrEqualTo(3),
        reason: '德育 / 美育 / 劳育 三处民主评议都是「点击才输入」',
      );
      expect(src, contains("label: '体测成绩'"));
      expect(src, contains("label: '加权成绩'"));
      expect(src, contains("label: '学年志愿时长(h)'"));
      expect(src, contains("_sourceTag(context, tag)"));
    });

    test('竞赛小项高亮最终计入的材料', () {
      expect(src, contains('final contestCounted = zcContestContributingIds('));
      expect(src, contains('highlightIds: contestCounted'));
      expect(src, contains('dimmedIds: {'));
      expect(src, contains("'计入总分'"));
      expect(src, contains("'未计入'"));
    });
  });
}
