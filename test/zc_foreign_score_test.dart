/// 综测 · 材料口径守卫：
/// 1. 外语按**证书名目**录入，分值**按表 10 档位识别**（用户 2026-09-17 二轮原话：
///    「四级加分有误，我四级 489 分，导致了加分加了 489，但是实际要按挡位识别」）；
/// 2. 材料**不分学年**（材料库不再按学年过滤/切换，综测全量计入）；
/// 3. 综测智育加权显示**保留 2 位**；
/// 4. 日期选择器年份下限 = **入学年**（见 `test/materials_wizard_test.dart`）；
/// 5. 日期块顶部显示**周一到周日**并对齐（见 `test/grid_date_picker_test.dart`）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_foreign.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

ZcMaterial _m(
  ZcTypeId id, {
  int level = 0,
  double? manualScore,
  String name = '',
}) => ZcMaterial(
  id: 'x',
  typeId: id,
  name: name,
  dateIso: '2026-03-01',
  level: level,
  manualScore: manualScore,
);

void main() {
  group('外语：证书名目 + 表 10 档位识别', () {
    test('类型声明为 manualScore，其余类型不受影响', () {
      expect(zcTypeSpecOf[ZcTypeId.foreign]!.manualScore, isTrue);
      expect(zcTypeSpecOf[ZcTypeId.contest]!.manualScore, isFalse);
      expect(zcTypeSpecOf[ZcTypeId.paper]!.manualScore, isFalse);
      expect(zcTypeSpecOf[ZcTypeId.startup]!.manualScore, isFalse);
    });

    test('目录：13 条名目、无重复、门槛从高到低', () {
      expect(zcForeignCatalog.length, 13);
      final names = zcForeignCertNames;
      expect(names.toSet().length, names.length, reason: '名目不得重复');
      expect(names.first, '雅思');
      expect(
        names,
        containsAll(['托福', 'GRE', '日语 N1', '大学英语四级', '四六级（艺术体育类）六级']),
      );
      for (final c in zcForeignCatalog) {
        final thresholds = [
          for (final b in c.bands)
            if (b.threshold != null) b.threshold!,
        ];
        expect(
          thresholds,
          orderedEquals([...thresholds]..sort((a, b) => b.compareTo(a))),
          reason: '${c.name} 门槛必须从高到低（查档取第一个满足的）',
        );
        expect(c.bands, isNotEmpty);
      }
    });

    test('★ 回归：四级 489 分 → 1 分（不是 489）', () {
      expect(zcForeignAward(name: '大学英语四级', rawScore: 489), 1);
      expect(
        zcMaterialValue(_m(ZcTypeId.foreign, name: '大学英语四级', manualScore: 489)),
        1,
      );
      // 未达线 425 不加分（但也绝不是原始分）
      expect(zcForeignAward(name: '大学英语四级', rawScore: 400), 0);
      expect(
        zcMaterialValue(_m(ZcTypeId.foreign, name: '大学英语四级', manualScore: 400)),
        0,
      );
    });

    test('各证书档位识别', () {
      expect(zcForeignAward(name: '大学英语六级', rawScore: 500), 2);
      expect(zcForeignAward(name: '大学英语六级', rawScore: 424), 0);
      expect(zcForeignAward(name: '四六级（艺术体育类）六级', rawScore: 500), 3);
      expect(zcForeignAward(name: '四六级（艺术体育类）四级', rawScore: 489), 1.5);
      expect(zcForeignAward(name: '雅思', rawScore: 6.5), 2);
      expect(zcForeignAward(name: '雅思', rawScore: 6.0), 1);
      expect(zcForeignAward(name: '雅思', rawScore: 5.5), 0);
      expect(zcForeignAward(name: '托福', rawScore: 90), 1);
      expect(zcForeignAward(name: '托福', rawScore: 100), 2);
      expect(zcForeignAward(name: 'GRE', rawScore: 315), 1);
      expect(zcForeignAward(name: 'GRE', rawScore: 320), 2);
    });

    test('等级类证书：无需填分，直接取固定分', () {
      expect(zcForeignCertOf('日语 N1')!.needsScore, isFalse);
      expect(zcForeignAward(name: '日语 N1'), 2);
      expect(zcForeignAward(name: '日语 N2'), 1);
      expect(zcForeignAward(name: '英/日专业八级'), 2);
      expect(zcForeignAward(name: '英/日专业四级'), 1);
      expect(zcForeignAward(name: '韩语 TOPIK 四级'), 1);
      expect(
        zcMaterialValue(_m(ZcTypeId.foreign, name: '日语 N1', manualScore: null)),
        2,
      );
    });

    test('目录外「其他证书」：手填分值上限 2 分，未填 → 回退旧档位', () {
      expect(zcForeignAward(name: '某省翻译大赛证书', rawScore: 1.5), 1.5);
      expect(zcForeignAward(name: '某省翻译大赛证书', rawScore: 5), 2);
      expect(zcForeignAward(name: '某省翻译大赛证书'), isNull);
      // 旧材料（只有档位下标、没有原始成绩）仍按表 10 计
      expect(zcMaterialValue(_m(ZcTypeId.foreign, level: 0)), 2);
      expect(zcMaterialValue(_m(ZcTypeId.foreign, level: 1)), 1);
      expect(zcMaterialValue(_m(ZcTypeId.foreign, name: '雅思')), 2);
    });

    test('名称容错：半角括号与空白', () {
      expect(zcForeignCertOf('四六级(艺术体育类) 六级'), isNotNull);
      expect(zcForeignCertOf(' 大学英语四级 '), isNotNull);
      expect(zcForeignCertOf('查无此证'), isNull);
      expect(zcForeignCertOf(''), isNull);
      expect(zcForeignAward(name: '四六级(艺术体育类) 六级', rawScore: 500), 3);
    });

    test('文案：显示原始成绩 → 实际加分', () {
      expect(
        zcForeignScoreLabel(name: '大学英语四级', rawScore: 489),
        '大学英语四级 489 → 1 分',
      );
      expect(
        zcForeignScoreLabel(name: '雅思', rawScore: 5.5),
        contains('未达表 10 门槛'),
      );
      expect(zcForeignScoreLabel(name: '日语 N1'), '日语 N1 → 2 分');
      expect(
        zcForeignScoreLabel(name: '其他证书', rawScore: 1.5),
        '其他证书 1.5 分（上限 2 分）',
      );
      expect(zcForeignScoreLabel(name: '大学英语四级'), '待填分数');
    });

    test('JSON 往返保留 manualScore（存的是原始成绩）；旧数据缺字段 → null', () {
      final m = _m(ZcTypeId.foreign, manualScore: 489, name: '大学英语四级');
      final back = ZcMaterial.fromJson(m.toJson());
      expect(back.manualScore, 489);
      expect(back.name, '大学英语四级');
      final json = m.toJson()..remove('manualScore');
      expect(ZcMaterial.fromJson(json).manualScore, isNull);
      expect(m.copyWith(manualScore: () => null).manualScore, isNull);
      expect(m.copyWith(manualScore: () => 6.5).manualScore, 6.5);
    });

    test('行内描述 = 证书 + 原始成绩 + 加分', () {
      expect(
        _m(ZcTypeId.foreign, name: '大学英语四级', manualScore: 489).optionLabel,
        '大学英语四级 489 → 1 分',
      );
      expect(
        _m(ZcTypeId.foreign, name: '日语 N1').optionLabel,
        '日语 N1 → 2 分',
      );
      // 未填原始成绩 → 提示待填（旧材料则显示表内档位标签）
      expect(
        _m(ZcTypeId.foreign, name: '大学英语四级').optionLabel,
        '待填分数',
      );
    });
  });

  group('材料不分学年 + 智育 2 位小数（源码守卫）', () {
    test('材料库：不按学年过滤、无学年切换条、外语填原始成绩', () {
      final src = File(
        'lib/features/materials/presentation/materials_screen.dart',
      ).readAsStringSync();
      expect(src.contains('zcFilterByYear'), isFalse, reason: '材料不分学年');
      expect(src.contains('_buildYearBar'), isFalse, reason: '学年切换条已删');
      expect(src.contains("tooltip: '上一学年'"), isFalse);
      expect(src, contains('final mats = all;'));
      expect(src, contains('原始成绩'), reason: '外语填的是原始成绩');
      expect(src, contains('zcForeignScoreLabel'), reason: '按表 10 换算后显示实际加分');
      expect(src, contains('zcForeignCertOf'));
      expect(src.contains('得分（自行填写）'), isFalse, reason: '不再手填加分');
      expect(src, contains('calendarViewerProvider'), reason: '日期下限取入学年');
      // 材料行不显示加分、右侧显示备注（用户 2026-09-17 裁定）
      expect(src.contains('zcMaterialValue'), isFalse, reason: '材料行不再算/显示加分');
      expect(src, contains('m.note.trim()'), reason: '右侧显示备注');
    });

    test('外语目录唯一来源 = zc_foreign.dart（zc_rules 不再自建名目表）', () {
      final rules = File(
        'lib/features/zongce/domain/zc_rules.dart',
      ).readAsStringSync();
      expect(rules.contains('zcForeignCertNames = ['), isFalse);
      expect(rules.contains('zcForeignBandsOf'), isFalse);
      expect(rules, contains('zc_foreign.dart'), reason: '指向新目录');
      final foreign = File(
        'lib/features/zongce/domain/zc_foreign.dart',
      ).readAsStringSync();
      expect(foreign, contains('kZcForeignOtherCap = 2'));
      expect(foreign, contains('kZcForeignTotalCap = 4'));
    });

    test('综测页：材料全量计入，加权显示 2 位', () {
      final src = File(
        'lib/features/zongce/presentation/zongce_screen.dart',
      ).readAsStringSync();
      expect(src, contains('final mats = all;'));
      expect(src.contains('zcFilterByYear'), isFalse);
      expect(src, contains('_fmt2(r.weightUsed)'));
      expect(src, contains('v.toStringAsFixed(2)'));
      // 自动源仍按学年（用户 2026-09-16 裁定）——别被这轮改坏
      expect(src, contains('ref.watch(zcAutoWeightProvider(_year))'));
      expect(src, contains('ref.watch(zcAutoVolunteerProvider(_year))'));
    });
  });
}
