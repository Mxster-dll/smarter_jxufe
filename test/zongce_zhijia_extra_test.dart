/// 综测「智育 · 加分项」四小项守卫（用户 2026-09-18 裁定）。
///
/// 原话：「综测智育加分项分为四部分，我希望你分开显示为四小项」。
///
/// 口径：四小项 = 学科竞赛（表 8）/ 论文·专利（表 9）/ 外语能力（表 10）/
/// 创新创业（表 11），**分值各自取引擎明细**（`智育 · 学科竞赛` 等前缀），
/// 界面层不重算；四者之和 == 加分项总徽章。
///
/// 这里守两件事：
/// ① 引擎确实产出这四个明细 label（前缀写错的话，界面四小项会恒显示 0）；
/// ② `zongce_screen.dart` 的四个小项 + 四个 `_sumDetail` 前缀与之一致。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

ZcMaterial _mat(
  ZcTypeId type, {
  String name = 't',
  String cat = 'c2',
  int level = 0,
  int opt = 0,
  double? manualScore,
}) => ZcMaterial(
  id: 'x-${type.name}',
  typeId: type,
  name: name,
  dateIso: '2026-03-10',
  cat: cat,
  level: level,
  opt: opt,
  manualScore: manualScore,
);

void main() {
  const labels = <String>[
    '智育 · 学科竞赛',
    '智育 · 论文/专利',
    '智育 · 外语',
    '智育 · 创业',
  ];

  group('引擎明细：智育加分项四类各自出分', () {
    test('四类材料齐全时，四个明细 label 都在', () {
      final r = zcCalculate([
        _mat(ZcTypeId.contest, cat: 'c2', level: 0, opt: 1), // Ⅱ类国家级二等奖 8
        _mat(ZcTypeId.paper, name: '论文', level: 5, opt: 0), // 国内一般 0.5 × 1
        _mat(ZcTypeId.foreign, name: '大学英语四级', manualScore: 489), // → 1 分
        _mat(ZcTypeId.startup, name: '创业', level: 0), // 4 分
      ], manual: const ZcManual());

      for (final label in labels) {
        expect(
          r.details.any((d) => d.label == label),
          isTrue,
          reason: '引擎必须产出「$label」（界面四小项按它取数，写错就恒 0）',
        );
      }
      final sum = [
        for (final d in r.details)
          if (labels.contains(d.label)) d.value,
      ].fold<double>(0, (a, b) => a + b);
      expect(sum, greaterThan(0));
    });

    test('只放一类材料时，其余三类不出分（各自独立）', () {
      final r = zcCalculate([
        _mat(ZcTypeId.foreign, name: '大学英语四级', manualScore: 489),
      ], manual: const ZcManual());
      final foreign = r.details.firstWhere((d) => d.label == '智育 · 外语');
      expect(foreign.value, 1);
      // 引擎会给未参与的类别补 0 分条目 → 界面显示「0 分」，不是漏掉小项。
      final contest = r.details.where((d) => d.label == '智育 · 学科竞赛');
      expect(contest.isEmpty || contest.first.value == 0, isTrue);
    });
  });

  group('源码守卫：智育卡四小项', () {
    final src = File(
      'lib/features/zongce/presentation/zongce_screen.dart',
    ).readAsStringSync();

    test('四个小项标签与各自的明细前缀都在', () {
      for (final label in const [
        '学科竞赛（表 8）',
        '论文 / 专利（表 9）',
        '外语能力（表 10）',
        '创新创业（表 11）',
      ]) {
        expect(src, contains(label), reason: '缺少小项「$label」');
      }
      for (final prefix in labels) {
        expect(
          src,
          contains("_sumDetail(r, const ['$prefix'])"),
          reason: '「$prefix」的分值必须取自引擎明细（前缀要与引擎一致）',
        );
      }
    });

    test('四小项各挂一份材料筛选，且用 _extraItem 渲染', () {
      expect('_extraItem('.allMatches(src).length, greaterThanOrEqualTo(5)); // 定义 1 + 调用 4
      expect(src.contains('x.typeId == ZcTypeId.contest'), isTrue);
      expect(src.contains('x.typeId == ZcTypeId.paper'), isTrue);
      expect(src.contains('x.typeId == ZcTypeId.foreign'), isTrue);
      expect(src.contains('x.typeId == ZcTypeId.startup'), isTrue);
    });

    test('旧的「一整块证明材料」写法已撤（不再一次性铺全部 zMats）', () {
      expect(
        src.contains('加分项 · 证明材料（四类各计最高）'),
        isFalse,
        reason: '四小项取代了单块证明材料区',
      );
    });
  });
}
