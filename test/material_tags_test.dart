import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/materials/presentation/material_tags.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

/// 用户 2026-09-18：「材料库条目的备注颜色不用那么浅，颜色可以和标题一致，
/// 底部的国家级/省级、一二三等奖 I/II/III/IV 类赛的颜色也不用那么浅，
/// 并且按不同类别属性，要显示为不同色的胶囊」。
ZcMaterial _mat({
  String id = 'm1',
  ZcTypeId type = ZcTypeId.contest,
  String name = '测试竞赛',
  String cat = 'c1',
  int level = 0,
  int opt = 0,
  double? manualScore,
  String note = '',
}) => ZcMaterial(
  id: id,
  typeId: type,
  name: name,
  dateIso: '2026-05-01',
  cat: cat,
  level: level,
  opt: opt,
  manualScore: manualScore,
  note: note,
);

void main() {
  group('属性取色（浅色值）', () {
    test('级别：国家级 / 省级 / 校级 / 院级 各不相同', () {
      final colors = {
        materialAttributeColor('国家级'),
        materialAttributeColor('省级'),
        materialAttributeColor('校级'),
        materialAttributeColor('院级'),
      };
      expect(colors.length, 4, reason: '四个级别要四种颜色');
      expect(materialAttributeColor('国家级'), const Color(0xFFB3261E));
      expect(materialAttributeColor('省级'), const Color(0xFFE65100));
      expect(materialAttributeColor('市（校）级'), const Color(0xFF1565C0));
    });

    test('奖项：一等 / 二等 / 三等 各不相同，且都不是中性色', () {
      final gold = materialAttributeColor('一等奖');
      final silver = materialAttributeColor('二等奖');
      final bronze = materialAttributeColor('三等奖');
      expect({gold, silver, bronze}.length, 3);
      expect(materialAttributeColor('特等奖'), const Color(0xFFB8860B));
      expect(materialAttributeColor('优胜奖'), const Color(0xFF00838F));
      expect(materialAttributeColor('未获奖'), const Color(0xFF757575));
      expect(gold, isNot(materialTypeColor));
      expect(bronze, isNot(materialTypeColor));
    });

    test('类别：Ⅰ~Ⅳ 类赛四色，未知类别回退中性色', () {
      final colors = {
        for (final c in const ['c1', 'c2', 'c3', 'c4']) materialCategoryColor(c),
      };
      expect(colors.length, 4);
      expect(materialCategoryColor('c1'), const Color(0xFFB3261E));
      expect(materialCategoryColor('c4'), const Color(0xFF00695C));
      expect(materialCategoryColor('c9'), materialTypeColor);
      expect(materialAttributeColor(''), materialTypeColor);
    });

    test('档位文案去掉「（x 分）」后缀', () {
      expect(materialLevelShort('国家级（5 分）'), '国家级');
      expect(materialLevelShort('校学生会主席（3.5 分）'), '校学生会主席');
      expect(materialLevelShort('省级'), '省级');
    });
  });

  group('materialLevelTags', () {
    Future<void> pumpTags(WidgetTester tester, ZcMaterial m) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  Wrap(children: materialLevelTags(context, m)),
            ),
          ),
        ),
      );
    }

    testWidgets('竞赛：级别 + 奖项 两枚胶囊，且不同色', (tester) async {
      await pumpTags(tester, _mat(level: 0, opt: 0));
      final tags = tester
          .widgetList<MaterialTag>(find.byType(MaterialTag))
          .toList();
      expect(tags.map((t) => t.text).toList(), ['国家级', '特等奖']);
      expect(tags.map((t) => t.color).toSet().length, 2);
    });

    testWidgets('外语：只出一枚「原始成绩」胶囊（材料库不印综测换算文案）', (tester) async {
      // 用户 2026-09-18：「材料库不是综测的材料库，因此里面的四级证书这样的，
      // 不需要显示『大学英语四级 489 → 1 分』而是直接显示『489』就可以了」。
      await pumpTags(
        tester,
        _mat(type: ZcTypeId.foreign, name: '大学英语四级', manualScore: 489),
      );
      final tags = tester
          .widgetList<MaterialTag>(find.byType(MaterialTag))
          .toList();
      expect(tags.length, 1);
      expect(tags.single.text, '489');
      expect(tags.single.text, isNot(contains('→')));
      expect(tags.single.text, isNot(contains('分')));
    });

    testWidgets('外语等级类证书（无原始成绩）→ 不出胶囊，也不回落到换算文案', (tester) async {
      await pumpTags(tester, _mat(type: ZcTypeId.foreign, name: '日语 N1'));
      expect(find.byType(MaterialTag), findsNothing);
    });

    testWidgets('越界的下标不崩、且不出胶囊', (tester) async {
      await pumpTags(tester, _mat(level: 99, opt: 99));
      expect(find.byType(MaterialTag), findsNothing);
    });
  });

  group('MaterialTag 渲染', () {
    testWidgets('深色文字 + 同色底 + 同色描边（浅色下也不再是浅灰）', (tester) async {
      const accent = Color(0xFFB3261E);
      late Color expected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                expected = AppColors.tone(context, accent);
                return const MaterialTag(text: 'Ⅰ类', color: accent);
              },
            ),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('Ⅰ类'));
      expect(text.style?.color, expected);
      expect(text.style?.fontWeight, FontWeight.w600);
      final deco =
          tester.widget<Container>(find.byType(Container)).decoration!
              as BoxDecoration;
      expect(deco.color, isNotNull);
      expect(deco.color, isNot(Colors.transparent));
      expect((deco.border! as Border).top.color.a, greaterThan(0.2));
    });
  });

  group('源码守卫：材料行（用户 2026-09-18）', () {
    final src = File(
      'lib/features/materials/presentation/materials_screen.dart',
    ).readAsStringSync();

    test('备注颜色与标题一致（不再是 outline 浅灰）', () {
      expect(
        src,
        contains('style: TextStyle(fontSize: 11, color: scheme.onSurface)'),
      );
      expect(src, contains('备注颜色与标题一致'));
    });

    test('副标题改成属性胶囊，不再是一行浅灰纯文本', () {
      expect(src, contains('MaterialTag('));
      expect(src, contains('...materialLevelTags(context, m)'));
      expect(src, contains('materialCategoryColor(m.cat)'));
      final row = src.substring(
        src.indexOf('Widget _materialRow('),
        src.indexOf('Future<void> _addMaterial()'),
      );
      expect(
        row.contains(".where((x) => x.isNotEmpty).join(' · ')"),
        isFalse,
        reason: '旧的「类型 · 类别 · 奖项 · 日期」浅灰串已删',
      );
    });
  });
}
