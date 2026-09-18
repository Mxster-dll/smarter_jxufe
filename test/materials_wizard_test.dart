/// 材料库「添加材料」向导（用户 2026-09-17 五条改造）守卫：
/// 1. 竞赛从目录选定后，比赛名与类别是**固定项**（自定义竞赛除外）；
/// 2. 竞赛不填「组织单位」；
/// 3. 日期用通用三宫格选择器（`showGridDatePicker`）；
/// 4. 级别 / 奖项不再用下拉，而是一排按钮；
/// 5. 保存后**停留在活动候选页**，可连续添加。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/materials/presentation/materials_screen.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_prefs_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_store.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_engine.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_rules.dart';
import 'package:smarter_jxufe/shared/widgets/grid_date_picker.dart';

/// 内存版存储：**不碰 Hive 落盘**。
///
/// ⚠ 实测教训：用真 `ZcStore`（Hive 文件写入）时，写入完成的真实异步回调会落到
/// **下一个用例**的假异步时区里 → 后续用例永远 `did not complete`（`tester.runAsync`
/// 也救不了）。保存路径的守卫改用内存 store，读写都在微任务里完成。
class _MemoryStore extends ZcStore {
  _MemoryStore(super.box, super.filesDir);

  final List<ZcMaterial> items = [];

  @override
  Future<List<ZcMaterial>> loadMaterials() async => List.of(items);

  @override
  Future<void> saveMaterials(List<ZcMaterial> list) async {
    items
      ..clear()
      ..addAll(list);
  }

  @override
  Future<void> deleteMaterial(List<ZcMaterial> all, ZcMaterial m) async {
    items.removeWhere((x) => x.id == m.id);
  }
}

void main() {
  late Directory dir;
  late Box<String> box;
  late _MemoryStore store;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('materials_wizard_test');
    Hive.init(dir.path);
    box = await Hive.openBox<String>('zongce_wizard_test');
  });

  setUp(() async {
    store = _MemoryStore(box, dir.path);
  });

  /// 测试包裹：学籍链（`calendarViewerProvider` → 学籍仓库）用固定入学年 stub，
  /// 否则真实 Hive 读在假异步区不会完成 → 表单弹窗永远不出现。
  Widget app({int enrollYear = 2025}) => ProviderScope(
    overrides: [
      zcStoreProvider.overrideWith((ref) async => store),
      zcMaterialsProvider.overrideWith((ref) async => store.loadMaterials()),
      calendarViewerProvider.overrideWith(
        (ref) async => CalendarViewer(enrollYear: enrollYear),
      ),
    ],
    child: MaterialApp(theme: appLightTheme, home: const MaterialsScreen()),
  );

  /// 表单在 640 高的 Dialog 里滚动，点之前必须先滚到可见。
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 保存后多推几帧，让 `_openEditor` 的异步续跑与 invalidate 落地。
  Future<void> settleSave(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  Future<void> openContestPicker(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加材料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('学科竞赛获奖'));
    await tester.pumpAndSettle();
  }

  /// 在二级页搜索并点选第一个候选（候选行 = ListTile）。
  Future<void> pickFirstCandidate(WidgetTester tester, String keyword) async {
    await tester.enterText(find.byType(TextField).first, keyword);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
  }

  testWidgets('竞赛：名称与类别是固定项、无组织单位、级别与奖项是按钮', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await openContestPicker(tester);
    expect(find.text('选择活动类型'), findsNothing, reason: '一级页已出栈');
    await pickFirstCandidate(tester, '创新大赛');

    // 固定项：名称不可编辑、类别以胶囊展示。
    // （候选页仍留在栈上，所以「同一文案」在弹窗外也有一份 → 断言限定在弹窗内。）
    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(Dialog), matching: f);
    expect(find.text('比赛项目（目录固定）'), findsOneWidget);
    expect(inDialog(find.text('中国国际大学生创新大赛')), findsOneWidget);
    expect(inDialog(find.text('类别 ${zcCatNames['c1']}')), findsOneWidget);
    expect(
      find.widgetWithText(TextField, '中国国际大学生创新大赛'),
      findsNothing,
      reason: '比赛名不再是输入框',
    );
    // 不填组织单位。
    expect(find.text('发证/组织单位'), findsNothing);
    // 级别 / 奖项 = 一排按钮（没有下拉）。
    expect(find.text('级别 / 档位'), findsOneWidget);
    expect(find.text('国家级'), findsOneWidget);
    expect(find.text('省级'), findsOneWidget);
    expect(find.text('奖项 / 细分'), findsOneWidget);
    expect(find.text(zcPrizeNames.first), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);

    // 点按钮即切换选中态。
    final scheme = Theme.of(tester.element(find.text('省级'))).colorScheme;
    await tapVisible(tester, find.text('省级'));
    final chip = tester.widget<Material>(
      find
          .ancestor(of: find.text('省级'), matching: find.byType(Material))
          .first,
    );
    expect(chip.color, scheme.primary);
  });

  testWidgets('日期改用三宫格选择器，保存后停留在竞赛选择页（可连续添加）', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await openContestPicker(tester);
    await pickFirstCandidate(tester, '创新大赛');

    // 日期：点开 → 通用三宫格（年 / 月 / 日）。
    await tapVisible(tester, find.text('选择日期'));
    expect(find.byKey(gridDatePickerKey), findsOneWidget);
    expect(find.text('年份'), findsOneWidget);
    expect(find.text('月份'), findsOneWidget);
    expect(find.text('日期'), findsOneWidget);

    final now = DateTime.now();
    await tester.tap(find.byKey(gridDateYearKey(now.year)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(gridDateMonthKey(now.month)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(gridDateDayKey(1)));
    await tester.pumpAndSettle();
    expect(find.byKey(gridDatePickerKey), findsNothing);
    final iso = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    expect(find.text(iso), findsOneWidget);

    await tapVisible(tester, find.text('保存'));
    await settleSave(tester);

    // 停留在活动候选页（二级页从不出栈），类型页已出栈。
    expect(find.text('选择活动类型'), findsNothing);
    expect(find.textContaining('第二步 · 选择比赛'), findsOneWidget);
    expect(find.textContaining('搜索比赛名称'), findsOneWidget);
    expect(
      find.text('中国国际大学生创新大赛'),
      findsWidgets,
      reason: '保存后搜索框已清空，候选重新铺开',
    );

    final saved = await store.loadMaterials();
    expect(saved, hasLength(1));
    expect(saved.single.name, '中国国际大学生创新大赛');
    expect(saved.single.cat, 'c1');
    expect(saved.single.org, isEmpty);
    expect(saved.single.dateIso, iso);

    // 连续添加第二个：还在这一页，直接再点一个候选即可。
    await pickFirstCandidate(tester, '数学建模');
    expect(find.text('比赛项目（目录固定）'), findsOneWidget);
    await tapVisible(tester, find.text('取消'));
    expect(
      find.textContaining('第二步 · 选择比赛'),
      findsOneWidget,
      reason: '取消后仍在活动候选页',
    );
  });

  testWidgets('自定义竞赛（其他比赛）仍可手填名称与类别，且同样不填组织单位', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await openContestPicker(tester);
    await pickFirstCandidate(tester, '手动录入');

    expect(find.text('比赛项目（目录固定）'), findsNothing);
    expect(find.text('名称（竞赛/论文/荣誉等）'), findsOneWidget);
    expect(find.text('类别（未识别手动选）'), findsOneWidget);
    expect(find.text('发证/组织单位'), findsNothing);
  });

  testWidgets('非竞赛类型仍保留组织单位与可编辑名称', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加材料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('论文 / 专利'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('直接填写').first);
    await tester.pumpAndSettle();

    expect(find.text('名称（竞赛/论文/荣誉等）'), findsOneWidget);
    expect(find.text('发证/组织单位'), findsOneWidget);
    expect(find.text('级别 / 档位'), findsOneWidget);
  });

  testWidgets('外语：候选按证书名目，填原始成绩并按表 10 档位识别（用户 2026-09-17 二轮）', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加材料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外语水平'));
    await tester.pumpAndSettle();

    // 二级页：候选 = 证书名目（雅思/托福/大学英语四级…），没有「雅思 ≥6.5」这类档位文案。
    expect(find.text('雅思'), findsWidgets);
    expect(find.textContaining('雅思 ≥6.5'), findsNothing);

    await tester.tap(find.text('大学英语四级'));
    await tester.pumpAndSettle();

    // 表单：填**原始成绩**（不再手填加分）+ 参考档位；无「级别 / 档位」按钮组。
    expect(find.text('原始成绩'), findsOneWidget);
    expect(find.text('级别 / 档位'), findsNothing);
    expect(find.textContaining('参考档位：大学英语四级 ≥425 → 1 分'), findsOneWidget);

    // ★ 用户报的 bug：「四级 489 分导致加分加了 489」→ 现在按档位识别。
    await tester.enterText(find.widgetWithText(TextField, '原始成绩'), '489');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('按表 10：大学英语四级 489 → 1 分'),
      findsOneWidget,
      reason: '输入原始成绩后立刻显示实际加分',
    );

    // 日期（必填）→ 今天。
    await tapVisible(tester, find.text('选择日期'));
    final now = DateTime.now();
    await tester.tap(find.byKey(gridDateYearKey(now.year)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(gridDateMonthKey(now.month)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(gridDateDayKey(1)));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('保存'));
    await settleSave(tester);

    final saved = await store.loadMaterials();
    expect(saved, hasLength(1));
    expect(saved.single.typeId, ZcTypeId.foreign);
    expect(saved.single.name, '大学英语四级');
    expect(saved.single.manualScore, 489, reason: '存的是原始成绩');
    expect(saved.single.optionLabel, '大学英语四级 489 → 1 分');
    expect(
      zcMaterialValue(saved.single),
      1,
      reason: '★ 加分 = 表 10 档位分（1 分），绝不是 489',
    );
  });

  testWidgets('外语等级类证书无需填分；材料行显示备注、不显示加分', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    store.items.add(
      const ZcMaterial(
        id: 'n1',
        typeId: ZcTypeId.foreign,
        name: '日语 N1',
        dateIso: '2026-03-01',
        note: 'N1 证书原件在档案袋',
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 行内：标题 = 证书名；**不再印综测口径的换算文案**（用户 2026-09-18：
    // 「材料库不是综测的材料库……」）→ 等级类没填原始成绩，连成绩胶囊都不出。
    expect(find.text('日语 N1'), findsWidgets, reason: '标题仍是证书名');
    expect(
      find.textContaining('→ 2 分'),
      findsNothing,
      reason: '材料库不显示综测的换算文案',
    );
    expect(find.text('N1 证书原件在档案袋'), findsOneWidget, reason: '右侧显示备注');
    expect(find.textContaining('+2'), findsNothing, reason: '材料页不显示加分');
    expect(zcMaterialValue(store.items.single), 2, reason: '综测口径仍是等级类固定分');
  });

  testWidgets('备注不受宽度限制（用户 2026-09-18：「材料库备注信息不要限制宽度」）', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const longNote = '这是一条很长的备注信息用来验证宽度不再被限制在一百三十二像素以内并可以完整显示';
    store.items.add(
      const ZcMaterial(
        id: 'long',
        typeId: ZcTypeId.contest,
        name: '蓝桥杯全国软件和信息技术专业人才大赛',
        cat: 'c2',
        level: 0,
        opt: 0,
        dateIso: '2026-06-01',
        note: longNote,
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final width = tester.getSize(find.text(longNote)).width;
    expect(
      width,
      greaterThan(200),
      reason: '旧实现套了 maxWidth: 132，长备注必然被截；现在按需占位',
    );
    expect(find.text(longNote), findsOneWidget);
  });

  testWidgets('材料库不按学年过滤：没有学年切换条（用户 2026-09-17 裁定）', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 一条「上一学年」的材料也应照常显示（旧实现会被 zcFilterByYear 过滤掉）。
    store.items.add(
      const ZcMaterial(
        id: 'old',
        typeId: ZcTypeId.foreign,
        name: '雅思',
        dateIso: '2024-05-01',
        manualScore: 2,
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byTooltip('上一学年'), findsNothing);
    expect(find.byTooltip('下一学年'), findsNothing);
    expect(find.textContaining('2024-05-01'), findsOneWidget);
    expect(find.textContaining('不区分学年'), findsOneWidget);
  });

  testWidgets('日期选择器年份下限 = 入学年（用户 2026-09-17 裁定）', (tester) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app(enrollYear: 2023));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加材料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('论文 / 专利'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('直接填写').first);
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('选择日期'));
    expect(find.byKey(gridDateYearKey(2023)), findsOneWidget, reason: '入学年可选');
    expect(
      find.byKey(gridDateYearKey(2022)),
      findsNothing,
      reason: '入学年之前的年份不在范围内',
    );
  });
}
