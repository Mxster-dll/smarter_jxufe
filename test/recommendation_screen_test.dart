import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/ims/grades/domain/recommendation_weighted.dart';
import 'package:smarter_jxufe/features/recommendation/data/bonus_catalog_parser.dart';
import 'package:smarter_jxufe/features/recommendation/data/providers/recommendation_providers.dart';
import 'package:smarter_jxufe/features/recommendation/data/recommendation_store.dart';
import 'package:smarter_jxufe/features/recommendation/domain/bonus_catalog.dart';
import 'package:smarter_jxufe/features/recommendation/domain/recommendation_calc.dart';
import 'package:smarter_jxufe/features/recommendation/domain/recommendation_item.dart';
import 'package:smarter_jxufe/features/recommendation/presentation/recommendation_screen.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

/// 推免成绩页面守卫。
///
/// fixture **刻意用资料库真实文件**（`assets/rules/text/r08a.md`）现解码，
/// 顺带守住解析器：目录一旦解析不出来，本文件的用例会先红。
const String _pagePath =
    'lib/features/recommendation/presentation/recommendation_screen.dart';

/// 固定一份推免加权结果（主干 20 门 42 学分 / 非主干 6 门 18 学分）。
const RecommendationWeighted _weighted = RecommendationWeighted(
  coreAverage: 92.10,
  nonCoreAverage: 91.40,
  coreCredits: 42,
  nonCoreCredits: 18,
  coreCount: 20,
  nonCoreCount: 6,
  score: 91.86,
);

const RecommendationWeightedResult _available = RecommendationWeightedResult(
  weighted: _weighted,
  importanceAvailable: true,
);

/// 让页面 / 弹层把 provider 的异步结果落地，但**不用 `pumpAndSettle`**
/// （页面里有 `CircularProgressIndicator`，无限动画会让 `pumpAndSettle` 超时）。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

/// 只读内存版 store：不碰 Hive（`add/save` 是真异步 I/O，widget 测试里会挂死）。
class _MemoryStore extends RecommendationStore {
  _MemoryStore(this._seed) : super(account: '');

  final List<RecommendationBonusItem> _seed;

  /// 「忽略」名单也放内存（自动带入的条目由材料库现算，忽略名单才落库）。
  final Set<String> _excluded = {};

  @override
  List<RecommendationBonusItem> get items => _seed;

  @override
  Set<String> get excludedMaterialIds => _excluded;

  @override
  bool get loaded => true;

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<void> excludeMaterial(String materialId) async {
    _excluded.add(materialId);
    notifyListeners();
  }

  @override
  Future<void> includeMaterial(String materialId) async {
    _excluded.remove(materialId);
    notifyListeners();
  }
}

bool _saveEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('recSaveItem')))
        .onPressed !=
    null;

void main() {
  late BonusCatalog catalog;

  setUpAll(() {
    catalog = parseBonusCatalog(
      File('assets/rules/text/r08a.md').readAsStringSync(),
    );
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required RecommendationWeightedResult weighted,
    List<RecommendationBonusItem> items = const [],
    List<ZcMaterial> materials = const [],
    BonusCatalog? overrideCatalog,
    _MemoryStore? store,
  }) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bonusCatalogProvider.overrideWith(
            (ref) async => overrideCatalog ?? catalog,
          ),
          recommendationWeightedResultProvider.overrideWith(
            (ref) async => weighted,
          ),
          recommendationRuleDocProvider.overrideWith((ref) async => null),
          recommendationStoreProvider.overrideWith(
            (ref) => store ?? _MemoryStore(items),
          ),
          // 材料库：自动带入的来源（不 override 会去开 Hive）。
          zcMaterialsProvider.overrideWith((ref) async => materials),
        ],
        child: MaterialApp(
          theme: appLightTheme,
          home: const RecommendationScreen(),
        ),
      ),
    );
    await _settle(tester);
  }

  /// 一条学科竞赛材料（`level`：0=国家级 1=省级 2=校级；`opt`：0=特等 1=一等 2=二等 3=三等）。
  ZcMaterial contestMaterial({
    String id = 'm1',
    String name = '中国高校计算机大赛',
    String cat = 'c2',
    int level = 0,
    int opt = 1,
    String date = '2026-05-06',
    String note = '',
  }) => ZcMaterial(
    id: id,
    typeId: ZcTypeId.contest,
    name: name,
    cat: cat,
    level: level,
    opt: opt,
    dateIso: date,
    note: note,
  );

  RecommendationBonusItem contestItem(
    String id, {
    String? tier,
    int? rank,
    DateTime? date,
  }) {
    final option = catalog.optionsOf(BonusCategory.contest).first;
    return RecommendationBonusItem(
      id: id,
      category: BonusCategory.contest,
      optionId: option.id,
      optionLabel: option.label,
      tierLabel: tier,
      rank: rank,
      awardDate: date,
    );
  }

  RecommendationBonusItem honorItem(String id) {
    final option = catalog.optionsOf(BonusCategory.honor).first;
    return RecommendationBonusItem(
      id: id,
      category: BonusCategory.honor,
      optionId: option.id,
      optionLabel: option.label,
    );
  }

  test('真实资料库解析出五大类加分项（fixture 自检）', () {
    expect(catalog.hasData, isTrue);
    for (final c in BonusCategory.values) {
      expect(
        catalog.optionsOf(c),
        isNotEmpty,
        reason: '${c.label} 应能从 r08a 解析出项目',
      );
    }
    expect(catalog.cap, 10);
  });

  testWidgets('汇总卡显示综合成绩与三段构成', (tester) async {
    final items = [honorItem('rec-1')];
    final outcome = recommendationOutcomeOf(
      weightedAverage: _weighted.score,
      items: items,
      catalog: catalog,
    );
    await pumpPage(tester, weighted: _available, items: items);

    expect(find.byKey(const Key('recSummaryCard')), findsOneWidget);
    expect(find.text('综合成绩'), findsOneWidget);
    expect(find.text('91.86'), findsOneWidget);
    expect(find.text('推免加权平均成绩'), findsOneWidget);
    // 「附加分」行（限定在汇总卡内，避免与条目行的 +X.XX 撞车）。
    expect(
      find.descendant(
        of: find.byKey(const Key('recSummaryCard')),
        matching: find.textContaining(
          '+${outcome.bonusTotal.toStringAsFixed(2)}',
        ),
      ),
      findsOneWidget,
    );
    // 大号总分 + 「= 综合成绩」行各一次。
    expect(
      find.text(outcome.total.toStringAsFixed(2)),
      findsWidgets,
    );

    // 默认收起，点开才显示主干 / 非主干口径。
    expect(find.textContaining('主干课程'), findsNothing);
    await _tap(tester, find.byKey(const Key('recWeightedToggle')));
    expect(find.textContaining('主干课程 42 学分'), findsOneWidget);
    expect(find.textContaining('非主干课程 18 学分'), findsOneWidget);
    expect(find.text('口径：主干×0.7 + 非主干×0.3'), findsOneWidget);
    expect(find.textContaining('参与计算 26 门'), findsOneWidget);
  });

  testWidgets('培养方案未就绪时提示并给出重试', (tester) async {
    await pumpPage(
      tester,
      weighted: RecommendationWeightedResult.unavailable,
      items: [honorItem('rec-1')],
    );

    expect(
      find.text('培养方案未就绪，推免加权暂不可算'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('recRetryWeighted')), findsOneWidget);
    // 未就绪时不显示总分（0 分是误导）。
    expect(find.text('0.00'), findsNothing);
  });

  testWidgets('加分项按类别分组，未计入的条目标出原因', (tester) async {
    final counted = contestItem('rec-1', tier: '金奖', rank: 1);
    final missingTier = contestItem('rec-2');
    final honor = honorItem('rec-3');
    final items = [counted, missingTier, honor];
    await pumpPage(tester, weighted: _available, items: items);

    expect(find.byKey(const Key('recBonusCard')), findsOneWidget);
    expect(find.text('竞赛类'), findsOneWidget);
    expect(find.text('综合类'), findsOneWidget);
    expect(find.byKey(const Key('recItemTile-rec-1')), findsOneWidget);
    expect(find.byKey(const Key('recItemTile-rec-2')), findsOneWidget);
    expect(find.byKey(const Key('recItemTile-rec-3')), findsOneWidget);
    expect(find.byKey(const Key('recDeleteItem-rec-1')), findsOneWidget);
    // 未选等级的条目要说明「为什么不加分」。
    expect(find.textContaining('未选择获奖等级，无法计分'), findsOneWidget);
    expect(find.textContaining('同类只计一项，不累加'), findsOneWidget);
  });

  testWidgets('点「添加」打开弹层，选项目后可保存', (tester) async {
    await pumpPage(tester, weighted: _available);
    // 空态文案在 2026-09-18 改成「材料库自动带入」口径（自动化的主路径在前）。
    expect(
      find.textContaining('还没有加分项。材料库里登记的竞赛'),
      findsOneWidget,
    );

    await _tap(tester, find.byKey(const Key('recAddItem')));
    expect(find.text('添加加分项'), findsOneWidget);
    expect(find.byKey(const Key('recOptionSearch')), findsOneWidget);
    expect(find.byKey(const Key('recCategoryChip-contest')), findsOneWidget);
    expect(find.byKey(const Key('recRankField')), findsOneWidget);
    expect(find.byKey(const Key('recDateField')), findsOneWidget);
    expect(find.byKey(const Key('recNoteField')), findsOneWidget);

    final option = catalog.optionsOf(BonusCategory.contest).first;
    expect(find.byKey(Key('recOptionTile-${option.id}')), findsOneWidget);
    await _tap(tester, find.byKey(Key('recOptionTile-${option.id}')));

    if (option.tiers.length > 1) {
      expect(_saveEnabled(tester), isFalse, reason: '未选获奖等级时不能保存');
    }
    final tier = option.tiers.first;
    await _tap(tester, find.byKey(Key('recTierChip-${tier.label}')));
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('同一类别登记两项时出现不累加对照卡', (tester) async {
    final items = [
      contestItem('rec-1', tier: '金奖', rank: 1),
      contestItem('rec-2', tier: '银奖', rank: 2),
    ];
    await pumpPage(tester, weighted: _available, items: items);

    expect(find.byKey(const Key('recCompareCard')), findsOneWidget);
    expect(find.text('办法口径（每类只计一项）'), findsOneWidget);
    expect(find.text('若按条目累加（对照）'), findsOneWidget);
  });

  testWidgets('没有条目时不显示对照卡，规则出处卡仍在', (tester) async {
    await pumpPage(tester, weighted: _available);

    expect(find.byKey(const Key('recCompareCard')), findsNothing);
    expect(find.byKey(const Key('recRulesCard')), findsOneWidget);
    expect(find.byKey(const Key('recOpenSource')), findsOneWidget);
    // 资料库文档取不到时原文入口禁用。
    final button = tester.widget<TextButton>(
      find.byKey(const Key('recOpenSource')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('资料库解析不到加分标准时给出提示与重试', (tester) async {
    await pumpPage(
      tester,
      weighted: _available,
      overrideCatalog: BonusCatalog.empty,
    );

    expect(find.byKey(const Key('recBonusCard')), findsNothing);
    expect(find.textContaining('资料库未解析到加分标准'), findsOneWidget);
    expect(find.text('重新解析'), findsOneWidget);
  });

  group('材料库自动带入（2026-09-18 用户裁定）', () {
    testWidgets('材料库里的国家级竞赛材料自动计入附加分，并打「材料库」徽标', (tester) async {
      // 中国高校计算机大赛（Ⅱ类）国家级一等奖 → 加分标准「排行榜目录 / 非主体赛道」档
      // 第一等次奖 2 分；竞赛类每类只计一项 → 附加分 2.00。
      await pumpPage(
        tester,
        weighted: _available,
        materials: [contestMaterial(id: 'm1', opt: 1)],
      );

      expect(find.byKey(const Key('recAutoBadge-material:m1')), findsOneWidget);
      expect(find.text('材料库'), findsOneWidget);
      expect(find.textContaining('附加分 2.00 分'), findsOneWidget);
      expect(find.byKey(const Key('recIgnoreItem-material:m1')), findsOneWidget);
      // 自动条目不给删除按钮（删了材料库就变，改成「忽略」）。
      expect(find.byKey(const Key('recDeleteItem-material:m1')), findsNothing);
    });

    testWidgets('点「忽略」后该条不再计入，并出现在「已忽略」清单里（可恢复）', (tester) async {
      final store = _MemoryStore(const []);
      await pumpPage(
        tester,
        weighted: _available,
        materials: [contestMaterial(id: 'm1', opt: 1)],
        store: store,
      );
      expect(find.textContaining('附加分 2.00 分'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('recIgnoreItem-material:m1')));

      expect(store.excludedMaterialIds, contains('m1'));
      expect(find.byKey(const Key('recAutoBadge-material:m1')), findsNothing);
      expect(find.textContaining('附加分 0.00 分'), findsOneWidget);
      // 被忽略的条目单列一节，并给「恢复」（用户 2026-09-18：「可以忽略某些项，
      // 但是没有恢复手段」）。
      expect(find.byKey(const Key('recIgnoredMaterials')), findsOneWidget);
      expect(find.text('已忽略 1 条'), findsOneWidget);
      expect(
        find.byKey(const Key('recRestoreMaterial-m1')),
        findsOneWidget,
      );
      // 它**不再**混在「材料库没算进来」那节里（那节是材料库的问题，不是你的选择）。
      expect(find.byKey(const Key('recSkippedMaterials')), findsNothing);
    });

    testWidgets('点「恢复」后该条重新计入，忽略名单清空', (tester) async {
      final store = _MemoryStore(const []);
      await pumpPage(
        tester,
        weighted: _available,
        materials: [contestMaterial(id: 'm1', opt: 1)],
        store: store,
      );
      await _tap(tester, find.byKey(const Key('recIgnoreItem-material:m1')));
      expect(find.textContaining('附加分 0.00 分'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('recRestoreMaterial-m1')));

      expect(store.excludedMaterialIds, isNot(contains('m1')));
      expect(find.byKey(const Key('recIgnoredMaterials')), findsNothing);
      expect(find.byKey(const Key('recAutoBadge-material:m1')), findsOneWidget);
      expect(find.textContaining('附加分 2.00 分'), findsOneWidget);
    });

    testWidgets('校级竞赛不计入，且在未计入清单里说明原因', (tester) async {
      await pumpPage(
        tester,
        weighted: _available,
        materials: [
          contestMaterial(id: 'm2', name: '某校赛', level: 2, opt: 1),
        ],
      );

      expect(find.byKey(const Key('recSkippedMaterials')), findsOneWidget);
      expect(find.textContaining('材料库里还有 1 条没算进来'), findsOneWidget);
      expect(find.textContaining('只认国家级'), findsOneWidget);
      expect(find.textContaining('附加分 0.00 分'), findsOneWidget);
    });

    testWidgets('手工登记的条目行为不变（可删，无徽标）', (tester) async {
      final items = [honorItem('rec-manual')];
      await pumpPage(tester, weighted: _available, items: items);

      expect(find.byKey(const Key('recAutoBadge-rec-manual')), findsNothing);
      expect(find.byKey(const Key('recDeleteItem-rec-manual')), findsOneWidget);
      expect(find.byKey(const Key('recIgnoreItem-rec-manual')), findsNothing);
    });
  });

  test('源码守卫：走 paneAppBar，且不硬编码颜色', () {
    final src = File(_pagePath).readAsStringSync();
    expect(src.contains('paneAppBar('), isTrue);
    expect(src.contains('Color(0xFF'), isFalse);
    // 裸 `Colors.xxx` 也不行（`AppColors.xxx` 不算）。
    expect(
      RegExp(r'(?<![A-Za-z])Colors\.').hasMatch(src),
      isFalse,
      reason: '颜色一律走 AppColors / fp(context)',
    );
  });
}
