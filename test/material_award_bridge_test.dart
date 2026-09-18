// 材料库 → 推免加分项 / 竞赛奖励获奖记录「自动带入」的守卫（2026-09-18 加）。
//
// 用户原话：「我希望推免和竞赛奖励的加分项自动从资料库中获取」→ 澄清为
// 「自动带入『材料库』里已登记的证明材料 + 直接按自动识别结果计入」。
//
// 数据两层都是**真实的**：材料 fixture 逐字段抄自该账号材料库的实际 9 条，
// 目录与标准用真实资料库资产（`assets/rules/text/r08a.md` / `r01a.md`）现解析。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smarter_jxufe/features/competition_award/data/award_standard_parser.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_calc.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_record.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_standard.dart';
import 'package:smarter_jxufe/features/competition_award/domain/competition_catalog.dart';
import 'package:smarter_jxufe/features/materials/domain/material_award_bridge.dart';
import 'package:smarter_jxufe/features/recommendation/data/bonus_catalog_parser.dart';
import 'package:smarter_jxufe/features/recommendation/domain/bonus_catalog.dart';
import 'package:smarter_jxufe/features/recommendation/domain/recommendation_calc.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

String _asset(String name) => File('assets/rules/text/$name').readAsStringSync();

BonusCatalog _bonusCatalog() => parseBonusCatalog(_asset('r08a.md'));
AwardStandard _standard() => parseAwardStandard(_asset('r01a.md'));

/// 竞赛材料（`levelIndex`：0=国家级 1=省级 2=校级；`opt`：0=特等 1=一等 2=二等 3=三等 4=参与）。
ZcMaterial _contest({
  required String name,
  String cat = 'c2',
  int level = 0,
  int opt = 1,
  String date = '2026-05-01',
  String note = '',
  String id = '',
}) => ZcMaterial(
  id: id.isEmpty ? 'm-${name.hashCode}-$date-$level-$opt' : id,
  typeId: ZcTypeId.contest,
  name: name,
  cat: cat,
  level: level,
  opt: opt,
  dateIso: date,
  note: note,
);

ZcMaterial _typed({
  required ZcTypeId typeId,
  required String name,
  int level = 0,
  int opt = 0,
  String date = '2026-05-01',
  String note = '',
}) => ZcMaterial(
  id: 'm-${typeId.name}-${name.hashCode}',
  typeId: typeId,
  name: name,
  level: level,
  opt: opt,
  dateIso: date,
  note: note,
);

/// 该账号材料库的真实 9 条（1 条外语 + 8 条竞赛）。
List<ZcMaterial> _myMaterials() => [
  _contest(
    name: '中国大学生程序设计竞赛',
    cat: 'c3',
    opt: 2,
    date: '2026-05-31',
    note: '2026 CCPC全国邀请赛（桂林）',
  ),
  _typed(typeId: ZcTypeId.foreign, name: '大学英语四级', date: '2026-06-13'),
  _contest(
    name: 'ACM-ICPC 国际大学生程序设计竞赛',
    opt: 3,
    date: '2026-05-02',
    note: '2026 ICPC全国邀请赛（西安）',
  ),
  _contest(
    name: 'ACM-ICPC 国际大学生程序设计竞赛',
    opt: 2,
    date: '2026-07-29',
    note: '2026 ICPC全国邀请赛（沈阳）',
  ),
  _contest(
    name: '蓝桥杯全国软件和信息技术专业人才大赛',
    level: 1,
    opt: 1,
    date: '2026-05-08',
    note: 'C++ B组',
  ),
  _contest(
    name: '蓝桥杯全国软件和信息技术专业人才大赛',
    opt: 1,
    date: '2026-06-17',
    note: 'C++ B组',
  ),
  _contest(
    name: '中国机器人及人工智能大赛',
    level: 1,
    opt: 3,
    date: '2026-06-18',
    note: '智慧零售赛道',
  ),
  _contest(name: '中国高校计算机大赛', opt: 3, date: '2026-05-06', note: '个人奖'),
  _contest(name: '中国高校计算机大赛', level: 1, opt: 1, date: '2026-05-06'),
];

void main() {
  group('真实材料库 → 竞赛奖励', () {
    test('8 条竞赛全部生成记录，外语材料明确给出不计入原因', () {
      final links = materialAwardRecordLinks(_myMaterials());
      final records = linkedValuesOf(links);
      expect(records, hasLength(8));
      expect(unlinkedOf(links), hasLength(1));
      expect(unlinkedOf(links).single.reason, contains('不是学科竞赛获奖材料'));

      // 逐条核对类别 / 赛别 / 等次（材料字段 → 办法口径）。
      CompetitionAwardRecord find(String name, String date) => records.firstWhere(
        (r) => r.competitionName == name && r.date?.day.toString() == date,
      );
      final ccpc = find('中国大学生程序设计竞赛', '31');
      expect(ccpc.klass, CompetitionClass.iii);
      expect(ccpc.scope, AwardScope.national);
      expect(ccpc.tierLabel, '二等奖');
      expect(ccpc.id, startsWith(kMaterialAwardIdPrefix));
      expect(ccpc.note, contains('来自材料库'));

      final icpc3 = records.firstWhere(
        (r) => r.competitionName.startsWith('ACM-ICPC') && r.tierLabel == '三等奖',
      );
      expect(icpc3.klass, CompetitionClass.ii);
      final lanqiaoProv = records.firstWhere(
        (r) => r.competitionName.startsWith('蓝桥杯') && r.scope == AwardScope.provincial,
      );
      expect(lanqiaoProv.tierLabel, '一等奖');
    });

    test('真实 8 条 → 合计 7500 元：Ⅱ类取最高（蓝桥杯国家级一等 6000）+ Ⅲ类 1500', () {
      final records = linkedValuesOf(materialAwardRecordLinks(_myMaterials()));
      final outcome = competitionAwardOutcomeOf(
        records: records,
        standard: _standard(),
      );
      // 同年度同竞赛取最高（第十条）：ICPC 二等 3000 > 三等 1500；蓝桥杯国家级 6000 > 省级 600。
      // Ⅱ/Ⅲ类各只保留金额最高的一项（第九条注）：Ⅱ类 6000、Ⅲ类 1500。
      expect(outcome.total, 7500);
      expect(outcome.countedCount, 2);
      expect(
        outcome.countedItems.map((i) => i.record.competitionName).toSet(),
        {'蓝桥杯全国软件和信息技术专业人才大赛', '中国大学生程序设计竞赛'},
      );
    });

    test('校级 / 参与未获奖 / 类别缺失 都有具体原因，不静默丢弃', () {
      final linked = materialAwardRecordLinks([
        _contest(name: '某比赛', cat: 'c2', level: 0, opt: 1, date: ''),
      ]);
      expect(linkedValuesOf(linked), hasLength(1)); // 缺日期仍生成（时间范围才筛）

      final skipped = materialAwardRecordLinks([
        _contest(name: '某校赛', cat: 'c3', level: 2, opt: 1),
        _contest(name: '某国赛', cat: 'c3', level: 0, opt: 4),
        _contest(name: 'qqqzzz', cat: '', level: 0, opt: 1),
      ]);
      expect(linkedValuesOf(skipped), isEmpty);
      final reasons = [for (final l in unlinkedOf(skipped)) l.reason!];
      expect(reasons[0], contains('校级竞赛不在奖励标准内'));
      expect(reasons[1], contains('参与(未获奖)'));
      expect(reasons[2], contains('认不出竞赛类别'));
    });

    test('类别缺失时按名称兜底识别（CCPC → 中国大学生程序设计竞赛 → Ⅲ类）', () {
      final links = materialAwardRecordLinks([
        _contest(name: 'CCPC 全国邀请赛', cat: '', level: 0, opt: 1),
      ]);
      final record = linkedValuesOf(links).single;
      expect(record.klass, CompetitionClass.iii);
    });

    test('去重：与手填记录同竞赛名 + 同日期时不重复计入', () {
      final material = _contest(
        name: '蓝桥杯全国软件和信息技术专业人才大赛',
        opt: 1,
        date: '2026-06-17',
      );
      final manual = CompetitionAwardRecord(
        id: 'manual-1',
        competitionName: '蓝桥杯全国软件和信息技术专业人才大赛',
        klass: CompetitionClass.ii,
        tierLabel: '一等奖',
        scope: AwardScope.national,
        date: DateTime(2026, 6, 17),
      );
      final links = materialAwardRecordLinks(
        [material],
        existing: [manual],
      );
      expect(linkedValuesOf(links), isEmpty);
      expect(unlinkedOf(links).single.reason, contains('与已登记的手填记录重复'));
    });

    test('忽略名单：被忽略的材料不再生成记录', () {
      final material = _contest(name: '某国赛', cat: 'c2', date: '2026-05-01');
      final links = materialAwardRecordLinks(
        [material],
        excludedMaterialIds: {material.id},
      );
      expect(linkedValuesOf(links), isEmpty);
      expect(unlinkedOf(links).single.reason, contains('已在页面上忽略'));
    });

    test('折减口径只对Ⅰ类生效（材料里写明了才套）', () {
      final nonMain = _contest(
        name: '“挑战杯”全国大学生课外学术科技作品竞赛专项赛',
        cat: 'c1',
        opt: 1,
        note: '非主体赛道',
      );
      final intl = _contest(
        name: '中国国际大学生创新大赛',
        cat: 'c1',
        opt: 1,
        note: '国际项目',
      );
      final plain = _contest(name: '某Ⅱ类国赛', cat: 'c2', opt: 1, note: '专项赛');
      final links = materialAwardRecordLinks([nonMain, intl, plain]);
      final records = linkedValuesOf(links);
      expect(
        records[0].adjustment,
        AwardAdjustment.nonMainTrackAsClassII,
      );
      expect(records[1].adjustment, AwardAdjustment.international70);
      expect(records[2].adjustment, AwardAdjustment.none);
    });
  });

  group('真实材料库 → 推免加分项', () {
    test('国家级 5 条落到「排行榜目录 / 非主体赛道」档，竞赛类只计最高一项 2 分', () {
      final catalog = _bonusCatalog();
      final links = materialBonusItemLinks(_myMaterials(), catalog);
      final items = linkedValuesOf(links);
      expect(items, hasLength(5));
      for (final item in items) {
        expect(item.category, BonusCategory.contest);
        expect(item.id, startsWith(kMaterialAwardIdPrefix));
        // 行标题 = 我在材料库里登记的名字；命中的目录项由 optionId 保留。
        expect(item.optionLabel, isNot(contains('排行榜')));
        expect(
          catalog.optionById(item.optionId)!.label,
          contains('排行榜'),
        );
      }
      // 等次 → 档位：一等→第一等次奖、二等→第二等次奖、三等→第三等次奖。
      expect(
        items.map((i) => i.tierLabel).toSet(),
        {'第一等次奖', '第二等次奖', '第三等次奖'},
      );

      final outcome = recommendationOutcomeOf(
        weightedAverage: 91.90833,
        items: items,
        catalog: catalog,
      );
      expect(outcome.categoryBest[BonusCategory.contest], 2.0);
      expect(outcome.bonusTotal, 2.0);
      expect(outcome.total, closeTo(93.90833, 0.00001));
    });

    test('省级 / 校级竞赛不加分，并给出「只认国家级」的原因', () {
      final catalog = _bonusCatalog();
      final links = materialBonusItemLinks([
        _contest(name: '蓝桥杯全国软件和信息技术专业人才大赛', level: 1, opt: 1),
        _contest(name: '某校赛', cat: 'c3', level: 2, opt: 1),
      ], catalog);
      expect(linkedValuesOf(links), isEmpty);
      for (final l in unlinkedOf(links)) {
        expect(l.reason, contains('只认国家级'));
      }
    });

    test('三套档位命名各自对位（金/银/铜 · 特等/一等/二等/三等 · 第一/二/三等次奖）', () {
      final catalog = _bonusCatalog();
      final links = materialBonusItemLinks([
        _contest(name: '中国国际大学生创新大赛', cat: 'c1', opt: 0, date: ''),
        _contest(name: '中国国际大学生创新大赛', cat: 'c1', opt: 1, date: ''),
        _contest(name: '中国国际大学生创新大赛', cat: 'c1', opt: 2, date: ''),
        _contest(name: '中国国际大学生创新大赛', cat: 'c1', opt: 3, date: ''),
        _contest(name: '“挑战杯”全国大学生课外学术科技作品竞赛', cat: 'c1', opt: 0, date: ''),
        _contest(name: '“挑战杯”全国大学生课外学术科技作品竞赛', cat: 'c1', opt: 3, date: ''),
        _contest(name: '“挑战杯”中国大学生创业计划竞赛', cat: 'c1', opt: 1, date: ''),
      ], catalog);
      final items = linkedValuesOf(links);
      expect(items, hasLength(7)); // 三等奖那条也会列出来，只是档位为空 → 计算时不封档
      String optionOf(int i) => catalog.optionById(items[i].optionId)!.label;
      expect(items[0].tierLabel, '金奖');
      expect(items[1].tierLabel, '银奖');
      expect(items[2].tierLabel, '铜奖');
      expect(optionOf(0), contains('大学生创新创业大赛'));
      // 创新大赛（金/银/铜三档）没有三等奖对应的档位 → 列出但档位为空。
      expect(items[3].tierLabel, isNull);
      expect(items[4].tierLabel, '特等奖');
      expect(optionOf(4), contains('课外学术'));
      expect(items[5].tierLabel, '三等奖');
      // 创业计划 一等奖 → 银奖（该组只有金/银/铜三档）。
      expect(optionOf(6), contains('创业计划'));
      expect(items[6].tierLabel, '银奖');
      expect(unlinkedOf(links), isEmpty);
    });

    test('论文 / 专利 / 著作权 / 综合类都能落到对应条目', () {
      final catalog = _bonusCatalog();
      final links = materialBonusItemLinks([
        _typed(
          typeId: ZcTypeId.paper,
          name: '一种图像识别装置实用新型专利',
          opt: 1,
          date: '',
        ),
        _typed(
          typeId: ZcTypeId.paper,
          name: '一种图像识别装置实用新型专利',
          opt: 2,
          date: '',
        ),
        _typed(typeId: ZcTypeId.paper, name: '软件著作权登记证书', opt: 1, date: ''),
        _typed(typeId: ZcTypeId.paper, name: 'CSSCI 期刊论文', opt: 0, date: ''),
        _typed(typeId: ZcTypeId.paper, name: 'CSSCI 期刊论文', opt: 1, date: ''),
        _typed(typeId: ZcTypeId.paper, name: '国家级大学生创新创业训练计划项目', opt: 0, date: ''),
        _typed(typeId: ZcTypeId.honorP, name: '校优秀学生干部', date: ''),
        _typed(typeId: ZcTypeId.honorP, name: '国家奖学金', date: ''),
      ], catalog);
      final items = linkedValuesOf(links);
      final labels = [for (final i in items) catalog.optionById(i.optionId)!.label];
      expect(labels, contains('实用新型专利第二发明人（第三发明人以下不加分）'));
      expect(labels, contains('CSSCI 期刊文章第一作者'));
      expect(labels, contains('国家级大学生创新创业训练计划项目课题负责人'));
      // 综合类做**最长包含**匹配：'校优秀学生干部' 不能落到 '校优秀学生'。
      expect(labels, contains('校优秀学生干部'));
      expect(labels, contains('国家奖学金'));
      expect(items.firstWhere((i) => i.optionLabel == '国家奖学金').category, BonusCategory.honor);
      // 未计入的四条：第三发明人（无档）、第二登记人、第二作者、第二作者。
      final reasons = [for (final l in unlinkedOf(links)) l.reason!];
      expect(reasons, hasLength(3));
      for (final r in reasons) {
        expect(r, contains('没有与这项对应的条目'));
      }
    });

    test('外语材料不进附加分（明确说明原因）', () {
      final links = materialBonusItemLinks([
        _typed(typeId: ZcTypeId.foreign, name: '大学英语四级'),
      ], _bonusCatalog());
      expect(linkedValuesOf(links), isEmpty);
      expect(unlinkedOf(links).single.reason, contains('外语水平不在附加分目录里'));
    });
  });

  group('id / 排名 辅助口径', () {
    test('自动条目 id 可逆', () {
      final id = materialAwardIdOf('abc-123');
      expect(id, '${kMaterialAwardIdPrefix}abc-123');
      expect(materialIdOfAwardId(id), 'abc-123');
      expect(materialIdOfAwardId('rec-1-2'), isNull);
    });

    test('材料备注里写了排名才认（推免排名系数用）', () {
      expect(materialRankOf(_contest(name: 'x', note: '队内排名第 3')), 3);
      expect(materialRankOf(_contest(name: 'x', note: '第 12 名')), 12);
      expect(materialRankOf(_contest(name: 'x', note: 'C++ B组')), isNull);
      expect(materialRankOf(_contest(name: 'x', note: '')), isNull);
    });
  });

  // 忽略是**可逆**的（用户 2026-09-18：「竞赛奖励功能里可以忽略某些项，但是没有
  // 恢复手段」）：被忽略的条目要从「材料库没算进来」里分出来，页面才好给「恢复」。
  group('忽略 / 恢复（splitIgnoredMaterials）', () {
    List<MaterialAwardLink<CompetitionAwardRecord>> awardLinks({
      Set<String> excluded = const {},
    }) => materialAwardRecordLinks([
      _contest(id: 'ok', name: '中国高校计算机大赛'),
      _contest(id: 'iv', name: '校级程序设计竞赛', level: 2),
      _contest(id: 'ignored', name: '蓝桥杯全国软件和信息技术专业人才大赛'),
    ], excludedMaterialIds: excluded, existing: const []);

    test('被忽略的材料 reason 用统一常量（页面不靠文案判断，但仍要能读懂）', () {
      final links = awardLinks(excluded: {'ignored'});
      final hit = links.firstWhere((l) => l.material.id == 'ignored');
      expect(hit.linked, isFalse);
      expect(hit.reason, kMaterialIgnoredReason);
      // 进忽略名单的不会生成记录 → 不会进合计。
      expect(linkedValuesOf(links).map((r) => r.id), isNot(contains('material:ignored')));
    });

    test('忽略名单为空时全部落在 skipped（行为与从前一致）', () {
      final split = splitIgnoredMaterials(awardLinks(), const {});
      expect(split.ignored, isEmpty);
      expect(split.skipped.map((l) => l.material.id), ['iv']);
    });

    test('按忽略名单拆成两拨：ignored 只装被忽略的，其余仍归 skipped', () {
      final split = splitIgnoredMaterials(awardLinks(excluded: {'ignored'}), {
        'ignored',
      });
      expect(split.ignored.map((l) => l.material.id), ['ignored']);
      expect(split.skipped.map((l) => l.material.id), ['iv']);
      // 已生成的条目（`ok`）两拨都不占位 —— 它在记录列表里。
      expect(
        [...split.ignored, ...split.skipped].map((l) => l.material.id),
        isNot(contains('ok')),
      );
    });

    test('材料改坏后仍在忽略名单里 → 仍可恢复（判据是名单不是文案）', () {
      // 这条现在认不出（校级），但用户之前忽略过它，页面必须还能给「恢复」。
      final links = materialAwardRecordLinks([
        _contest(id: 'was-ok', name: '某省赛', level: 2),
      ], excludedMaterialIds: const {}, existing: const []);
      expect(links.single.linked, isFalse);
      expect(links.single.reason, isNot(kMaterialIgnoredReason));
      final split = splitIgnoredMaterials(links, {'was-ok'});
      expect(split.ignored.single.material.id, 'was-ok');
      expect(split.skipped, isEmpty);
    });

    test('推免侧同构（泛型对两个 bridge 都成立）', () {
      final links = materialBonusItemLinks([
        _typed(typeId: ZcTypeId.honorP, name: '三好学生'),
        _contest(id: 'm1', name: '中国高校计算机大赛'),
      ], _bonusCatalog(), excludedMaterialIds: {'m1'});
      final split = splitIgnoredMaterials(links, {'m1'});
      expect(split.ignored.map((l) => l.material.id), ['m1']);
      expect(split.ignored.single.material.displayName, '中国高校计算机大赛');
      // 被忽略的那条**只**出现在 ignored 里，skipped 里不能有它（否则页面会重复列）。
      expect(split.skipped.map((l) => l.material.id), isNot(contains('m1')));
    });
  });
}
