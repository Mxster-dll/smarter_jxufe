/// 材料库「按二级分类分组」守卫（用户 2026-09-18 九轮原话：
/// 「我希望材料库条目显示不要按综测分类，而是直接按二级分类分类，比如学科竞赛这样的」）。
///
/// 守三件事：
/// 1. 分组键 = **材料类型**（学科竞赛获奖 / 外语水平 / 文明寝室…），
///    **不是**综测的「五育」（德育 / 智育 / …）——同一育的两种类型必须落进两个组；
/// 2. 组顺序 = `zcTypeSpecs` 注册顺序（与输入顺序无关），空组不占位，
///    组内按发生时间倒序；
/// 3. 页面真的用这套口径渲染（标题 = `类型名 · 条数`），且行内不再重复印类型名。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/materials/domain/material_grouping.dart';
import 'package:smarter_jxufe/features/materials/presentation/materials_screen.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_prefs_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

ZcMaterial _m({
  required String id,
  required ZcTypeId typeId,
  String name = '',
  String dateIso = '',
}) => ZcMaterial(id: id, typeId: typeId, name: name, dateIso: dateIso);

void main() {
  group('按二级分类分组（纯函数）', () {
    test('分组键 = 材料类型，不是五育：同一育的两种类型各成一组', () {
      // 学科竞赛获奖 与 外语水平 **同属智育**（spec.dim == 'z'）——按五育分只会出
      // 一个「智育加分材料」组，按二级分类必须出两个组（这正是用户这次要的）。
      final groups = groupMaterialsByType([
        _m(id: 'a', typeId: ZcTypeId.contest),
        _m(id: 'b', typeId: ZcTypeId.foreign),
      ]);
      expect(groups.length, 2);
      expect(groups.map((g) => g.label), ['学科竞赛获奖', '外语水平']);
      expect(groups.every((g) => g.spec.dim == 'z'), isTrue, reason: '同为智育');
      expect(
        groups.map((g) => g.label).join(),
        isNot(contains('智育')),
        reason: '标题里不许再出现综测的五育名',
      );
    });

    test('组顺序 = zcTypeSpecs 注册顺序，与输入顺序无关', () {
      final mats = [
        _m(id: 'dorm', typeId: ZcTypeId.dorm),
        _m(id: 'contest', typeId: ZcTypeId.contest),
        _m(id: 'deed', typeId: ZcTypeId.deed),
        _m(id: 'foreign', typeId: ZcTypeId.foreign),
      ];
      final forward = groupMaterialsByType(mats).map((g) => g.typeId).toList();
      final backward = groupMaterialsByType(mats.reversed.toList())
          .map((g) => g.typeId)
          .toList();
      expect(forward, backward, reason: '换输入顺序不改组顺序');
      // 注册表顺序：contest(0) < foreign(2) < deed(4) < dorm(18)
      expect(forward, [
        ZcTypeId.contest,
        ZcTypeId.foreign,
        ZcTypeId.deed,
        ZcTypeId.dorm,
      ]);
      // 与注册表本身同序（防止「组顺序」被改成按数量排）。
      final registryOrder = zcTypeSpecs.map((s) => s.id).toList();
      expect(
        forward,
        registryOrder.where(forward.contains).toList(),
        reason: '组顺序必须是注册表顺序的子序列',
      );
    });

    test('空组不占位；每条材料恰好落进一个组（不静默丢行）', () {
      final mats = [
        _m(id: 'a', typeId: ZcTypeId.contest),
        _m(id: 'b', typeId: ZcTypeId.contest),
        _m(id: 'c', typeId: ZcTypeId.media),
      ];
      final groups = groupMaterialsByType(mats);
      expect(groups.length, 2, reason: '只有出现过的类型才成组');
      expect(groups.first.count, 2);
      expect(groups.last.count, 1);
      expect(
        groups.fold<int>(0, (sum, g) => sum + g.count),
        mats.length,
        reason: '不变式：输出条数之和 == 输入条数',
      );
      expect(groupMaterialsByType(const []), isEmpty);
    });

    test('组内按发生时间倒序，同日按 id 定序（排序稳定）', () {
      final groups = groupMaterialsByType([
        _m(id: 'old', typeId: ZcTypeId.contest, dateIso: '2024-05-01'),
        _m(id: 'b', typeId: ZcTypeId.contest, dateIso: '2026-06-01'),
        _m(id: 'a', typeId: ZcTypeId.contest, dateIso: '2026-06-01'),
        _m(id: 'new', typeId: ZcTypeId.contest, dateIso: '2026-09-01'),
      ]);
      expect(groups.single.materials.map((m) => m.id), [
        'new',
        'a',
        'b',
        'old',
      ]);
    });

    test('分组元数据：label / typeId / count / groupKey', () {
      final group = groupMaterialsByType([
        _m(id: 'a', typeId: ZcTypeId.foreign),
      ]).single;
      expect(group.label, '外语水平');
      expect(group.typeId, ZcTypeId.foreign);
      expect(group.count, 1);
      expect(group.groupKey, const Key('materialsGroup-foreign'));
    });
  });

  group('材料库页面渲染', () {
    Widget app(List<ZcMaterial> mats) => ProviderScope(
      overrides: [
        zcMaterialsProvider.overrideWith((ref) async => mats),
        calendarViewerProvider.overrideWith(
          (ref) async => const CalendarViewer(enrollYear: 2025),
        ),
      ],
      child: MaterialApp(theme: appLightTheme, home: const MaterialsScreen()),
    );

    void bigView(WidgetTester tester) {
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('分组标题 = 二级分类名 · 条数，且没有「智育加分材料」这种综测口径', (tester) async {
      bigView(tester);
      await tester.pumpWidget(
        app([
          _m(id: 'a', typeId: ZcTypeId.contest, name: '蓝桥杯', dateIso: '2026-06-01'),
          _m(id: 'b', typeId: ZcTypeId.contest, name: 'ICPC', dateIso: '2026-05-01'),
          _m(id: 'c', typeId: ZcTypeId.foreign, name: '大学英语四级'),
          _m(id: 'd', typeId: ZcTypeId.dorm, name: '文明寝室'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('学科竞赛获奖 · 2'), findsOneWidget);
      expect(find.text('外语水平 · 1'), findsOneWidget);
      expect(find.text('文明寝室 · 1'), findsOneWidget);
      expect(
        find.textContaining('加分材料'),
        findsNothing,
        reason: '旧标题「智育加分材料 · N」不许回来',
      );
      for (final name in const ['智育', '德育', '体育', '美育', '劳育']) {
        expect(find.textContaining(name), findsNothing, reason: '不再按五育分组');
      }

      // 顺序：注册表顺序（contest → foreign → dorm），用 Key 的纵坐标核对。
      double top(String key) =>
          tester.getTopLeft(find.byKey(Key(key))).dy;
      expect(
        top('materialsGroup-contest'),
        lessThan(top('materialsGroup-foreign')),
      );
      expect(
        top('materialsGroup-foreign'),
        lessThan(top('materialsGroup-dorm')),
      );

      // 行内不再重复印类型名（类型已是分组标题）。
      expect(
        find.text('学科竞赛获奖'),
        findsNothing,
        reason: '行内的类型胶囊已随分组标题移除',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('materialsGroup-contest')),
          matching: find.text('学科竞赛获奖 · 2'),
        ),
        findsOneWidget,
      );
      // 组内仍是时间倒序（蓝桥杯 06-01 在 ICPC 05-01 之前）。
      expect(
        tester.getTopLeft(find.text('蓝桥杯')).dy,
        lessThan(tester.getTopLeft(find.text('ICPC')).dy),
      );
    });

    testWidgets('空库仍是空态，不出现任何分组标题', (tester) async {
      bigView(tester);
      await tester.pumpWidget(app(const []));
      await tester.pumpAndSettle();
      expect(find.text('还没有证明材料'), findsOneWidget);
      expect(find.byKey(const Key('materialsGroup-contest')), findsNothing);
    });
  });

  group('源码守卫', () {
    final screen = File(
      'lib/features/materials/presentation/materials_screen.dart',
    ).readAsStringSync();
    final domain = File(
      'lib/features/materials/domain/material_grouping.dart',
    ).readAsStringSync();

    test('页面走唯一分组实现，旧的按五育分组已删除', () {
      expect(screen, contains('groupMaterialsByType(mats)'));
      expect(screen, contains(r"'${group.label} · ${group.count}'"));
      expect(screen, contains('MaterialGroup group'));
      expect(screen.contains('_dimName('), isFalse);
      expect(
        screen.contains("for (final dim in const ['z', 'd', 't', 'm', 'l'])"),
        isFalse,
        reason: '按五育分的循环不许回来',
      );
      expect(RegExp(r"加分材料 · ").hasMatch(screen), isFalse);
    });

    test('分组唯一实现挂在 domain，组顺序取自注册表', () {
      expect(domain, contains('List<MaterialGroup> groupMaterialsByType('));
      expect(domain, contains('for (final spec in zcTypeSpecs)'));
      expect(domain, contains('Key(\'materialsGroup-\${spec.id.name}\')'));
    });

    test('材料库条目不再用五育口径（presentation 内不得按 dim 分）', () {
      final files = Directory('lib/features/materials/presentation')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        final src = f.readAsStringSync();
        expect(
          src.contains('.spec.dim'),
          isFalse,
          reason: '${f.path} 里还有按五育（spec.dim）分组的代码',
        );
      }
    });
  });
}
