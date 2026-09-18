/// 竞赛奖励页守卫（2026-09-17 加；2026-09-18 加「材料库自动带入」三例、
/// 「未计入只变暗不印第九条」一例）。
///
/// 覆盖：首屏四张卡 / **手动时间范围**（预设切换后只算区间内的记录、区外标注原因、
/// 「清除」回全部）/ 添加 · 编辑 · 删除三条记录链 / **材料库自动带入**（自动行带
/// 「材料库」徽标并计入合计 · 「忽略」后行消失且合计回落 · 认不出的材料进
/// 「未计入」小节）/ **未计入的两档表现**（被取最高挤掉 → 只变暗；算不出来 → 变暗 +
/// 给原因）/ 目录浏览搜索 / 源码守卫。
///
/// 三条测试纪律（与 `test/recommendation_screen_test.dart` 同款）：
/// 1. **不用 `pumpAndSettle`**：页面挂了 `PageAutoRefresher`（首帧后会失效资料库
///    provider），弹层还有进出场动画，`pumpAndSettle` 容易被拖到超时 → 一律用有界
///    `pump`（见 `_settle`）；
/// 2. **Hive 不进测试**：`CompetitionAwardStore.add/save` 是真异步 I/O，在
///    `testWidgets` 的假异步区里永不完成（会把用例挂满 10 分钟）→ 用内存假 store
///    子类 override 掉 `records / loaded / add / update / remove`，全程不碰 Hive；
/// 3. **`zcMaterialsProvider` 必须 override**（自动带入的来源）：它默认经 `zcStoreProvider`
///    去开 Hive + 读应用目录，不 override 就会在假异步区里挂死 → 每个用例（都在
///    `pumpPage` 里）喂内存材料清单，空列表 = 没有材料。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/competition_award/data/award_standard_parser.dart';
import 'package:smarter_jxufe/features/competition_award/data/competition_award_store.dart';
import 'package:smarter_jxufe/features/competition_award/data/competition_catalog_parser.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_calc.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_coefficient.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_record.dart';
import 'package:smarter_jxufe/features/competition_award/domain/award_standard.dart';
import 'package:smarter_jxufe/features/competition_award/domain/competition_catalog.dart';
import 'package:smarter_jxufe/features/competition_award/presentation/award_record_card.dart';
import 'package:smarter_jxufe/features/competition_award/presentation/competition_award_screen.dart';
import 'package:smarter_jxufe/features/materials/domain/material_award_bridge.dart';
import 'package:smarter_jxufe/features/rules/domain/rule_doc.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/data/wxcal_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/wxcal_semester.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_catalog.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

/// 固定「今天」——三个预设（本学期 / 本学年 / 近一年）都相对它算，不注入就没法断言。
final DateTime _now = DateTime(2026, 10, 1);

/// 页面源码（源码守卫用）。
const String _pagePath =
    'lib/features/competition_award/presentation/competition_award_screen.dart';

String _asset(String name) => File('assets/rules/text/$name').readAsStringSync();

/// 有界 settle：落地 provider 的异步结果 + 弹层动画，但**不用 `pumpAndSettle`**。
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

/// 合计大字（`awardTotal`）—— 记录行也印金额，必须按 Key 取，别用 `find.text`。
String _total(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('awardTotal'))).data!;

/// 某条记录左侧信息列的压暗系数（未计入 = `kAwardDimOpacity`、计入 = 1）。
double _dim(WidgetTester tester, String recordId) =>
    tester.widget<Opacity>(find.byKey(Key('awardDim-$recordId'))).opacity;

/// 只读 + 内存写的假 store：不碰 Hive（真 I/O 会挂死假异步区）。
///
/// 「忽略名单」也一并走内存：真实现的 `excludeMaterial` 会写账号级 Hive box，
/// 而 Hive 未初始化时 `hive_impl.dart:118` 是 `completer.completeError(...)` **再**
/// `rethrow` —— rethrow 被 `saveCompetitionAwardExcluded` 的 try/catch 收下了，
/// 但 completer 那条错误是**无人监听的异步错误**，flutter_test 会直接判用例失败
/// （实测：`HiveError: You need to initialize Hive or provide a path to store the box.`）。
class _MemoryAwardStore extends CompetitionAwardStore {
  _MemoryAwardStore([List<CompetitionAwardRecord> seed = const []])
    : _list = [...seed],
      super(account: 'test');

  final List<CompetitionAwardRecord> _list;
  final Set<String> _excluded = <String>{};
  final List<AwardCoefficient> _coefficients = [];

  @override
  List<CompetitionAwardRecord> get records => List.unmodifiable(_list);

  @override
  Set<String> get excludedMaterialIds => _excluded;

  @override
  List<AwardCoefficient> get coefficients => List.unmodifiable(_coefficients);

  @override
  AwardCoefficientTable get coefficientTable =>
      AwardCoefficientTable(_coefficients);

  @override
  bool get loaded => true;

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<void> setCoefficient(String competitionName, double factor) async {
    final key = awardCoefficientKey(competitionName);
    _coefficients.removeWhere(
      (c) => awardCoefficientKey(c.competitionName) == key,
    );
    _coefficients.add(
      AwardCoefficient(competitionName: competitionName, factor: factor),
    );
    notifyListeners();
  }

  @override
  Future<void> removeCoefficient(String competitionName) async {
    final key = awardCoefficientKey(competitionName);
    _coefficients.removeWhere(
      (c) => awardCoefficientKey(c.competitionName) == key,
    );
    notifyListeners();
  }

  @override
  Future<void> add(CompetitionAwardRecord record) async {
    _list.add(record);
    notifyListeners();
  }

  @override
  Future<void> update(CompetitionAwardRecord record) async {
    final i = _list.indexWhere((r) => r.id == record.id);
    if (i >= 0) _list[i] = record;
    notifyListeners();
  }

  @override
  Future<void> remove(String id) async {
    _list.removeWhere((r) => r.id == id);
    notifyListeners();
  }

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

CompetitionAwardRecord _record({
  required String id,
  required CompetitionClass klass,
  required String name,
  String tier = '第一等次',
  AwardScope scope = AwardScope.national,
  DateTime? date,
}) => CompetitionAwardRecord(
  id: id,
  competitionName: name,
  klass: klass,
  tierLabel: tier,
  scope: scope,
  date: date,
);

/// 材料库夹具：一条学科竞赛证明材料。
///
/// 字段口径（见 `zc_catalog.dart` 的 contest 规格）：`cat` c1~c4 = Ⅰ~Ⅳ 类、
/// `level` 0/1/2 = 国家级/省级/校级、`opt` 0/1/2/3 = 特等/一等/二等/三等。
ZcMaterial _contestMaterial({
  required String id,
  required String name,
  String cat = 'c2',
  int level = 0,
  int opt = 1,
  String dateIso = '2026-05-06',
}) => ZcMaterial(
  id: id,
  typeId: ZcTypeId.contest,
  name: name,
  dateIso: dateIso,
  cat: cat,
  level: level,
  opt: opt,
);

void main() {
  late AwardStandard standard;
  late CompetitionCatalog catalog;

  // 夹具刻意用资料库真实文件现解析（目录 r21 / 办法 r01a）：解析器一旦失效，
  // 本文件先红。
  setUpAll(() {
    standard = parseAwardStandard(_asset('r01a.md'));
    final edition = parseCompetitionCatalogEdition(
      _asset('r21.md'),
      sourceDocId: 'r21',
    );
    catalog = competitionCatalogOf([?edition]);
  });

  test('资料库自检：Ⅱ类国赛一等次 6000 / Ⅲ类一等次 3000', () {
    expect(standard.hasData, isTrue);
    expect(catalog.isEmpty, isFalse);
    double amount(CompetitionAwardRecord r) => competitionAwardOutcomeOf(
      records: [r],
      standard: standard,
      range: null,
    ).total;
    expect(
      amount(
        _record(
          id: 'x',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
        ),
      ),
      6000,
    );
    expect(
      amount(_record(id: 'y', klass: CompetitionClass.iii, name: '某Ⅲ类竞赛')),
      3000,
    );
    expect(fmtAwardAmount(6000), '6000 元');
  });

  Future<_MemoryAwardStore> pumpPage(
    WidgetTester tester, {
    List<CompetitionAwardRecord> records = const [],
    List<ZcMaterial> materials = const [],
    AwardStandard? overrideStandard,
    CompetitionCatalog? overrideCatalog,
    bool realTerms = false,
  }) async {
    // 底部弹层比默认 800×600 高得多，按钮会落在视口外点不到。
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = _MemoryAwardStore(records);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          competitionAwardStoreProvider.overrideWith((ref) => store),
          // 资料库四条链全部喂内存值：不读 rulesCatalogProvider、不动 asset bundle。
          competitionCatalogDocsProvider.overrideWith(
            (ref) async => const <RuleDoc>[],
          ),
          competitionCatalogProvider.overrideWith(
            (ref) async => overrideCatalog ?? catalog,
          ),
          awardStandardDocProvider.overrideWith((ref) async => null),
          awardStandardProvider.overrideWith(
            (ref) async => overrideStandard ?? standard,
          ),
          // 材料库（自动带入的唯一来源）：默认实现要开账号级 Hive box + 读应用目录，
          // 在假异步区里会挂死 → 一律喂内存清单（空列表 = 没有材料）。
          zcMaterialsProvider.overrideWith((ref) async => materials),
          // 「本学期」预设：空校历快照 → 走月份兜底（2026-10-01 → 261 第一学期
          // = 2026-09-01 ~ 2027-01-31），使断言与校历快照内容解耦。
          // `realTerms: true` 则用**真实快照**（生产走的就是这条，见下一个用例）。
          if (!realTerms)
            offlineSemesterTermsProvider.overrideWithValue(
              const <WxSemesterArrangement>[],
            ),
        ],
        child: MaterialApp(
          theme: appLightTheme,
          home: CompetitionAwardScreen(now: _now),
        ),
      ),
    );
    await _settle(tester);
    return store;
  }

  testWidgets('首屏四张卡 + 空态合计', (tester) async {
    await pumpPage(tester);

    expect(find.byKey(const Key('awardRangeCard')), findsOneWidget);
    expect(find.byKey(const Key('awardRulesCard')), findsOneWidget);
    expect(find.byKey(const Key('awardRecordCard')), findsOneWidget);
    expect(find.byKey(const Key('awardCatalogCard')), findsOneWidget);

    // 没有记录：0 元 + 两个 0 条。
    expect(_total(tester), '0 元');
    expect(find.text('计入 0 条 · 未计入 0 条'), findsOneWidget);
    expect(find.text('还没有登记获奖记录。'), findsOneWidget);
    expect(find.byKey(const Key('awardAddRecordEmpty')), findsOneWidget);
    // 未设范围时起止都是「未设置」。
    expect(find.text('未设置'), findsNWidgets(2));
  });

  testWidgets('切「本学期」只算区间内的记录，区间外的标注原因', (tester) async {
    await pumpPage(
      tester,
      records: [
        _record(
          id: 'a1',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
          date: DateTime(2026, 9, 20),
        ),
        _record(
          id: 'a2',
          klass: CompetitionClass.iii,
          name: 'IMA 校园管理会计案例大赛',
          date: DateTime(2025, 8, 27),
        ),
      ],
    );

    // 默认「全部」：两条都计入（Ⅱ6000 + Ⅲ3000）。
    expect(_total(tester), '9000 元');
    expect(find.text('计入 2 条 · 未计入 0 条'), findsOneWidget);
    expect(find.textContaining('不在所选时间范围内'), findsNothing);

    await _tap(tester, find.byKey(const Key('awardRangePreset-currentTerm')));

    // 261 第一学期兜底区间（九月起，见 award_common.dart 的 awardRangeOfPreset）。
    expect(find.text('2026-09-01'), findsOneWidget);
    expect(find.text('2027-01-31'), findsOneWidget);
    expect(_total(tester), '6000 元');
    expect(find.text('计入 1 条 · 未计入 1 条'), findsOneWidget);
    // 区外那条仍显示，并说明为什么没算钱。
    expect(find.byKey(const Key('awardRecordTile-a2')), findsOneWidget);
    expect(find.textContaining('不在所选时间范围内'), findsOneWidget);
    expect(find.text('未计入的 1 条已变暗'), findsOneWidget);
    // 原因必须压在「压暗」之外：0.55 的警示色只剩约 1.7:1，等于看不清。
    expect(
      find.descendant(
        of: find.byKey(const Key('awardDim-a2')),
        matching: find.textContaining('不在所选时间范围内'),
      ),
      findsNothing,
      reason: '算不出来的原因要照原样显示（不属于「只变暗」那一档）',
    );
  });

  testWidgets('被「取最高」挤掉的行只变暗，不再印第九条 / 第十条的提示', (tester) async {
    await pumpPage(
      tester,
      records: [
        _record(
          id: 'w1',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
          tier: '第一等次', // 6000
          date: DateTime(2026, 5, 1),
        ),
        _record(
          id: 'w2',
          klass: CompetitionClass.ii,
          name: '全国大学生电子设计竞赛',
          tier: '第二等次', // 3000 → 被Ⅱ类「只奖最高一项」挤掉
          date: DateTime(2026, 5, 2),
        ),
      ],
    );

    expect(_total(tester), '6000 元');
    expect(find.text('计入 1 条 · 未计入 1 条'), findsOneWidget);
    // 行还在（不静默丢弃），但**不再**印原因。
    // ⚠ 断言必须限定在「获奖记录」卡内：「不累计」在「本次统计口径」卡（appliedRules）
    // 与规则原文注记里本来就该出现，`find.textContaining` 全局找会误判。
    expect(find.byKey(const Key('awardRecordTile-w2')), findsOneWidget);
    final recordCard = find.byKey(const Key('awardRecordCard'));
    expect(
      find.descendant(of: recordCard, matching: find.textContaining('不累计')),
      findsNothing,
    );
    expect(
      find.descendant(of: recordCard, matching: find.textContaining('更高奖项')),
      findsNothing,
    );
    expect(find.textContaining('不累计'), findsWidgets, reason: '口径卡照旧写条款');
    expect(find.text('未计入的 1 条已变暗'), findsOneWidget);
    // 表现 = 信息那一列压暗；计入的那条不压。
    expect(_dim(tester, 'w2'), kAwardDimOpacity);
    expect(_dim(tester, 'w2'), lessThan(1));
    expect(_dim(tester, 'w1'), 1.0);
    // 行尾的「删除」不跟着压暗（否则唯一能撤销动作的入口会变模糊）：
    // 压暗的是信息那一列，删除按钮在它之外。
    expect(
      find.byKey(const Key('awardDeleteRecord-w2')),
      findsOneWidget,
      reason: '前提：未计入的手填行仍有删除入口',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('awardDim-w2')),
        matching: find.byKey(const Key('awardDeleteRecord-w2')),
      ),
      findsNothing,
      reason: '删除按钮不许落在 Opacity 里',
    );
  });

  testWidgets('「本学期」预设走真实校历快照（生产路径，不是月份兜底）', (tester) async {
    await pumpPage(
      tester,
      realTerms: true, // 不 override → 用 offlineSemesterTermsProvider 的真快照
      records: [
        _record(
          id: 'a1',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
          date: DateTime(2026, 9, 20),
        ),
        _record(
          id: 'a2',
          klass: CompetitionClass.iii,
          name: 'IMA 校园管理会计案例大赛',
          date: DateTime(2025, 8, 27),
        ),
      ],
    );

    await _tap(tester, find.byKey(const Key('awardRangePreset-currentTerm')));

    // _now = 2026-10-01 落在快照的 261 第一学期里 → 区间 = 该学期真实起止。
    final term261 = wxcalOfflineToDomain().firstWhere((t) => t.term == '261');
    expect(
      term261.start,
      isNot(DateTime(2026, 9, 1)),
      reason: '09-01 是月份兜底值；两者不同这条用例才真的验证了快照分支',
    );
    expect(find.text(fmtAwardDate(term261.start)), findsOneWidget);
    expect(find.text(fmtAwardDate(term261.end)), findsOneWidget);
    // 兜底区间（09-01 / 01-31）一个都不该出现。
    expect(find.text('2026-09-01'), findsNothing);
    expect(find.text('2027-01-31'), findsNothing);
    // 区间内的 Ⅱ 类算钱，区外的 Ⅲ 类不计（与预设无关的金额口径不受影响）。
    expect(_total(tester), '6000 元');
    expect(find.text('计入 1 条 · 未计入 1 条'), findsOneWidget);
  });

  testWidgets('「清除」时间范围后两条记录都回到合计里', (tester) async {
    await pumpPage(
      tester,
      records: [
        _record(
          id: 'a1',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
          date: DateTime(2026, 9, 20),
        ),
        _record(
          id: 'a2',
          klass: CompetitionClass.iii,
          name: 'IMA 校园管理会计案例大赛',
          date: DateTime(2025, 8, 27),
        ),
      ],
    );

    await _tap(tester, find.byKey(const Key('awardRangePreset-currentTerm')));
    expect(_total(tester), '6000 元');

    await _tap(tester, find.byKey(const Key('awardClearRange')));
    expect(_total(tester), '9000 元');
    expect(find.text('计入 2 条 · 未计入 0 条'), findsOneWidget);
    expect(find.text('未设置'), findsNWidgets(2));
    expect(find.textContaining('不在所选时间范围内'), findsNothing);
  });

  testWidgets('添加记录：弹层实时预览 → 保存后列表与合计都更新', (tester) async {
    final store = await pumpPage(tester);

    await _tap(tester, find.byKey(const Key('awardAddRecord')));
    expect(find.text('添加获奖记录'), findsOneWidget);
    expect(find.byKey(const Key('awardNameField')), findsOneWidget);
    expect(find.byKey(const Key('awardSpecialTierSwitch')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('awardNameField')),
      '全国大学生数学建模竞赛',
    );
    await _settle(tester);
    // 默认 Ⅱ类 / 第一等次 / 国赛 → 实时预览 6000 元（办法表格口径）。
    expect(find.text('预计奖励：6000 元'), findsOneWidget);

    await _tap(tester, find.text('保存'));

    expect(store.records.length, 1);
    expect(store.records.single.competitionName, '全国大学生数学建模竞赛');
    expect(find.text('获奖记录（1 条）'), findsOneWidget);
    expect(_total(tester), '6000 元');
    expect(find.text('计入 1 条 · 未计入 0 条'), findsOneWidget);
  });

  testWidgets('点行编辑：改等次后金额从 6000 变 3000', (tester) async {
    final store = await pumpPage(
      tester,
      records: [
        _record(
          id: 'a1',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
        ),
      ],
    );
    expect(_total(tester), '6000 元');

    await _tap(tester, find.byKey(const Key('awardRecordTile-a1')));
    expect(find.text('编辑获奖记录'), findsOneWidget);

    await _tap(tester, find.byKey(const Key('awardTierChip-第二等次')));
    expect(find.text('预计奖励：3000 元'), findsOneWidget);

    await _tap(tester, find.text('保存'));
    expect(store.records.single.id, 'a1');
    expect(store.records.single.tierLabel, '第二等次');
    expect(_total(tester), '3000 元');
  });

  testWidgets('删除要过确认框，确认后记录消失', (tester) async {
    final store = await pumpPage(
      tester,
      records: [
        _record(
          id: 'a1',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
        ),
      ],
    );

    await _tap(tester, find.byKey(const Key('awardDeleteRecord-a1')));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('删除获奖记录'), findsOneWidget);
    expect(find.textContaining('确定删除「全国大学生数学建模竞赛」'), findsOneWidget);

    // 先取消：记录还在。
    await _tap(tester, find.text('取消'));
    expect(store.records.length, 1);

    await _tap(tester, find.byKey(const Key('awardDeleteRecord-a1')));
    await _tap(tester, find.text('删除'));

    expect(store.records, isEmpty);
    expect(find.text('获奖记录（0 条）'), findsOneWidget);
    expect(find.byKey(const Key('awardAddRecordEmpty')), findsOneWidget);
    expect(_total(tester), '0 元');
  });

  testWidgets('材料库里的国家级Ⅱ类一等奖自动带入并计入合计', (tester) async {
    // 材料库一条：中国高校计算机大赛 · Ⅱ类（c2）· 国家级（level 0）· 一等奖（opt 1）。
    await pumpPage(
      tester,
      materials: [
        _contestMaterial(id: 'm1', name: '中国高校计算机大赛'),
      ],
    );

    final autoId = materialAwardIdOf('m1');
    expect(autoId, 'material:m1', reason: '自动条目 id 口径 = 前缀 + 材料 id');

    // 行在卡里，带「材料库」徽标；Ⅱ类国赛第一等次 = 6000 元，**已进合计**。
    expect(find.byKey(Key('awardRecordTile-$autoId')), findsOneWidget);
    expect(find.byKey(Key('awardAutoBadge-$autoId')), findsOneWidget);
    expect(find.text('材料库'), findsOneWidget);
    expect(find.text('获奖记录（1 条）'), findsOneWidget);
    expect(_total(tester), '6000 元');
    expect(find.text('计入 1 条 · 未计入 0 条'), findsOneWidget);
    // 自动行由材料库派生：不给编辑 / 删除，只给「忽略」。
    expect(find.byKey(const Key('awardIgnoreMaterial-m1')), findsOneWidget);
    expect(
      find.byKey(Key('awardDeleteRecord-$autoId')),
      findsNothing,
      reason: '自动行不能被删除（删了也会被材料库重新带回来）',
    );
    // 这条算进来了 → 「未计入」小节整节不渲染。
    expect(find.byKey(const Key('awardSkippedMaterials')), findsNothing);
  });

  testWidgets('自动行「忽略」后消失：忽略名单进 store、合计回落、转到「已忽略」清单', (
    tester,
  ) async {
    final store = await pumpPage(
      tester,
      materials: [
        _contestMaterial(id: 'm1', name: '中国高校计算机大赛'),
      ],
    );
    expect(_total(tester), '6000 元');

    await _tap(tester, find.byKey(const Key('awardIgnoreMaterial-m1')));

    expect(store.excludedMaterialIds, contains('m1'));
    expect(find.byKey(const Key('awardRecordTile-material:m1')), findsNothing);
    expect(find.byKey(const Key('awardAutoBadge-material:m1')), findsNothing);
    expect(_total(tester), '0 元');
    expect(find.text('获奖记录（0 条）'), findsOneWidget);
    // 行没了，但材料本身没丢：单列一节「已忽略」+ 逐条「恢复」
    //（用户 2026-09-18：「竞赛奖励功能里可以忽略某些项，但是没有恢复手段」）。
    expect(find.byKey(const Key('awardIgnoredMaterials')), findsOneWidget);
    expect(find.text('已忽略 1 条'), findsOneWidget);
    expect(find.byKey(const Key('awardRestoreMaterial-m1')), findsOneWidget);
    // 它**不再**混在「材料库没算进来」那节里（那节是材料库的问题，不是你的选择）。
    expect(find.byKey(const Key('awardSkippedMaterials')), findsNothing);
  });

  testWidgets('点「恢复」后自动行回到列表、重新计入合计', (tester) async {
    final store = await pumpPage(
      tester,
      materials: [
        _contestMaterial(id: 'm1', name: '中国高校计算机大赛'),
      ],
    );
    await _tap(tester, find.byKey(const Key('awardIgnoreMaterial-m1')));
    expect(_total(tester), '0 元');

    await _tap(tester, find.byKey(const Key('awardRestoreMaterial-m1')));

    expect(store.excludedMaterialIds, isNot(contains('m1')));
    expect(find.byKey(const Key('awardIgnoredMaterials')), findsNothing);
    expect(find.text('获奖记录（1 条）'), findsOneWidget);
    expect(find.byKey(const Key('awardRecordTile-material:m1')), findsOneWidget);
    expect(find.byKey(const Key('awardAutoBadge-material:m1')), findsOneWidget);
    expect(find.byKey(const Key('awardIgnoreMaterial-m1')), findsOneWidget);
    expect(_total(tester), '6000 元');
  });

  testWidgets('校级竞赛材料不进合计，列进「未计入」小节并说明原因', (tester) async {
    await pumpPage(
      tester,
      materials: [
        _contestMaterial(id: 'm2', name: '校级程序设计竞赛', level: 2),
      ],
    );

    // 办法第九条只列国赛 / 省赛 → 校级不进记录、不进合计。
    expect(find.byKey(const Key('awardRecordTile-material:m2')), findsNothing);
    expect(_total(tester), '0 元');
    expect(find.text('获奖记录（0 条）'), findsOneWidget);
    expect(find.byKey(const Key('awardSkippedMaterials')), findsOneWidget);
    expect(find.text('材料库里还有 1 条没算进来'), findsOneWidget);
    expect(find.textContaining('校级程序设计竞赛'), findsWidgets);
    expect(
      find.textContaining('校级竞赛不在奖励标准内'),
      findsOneWidget,
      reason: '认不出的一律给原因，不静默丢弃',
    );
  });

  testWidgets('竞赛目录浏览能搜到「全国大学生数学建模竞赛」', (tester) async {
    await pumpPage(tester);

    await _tap(tester, find.byKey(const Key('awardCatalogBrowse')));
    expect(find.byKey(const Key('awardCatalogSearch')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('awardCatalogSearch')),
      '数学建模',
    );
    await _settle(tester);
    expect(find.textContaining('全国大学生数学建模竞赛'), findsWidgets);
  });

  // ---------------------------------------------------------------- 赛事经验系数
  // 用户 2026-09-18：「竞赛奖励有一个经验系数……这个比例一般是固定的，我希望可以
  // 手动设置」；拍板 = 按赛事设 + 行内明算。

  testWidgets('赛事系数：设为 0.6 后按 ×0.6 缩减，且行内明算写出来', (tester) async {
    final store = await pumpPage(
      tester,
      records: [
        _record(
          id: 'a',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
          date: DateTime(2026, 5, 6),
        ),
      ],
    );
    // 未设系数：全额 6000，且没有行内明算那一行（卡片说明文案里本来就有「×」，
    // 所以按 Key 断言，不能用 find.textContaining('×')）。
    expect(_total(tester), '6000 元');
    expect(find.byKey(const Key('awardScaleExpr-a')), findsNothing);

    await store.setCoefficient('全国大学生数学建模竞赛', 0.6);
    await _settle(tester);

    // 合计 = 6000 × 0.6 = 3600；行内把「6000 元 ×0.6 =」写出来（行内明算）。
    expect(_total(tester), '3600 元');
    expect(find.byKey(const Key('awardScaleExpr-a')), findsOneWidget);
    final expr = tester
        .widget<Text>(find.byKey(const Key('awardScaleExpr-a')))
        .data;
    expect(expr, '6000 元 ×0.6 =');
    // 统计口径里说明哪条被缩减。
    expect(find.textContaining('赛事经验系数'), findsWidgets);
  });

  testWidgets('赛事系数：只影响命中的赛事，其他记录仍全额', (tester) async {
    final store = await pumpPage(
      tester,
      records: [
        _record(
          id: 'a',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
          date: DateTime(2026, 5, 6),
        ),
        _record(
          id: 'b',
          klass: CompetitionClass.iii,
          name: '中国大学生计算机设计大赛',
          date: DateTime(2026, 5, 7),
        ),
      ],
    );
    expect(_total(tester), '9000 元'); // 6000（Ⅱ类最高）+ 3000（Ⅲ类最高）

    await store.setCoefficient('全国大学生数学建模竞赛', 0.5);
    await _settle(tester);
    expect(_total(tester), '6000 元'); // 3000 + 3000
    expect(find.byKey(const Key('awardScaleExpr-a')), findsOneWidget);
    expect(find.byKey(const Key('awardScaleExpr-b')), findsNothing);
  });

  testWidgets('赛事系数卡：添加 / 编辑 / 删除三条链', (tester) async {
    final store = await pumpPage(tester);
    expect(find.byKey(const Key('awardCoefficientCard')), findsOneWidget);
    expect(find.byKey(const Key('awardAddCoefficientEmpty')), findsOneWidget);

    // 添加：弹层保存 → 卡片出现该行（×0.6）。
    await _tap(tester, find.byKey(const Key('awardAddCoefficientEmpty')));
    await tester.enterText(
      find.byKey(const Key('coefNameField')),
      '蓝桥杯全国软件和信息技术专业人才大赛',
    );
    await tester.enterText(find.byKey(const Key('coefFactorField')), '60%');
    await _settle(tester);
    await _tap(tester, find.byKey(const Key('coefSave')));
    await _settle(tester);

    expect(store.coefficients.length, 1);
    expect(store.coefficients.first.factor, 0.6);
    expect(find.text('×0.6'), findsOneWidget);

    // 编辑：改 0.5（按赛事覆盖，不新增一条）。
    await _tap(
      tester,
      find.byKey(const Key('awardEditCoefficient-蓝桥杯全国软件和信息技术专业人才大赛')),
    );
    await tester.enterText(find.byKey(const Key('coefFactorField')), '0.5');
    await _settle(tester);
    await _tap(tester, find.byKey(const Key('coefSave')));
    await _settle(tester);
    expect(store.coefficients.length, 1);
    expect(store.coefficients.first.factor, 0.5);

    // 删除：过确认框。
    await _tap(
      tester,
      find.byKey(const Key('awardDeleteCoefficient-蓝桥杯全国软件和信息技术专业人才大赛')),
    );
    await _settle(tester);
    await _tap(tester, find.text('删除'));
    await _settle(tester);
    expect(store.coefficients, isEmpty);
    expect(find.byKey(const Key('awardAddCoefficientEmpty')), findsOneWidget);
  });

  testWidgets('赛事系数：弹层里的赛事名 chip 一键填入当前记录的赛事', (tester) async {
    await pumpPage(
      tester,
      records: [
        _record(
          id: 'a',
          klass: CompetitionClass.ii,
          name: '全国大学生数学建模竞赛',
          date: DateTime(2026, 5, 6),
        ),
      ],
    );
    await _tap(tester, find.byKey(const Key('awardAddCoefficient')));
    await _settle(tester);
    expect(find.byKey(const Key('coefNameChip-0')), findsOneWidget);

    await _tap(tester, find.byKey(const Key('coefNameChip-0')));
    await _settle(tester);
    final name = tester
        .widget<TextField>(find.byKey(const Key('coefNameField')))
        .controller!
        .text;
    expect(name, '全国大学生数学建模竞赛');
  });

  testWidgets('赛事系数：系数越界（1.5）时保存禁用并提示', (tester) async {
    await pumpPage(tester);
    await _tap(tester, find.byKey(const Key('awardAddCoefficientEmpty')));
    await tester.enterText(
      find.byKey(const Key('coefNameField')),
      '某赛事',
    );
    await tester.enterText(find.byKey(const Key('coefFactorField')), '1.5');
    await _settle(tester);
    expect(find.byKey(const Key('coefFactorError')), findsOneWidget);
    final save = tester.widget<FilledButton>(find.byKey(const Key('coefSave')));
    expect(save.onPressed, isNull);
  });

  test('源码守卫：走 paneAppBar + PageAutoRefresher，且不硬编码颜色', () {
    final src = File(_pagePath).readAsStringSync();
    expect(src.contains('paneAppBar('), isTrue);
    expect(src.contains('PageAutoRefresher('), isTrue);
    // 时间范围只喂给唯一口径函数，页面不自己算钱。
    expect(src.contains('competitionAwardOutcomeOf('), isTrue);
    expect(src.contains('Color(0x'), isFalse);
    expect(
      RegExp(r'(?<![A-Za-z])Colors\.').hasMatch(src),
      isFalse,
      reason: '颜色一律走 AppColors / fp(context)',
    );
  });

  test('源码守卫：竞赛奖励页与子组件都不硬编码颜色', () {
    final files = Directory(
      'lib/features/competition_award/presentation',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart')).toList();
    expect(files.length, 8, reason: '主屏 + 7 个子组件（含 award_coefficient_card）');
    for (final f in files) {
      final src = f.readAsStringSync();
      expect(src.contains('Color(0x'), isFalse, reason: f.path);
      expect(
        RegExp(r'(?<![A-Za-z])Colors\.').hasMatch(src),
        isFalse,
        reason: '${f.path} 用了裸 Colors.',
      );
    }
  });
}
