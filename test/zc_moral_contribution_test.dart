import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

/// 用户 2026-09-27：「德育加分部分，也要像竞赛附加分一样，只高亮计入的那一项」
/// +「德育附加分也要分各板块」+「思想教育应该分为思想教育·贡献度和思想教育·
/// 参与度；荣誉称号同样要分个人和集体」→ 界面 6 个板块（引擎 6 行明细）。
///
/// 材料构造：分值由 `zcMaterialValue` 按档位表算（deed 5/5/3/2/1；
/// eduCon 5/3/1；eduPart 0.5/次；servicePost 档位分 × 考核系数；
/// honorP 10/5/4/2/1；honorG 4/3/2/1 × 负责人系数）。
ZcMaterial _m(
  String id,
  ZcTypeId type, {
  int level = 0,
  int opt = 0,
  double qty = 1,
  String name = '测试材料',
  String dateIso = '2026-05-01',
}) => ZcMaterial(
  id: id,
  typeId: type,
  name: name,
  dateIso: dateIso,
  level: level,
  opt: opt,
  qty: qty,
);

/// 综测页源码（⚠ 2026-10-08：改为扫**整族目录** —— 该页要按类拆分，
/// 不再假设这些形态住在某一个文件里；原意不变）。
String _screen() => Directory('lib/features/zongce/presentation')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.readAsStringSync())
    .join('\n');

/// 引擎明细里某个标签的值（界面 `zcSumDetail` 的同源数据）。
double _detail(ZcCalcResult r, String label) {
  for (final d in r.details) {
    if (d.label == label) return d.value;
  }
  return 0;
}

/// 一个板块内「高亮项」的分值合计。
double _sumOf(List<ZcMaterial> items, Set<String> counted) {
  var s = 0.0;
  for (final x in items) {
    if (counted.contains(x.id)) s += zcMaterialValue(x) ?? 0;
  }
  return s;
}

void main() {
  group('zcMoralContributingIds（德育附加分「最终采用」的项）', () {
    test('优秀事迹（表 3）：单选就高 → 只采用最高那一条', () {
      final deed = [
        _m('a', ZcTypeId.deed, level: 0), // 国家级 5 分
        _m('b', ZcTypeId.deed, level: 2), // 校级 3 分
        _m('c', ZcTypeId.deed, level: 4), // 班级认定 1 分
      ];
      expect(zcMaterialValue(deed[0]), 5);
      expect(zcMaterialValue(deed[1]), 3);
      expect(zcMoralContributingIds(deed), {'a'});
      final r = zcCalculate(deed, manual: const ZcManual());
      expect(_detail(r, '德育 · 优秀事迹'), 5, reason: '引擎同样只取最高');
    });

    test('同分并列时取材料列表里靠前的那一条（结果确定，不看 sort 是否稳定）', () {
      final deed = [
        _m('a', ZcTypeId.deed, level: 1), // 省部级 5 分
        _m('b', ZcTypeId.deed, level: 0), // 国家级 5 分（同为 5）
      ];
      expect(zcMoralContributingIds(deed), {'a'});
      expect(zcMoralContributingIds([deed[1], deed[0]]), {'b'}, reason: '顺序换了就换人');
    });

    test('思想教育（表 4）：骨干培训只取最高，活动参与累加到 2 分为止', () {
      final mats = [
        _m('con1', ZcTypeId.eduCon, level: 0), // 5 分
        _m('con2', ZcTypeId.eduCon, level: 1), // 3 分
        _m('part1', ZcTypeId.eduPart, qty: 4), // 2 分（正好到顶）
        _m('part2', ZcTypeId.eduPart, qty: 2), // 1 分（被 2 分上限截掉）
      ];
      expect(zcMaterialValue(mats[2]), 2);
      expect(zcMaterialValue(mats[3]), 1);
      final counted = zcMoralContributingIds(mats);
      expect(counted.contains('con1'), isTrue, reason: '骨干培训取最高');
      expect(counted.contains('con2'), isFalse);
      expect(counted.contains('part1'), isTrue);
      expect(
        counted.contains('part2'),
        isFalse,
        reason: '参与度已累到 2 分，后面的不再采用',
      );
    });

    test('思想教育参与度：0.5 一条时要累加多条才够 2 分', () {
      final mats = [
        _m('p1', ZcTypeId.eduPart, qty: 2), // 1 分
        _m('p2', ZcTypeId.eduPart, qty: 2), // 1 分
        _m('p3', ZcTypeId.eduPart, qty: 2), // 1 分（第三条起被截）
      ];
      final counted = zcMoralContributingIds(mats);
      expect(counted, {'p1', 'p2'}, reason: '按分值从高到低累加到 ≥2 分为止');
    });

    test('公共服务（表 5）：单选就高（考核系数只影响分值，不影响取舍）', () {
      final mats = [
        _m('a', ZcTypeId.servicePost, level: 0), // 国家级负责人 5
        _m('b', ZcTypeId.servicePost, level: 2, opt: 1), // 校级负责人 3.5×0.75
        _m('c', ZcTypeId.servicePost, level: 3), // 校级部门负责人 3
      ];
      expect(zcMaterialValue(mats[1]), closeTo(2.625, 1e-9));
      expect(zcMoralContributingIds(mats), {'a'});
      final r = zcCalculate(mats, manual: const ZcManual());
      expect(_detail(r, '德育 · 公共服务'), 5);
    });

    test('荣誉称号（表 6·7）：个人与集体各取最高，两条都算采用', () {
      final mats = [
        _m('p1', ZcTypeId.honorP, level: 0), // 国家级个人 10
        _m('p2', ZcTypeId.honorP, level: 3), // 校级个人 2
        _m('g1', ZcTypeId.honorG, level: 0), // 国家级集体 4
        _m('g2', ZcTypeId.honorG, level: 2), // 市级集体 2
      ];
      expect(zcMoralContributingIds(mats), {'p1', 'g1'});
      final r = zcCalculate(mats, manual: const ZcManual(deyuPingyi: 20));
      expect(
        _detail(r, '德育 · 荣誉称号（个人）'),
        10,
        reason: '界面按「个人 / 集体」两行挂两个板块（用户 2026-09-27）',
      );
      expect(_detail(r, '德育 · 荣誉称号（集体）'), 4);
      expect(
        r.deyu,
        90,
        reason: '个人 10 + 集体 4 → 合计封顶 10：60 + 20 评议 + 10 = 90（不封顶会是 94）',
      );
    });

    test('分值为 0 / 未填档位的材料不算采用', () {
      final mats = [
        _m('zero', ZcTypeId.eduPart, qty: 0), // 0 分
        _m('bad', ZcTypeId.servicePost, level: 99), // 档位越界 → 无分
        _m('ok', ZcTypeId.servicePost, level: 7), // 班委 2 分
      ];
      expect(zcMaterialValue(mats[0]), 0);
      expect(zcMaterialValue(mats[1]), isNull);
      expect(zcMoralContributingIds(mats), {'ok'});
    });

    test('非德育材料被忽略；空列表 → 空集合', () {
      final contest = _m('c', ZcTypeId.contest, name: '蓝桥杯');
      expect(zcMoralContributingIds([contest]), isEmpty);
      expect(zcMoralContributingIds(const []), isEmpty);
    });

    test('★ 一致性：六个板块「高亮项合计」都不小于引擎明细（封顶只会让合计变小）', () {
      final deed = [_m('d1', ZcTypeId.deed, level: 2), _m('d2', ZcTypeId.deed, level: 3)];
      final eduCon = [_m('e1', ZcTypeId.eduCon, level: 2)];
      final eduPart = [
        _m('e2', ZcTypeId.eduPart, qty: 3),
        _m('e3', ZcTypeId.eduPart, qty: 3),
      ];
      final post = [_m('s1', ZcTypeId.servicePost, level: 1)];
      final honorP = [_m('h1', ZcTypeId.honorP, level: 1)];
      final honorG = [_m('h2', ZcTypeId.honorG, level: 1)];
      final mats = [...deed, ...eduCon, ...eduPart, ...post, ...honorP, ...honorG];
      final counted = zcMoralContributingIds(mats);
      final r = zcCalculate(mats, manual: const ZcManual());

      for (final board in [deed, eduCon, eduPart, post, honorP, honorG]) {
        expect(
          board.where((x) => counted.contains(x.id)).length,
          greaterThan(0),
          reason: '每个有分的板块至少要高亮一条',
        );
      }
      expect(
        _sumOf(eduCon, counted),
        greaterThanOrEqualTo(_detail(r, '德育 · 思想教育贡献度')),
        reason: '骨干培训：就高，合计 == 明细',
      );
      expect(
        _sumOf(eduPart, counted),
        greaterThanOrEqualTo(_detail(r, '德育 · 思想教育参与度')),
        reason: '参与度：累加类板块，高亮项原始合计 ≥ 引擎封顶 2 后的明细值',
      );
      expect(
        _sumOf(honorP, counted),
        greaterThanOrEqualTo(_detail(r, '德育 · 荣誉称号（个人）')),
      );
      expect(
        _sumOf(honorG, counted),
        greaterThanOrEqualTo(_detail(r, '德育 · 荣誉称号（集体）')),
      );
      expect(_sumOf(deed, counted), _detail(r, '德育 · 优秀事迹'));
      expect(_sumOf(post, counted), _detail(r, '德育 · 公共服务'));
      // 未采用的项 = 有分但不在集合里（界面据此淡出）
      final dimmed = [
        for (final x in mats)
          if (!counted.contains(x.id) && (zcMaterialValue(x) ?? 0) > 0) x.id,
      ];
      expect(dimmed, isNotEmpty, reason: '这组材料里有被截掉的项');
    });
  });

  group('源码守卫：德育附加分拆板块 + 高亮（用户 2026-09-27）', () {
    test('zcMoralContributingIds 只有一处实现（domain 层）', () {
      final hits = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.contains('/old/')) continue;
        if (f.readAsStringSync().contains('Set<String> zcMoralContributingIds(')) {
          hits.add(f.path.replaceAll(r'\', '/'));
        }
      }
      expect(hits, ['lib/features/zongce/domain/zc_engine.dart']);
    });

    test('德育卡拆成六个板块：每块一个 zcExtraItem + 同一份高亮集合', () {
      final src = _screen();
      expect(
        src,
        // 2026-09-27 追加「放开所有累加」开关后这个调用折行了（多传 `open:`）。
        contains('final dCounted = zcMoralContributingIds('),
        reason: '高亮集合取引擎同一套口径',
      );
      for (final label in const [
        "'优秀事迹（表 3）'",
        "'思想教育 · 贡献度（表 4）'",
        "'思想教育 · 参与度（表 4）'",
        "'公共服务（表 5）'",
        "'荣誉称号 · 个人（表 6）'",
        "'荣誉称号 · 集体（表 7）'",
      ]) {
        expect(src, contains('label: $label'), reason: '板块 $label 缺失');
      }
      // 六个板块各自把 highlightIds / dimmedIds 传下去（智育那四条本来就有）。
      expect(
        'highlightIds: dCounted,'.allMatches(src).length,
        6,
        reason: '德育六个板块都要高亮',
      );
      // 旧的一把平铺（无板块、无高亮）必须消失。
      expect(
        src.contains('for (final x in dMats) zcMatRow(context, x)'),
        isFalse,
        reason: '旧的平铺列表已被六板块取代',
      );
    });

    test('板块顺序与规则点：优秀事迹→贡献度→参与度→公共服务→个人→集体', () {
      final src = _screen();
      final at = [
        for (final k in const [
          '优秀事迹（表 3）',
          '思想教育 · 贡献度（表 4）',
          '思想教育 · 参与度（表 4）',
          '公共服务（表 5）',
          '荣誉称号 · 个人（表 6）',
          '荣誉称号 · 集体（表 7）',
        ])
          src.indexOf(k),
      ];
      expect(at.every((i) => i > 0), isTrue);
      for (var i = 1; i < at.length; i++) {
        expect(at[i], greaterThan(at[i - 1]), reason: '板块顺序被打乱');
      }
      // 规则点 id：r23 贡献度 / r24 参与度 / r28 个人 / r29+r30 集体 —— 一一对应。
      for (final tip in const ["'d-3-1'", "'d-3-2a'", "'d-3-2b'", "'d-3-3'", "'d-3-4a'", "'d-3-4b'"]) {
        expect(src, contains(tip), reason: '规则点 $tip 缺失');
      }
      expect(
        src.contains("zcTipIdsOf(const ['d-3-2a', 'd-3-2b'])"),
        isFalse,
        reason: '思想教育两块已拆开，不能再用一个板块挂两个规则点',
      );
      expect(
        src.contains("zcTipIdsOf(const ['d-3-4a', 'd-3-4b'])"),
        isFalse,
        reason: '荣誉称号个人/集体已拆开',
      );
    });
  });
}
