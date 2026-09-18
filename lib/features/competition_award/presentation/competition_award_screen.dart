/// 竞赛奖励（按《学科竞赛管理办法》测算获奖奖励）。
///
/// 用户 2026-09-17 原话：「新功能：竞赛奖励 / 参考《学科竞赛管理办法》 /
/// 自动资料库里获取竞赛信息，然后时间范围不是按学年，而是手动选择时间范围」。
///
/// 已拍板口径：
/// - 竞赛目录与奖励标准都**自动从资料库获取**（`competitionCatalogProvider` /
///   `awardStandardProvider`，随包 `assets/rules/` 运行时解析）；
/// - 时间范围 = **手动选择起止日期**，只筛选获奖记录再合计 —— 金额判定只有一处
///   （`competitionAwardOutcomeOf` + `AwardDateRange`），页面不重算钱；
/// - 记录本身存在本地 Hive（`competitionAwardStoreProvider`），**范围不进库**：
///   它只是「这一次想看哪一段」的临时视图状态，页面重建即回到「全部」；
/// - 记录有**两个来源**（用户 2026-09-18「加分项自动从资料库中获取」）：材料库里
///   已登记的学科竞赛获奖**自动带入并直接计入**（`material_award_bridge.dart`
///   的 `materialAwardRecordLinks`，id = `material:<材料 id>`，不落库），加上用户
///   手工登记的记录。两者一起进 `competitionAwardOutcomeOf` 算合计 —— 自动带入的
///   行不给编辑 / 删除，只能「忽略」（忽略名单记在 store 的 `excludedMaterialIds`）。
///
/// 页面挂了 [PageAutoRefresher]（AGENTS §3 硬口径）：资料库解析结果都挂在缓存型
/// `FutureProvider` 上，从《学科竞赛管理办法》原文阅读器返回、或 App 回前台时
/// 若不失效，页面会一直显示旧数据。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/materials/domain/material_award_bridge.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

import '../data/competition_award_store.dart';
import '../domain/award_calc.dart';
import '../domain/award_coefficient.dart';
import '../domain/award_record.dart';
import '../domain/award_standard.dart';
import '../domain/competition_catalog.dart';
import 'award_catalog_card.dart';
import 'award_coefficient_card.dart';
import 'award_common.dart';
import 'award_range_card.dart';
import 'award_record_card.dart';
import 'award_record_sheet.dart';
import 'award_rules_card.dart';

class CompetitionAwardScreen extends ConsumerStatefulWidget {
  const CompetitionAwardScreen({super.key, this.now});

  /// 注入「今天」（时间范围预设与日期选择器的起点）。
  ///
  /// 预设区间都相对「当下」计算（本学期 / 本学年 / 近一年），不注入就没法在测试里
  /// 稳定断言；生产路径不传即真实时间。
  final DateTime? now;

  @override
  ConsumerState<CompetitionAwardScreen> createState() =>
      _CompetitionAwardScreenState();
}

class _CompetitionAwardScreenState
    extends ConsumerState<CompetitionAwardScreen> {
  /// 手选时间范围；null = 不按日期筛（「全部」）。
  AwardDateRange? _range;

  late final PageAutoRefresher _refresher;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _refresher = PageAutoRefresher(onRefresh: _refreshAll)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresher.subscribeRoute(context);
  }

  @override
  void dispose() {
    _refresher.dispose();
    super.dispose();
  }

  /// 自动刷新：**被依赖者先失效** —— 目录 / 标准的「文档 provider」是下面两个解析
  /// provider 的输入，先失效上游，下游才会拿着新文档重新解析。
  void _refreshAll() {
    if (!mounted) return;
    invalidateIfLoaded(ref, competitionCatalogDocsProvider);
    invalidateIfLoaded(ref, competitionCatalogProvider);
    invalidateIfLoaded(ref, awardStandardDocProvider);
    invalidateIfLoaded(ref, awardStandardProvider);
    // 获奖记录自动来自材料库（见 `material_award_bridge.dart`）：从材料库返回 /
    // 回前台也重取一次。材料库那边保存 / 删除时自己也会 invalidate 它，这里只是
    // 保证「进了本页看到的一定是新材料」，与推免页同款。
    invalidateIfLoaded(ref, zcMaterialsProvider);
  }

  /// 手动重试（失败卡的按钮）：无条件失效，不看「是否已加载完」。
  void _retryLibrary() {
    ref.invalidate(competitionCatalogDocsProvider);
    ref.invalidate(competitionCatalogProvider);
    ref.invalidate(awardStandardDocProvider);
    ref.invalidate(awardStandardProvider);
  }

  Future<void> _addRecord() => showAwardRecordSheet(context, ref);

  Future<void> _editRecord(CompetitionAwardRecord record) =>
      showAwardRecordSheet(context, ref, editing: record);

  Future<void> _deleteRecord(CompetitionAwardRecord record) async {
    final ok = await geConfirmDelete(
      context,
      title: '删除获奖记录',
      message: '确定删除「${record.competitionName}」这条获奖记录吗？删除后无法恢复。',
    );
    if (!ok || !mounted) return;
    await ref.read(competitionAwardStoreProvider).remove(record.id);
  }

  /// 从目录挑一条 → 直接进「添加记录」弹层并预填该竞赛。
  Future<void> _browseCatalog(CompetitionCatalog catalog) async {
    final picked = await showAwardCatalogSheet(context, catalog: catalog);
    if (picked == null || !mounted) return;
    await showAwardRecordSheet(context, ref, preset: picked);
  }

  /// 当前获奖记录里出现过的赛事名（去重、保持先后），供系数弹层一键填入。
  List<String> _knownCompetitionNames(List<CompetitionAwardRecord> records) {
    final seen = <String>{};
    final out = <String>[];
    for (final r in records) {
      final name = r.competitionName.trim();
      if (name.isEmpty) continue;
      if (seen.add(awardCoefficientKey(name))) out.add(name);
    }
    return out;
  }

  Future<void> _addCoefficient(List<String> known) => showAwardCoefficientSheet(
    context,
    knownNames: known,
    onSave: (name, factor) =>
        ref.read(competitionAwardStoreProvider).setCoefficient(name, factor),
  );

  Future<void> _editCoefficient(
    List<String> known,
    AwardCoefficient coefficient,
  ) => showAwardCoefficientSheet(
    context,
    editing: coefficient,
    knownNames: known,
    onSave: (name, factor) =>
        ref.read(competitionAwardStoreProvider).setCoefficient(name, factor),
  );

  Future<void> _deleteCoefficient(AwardCoefficient coefficient) async {
    final ok = await geConfirmDelete(
      context,
      title: '删除赛事系数',
      message:
          '确定删除「${coefficient.competitionName}」的 ×${fmtAwardCoefficient(coefficient.factor)} 吗？'
          '删除后该赛事的记录恢复按奖励标准全额计算。',
    );
    if (!ok || !mounted) return;
    await ref
        .read(competitionAwardStoreProvider)
        .removeCoefficient(coefficient.competitionName);
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(competitionAwardStoreProvider);
    final catalogAsync = ref.watch(competitionCatalogProvider);
    final standardAsync = ref.watch(awardStandardProvider);
    final standardDoc = ref.watch(awardStandardDocProvider).valueOrNull;
    // 「本学期」预设取校历快照的真实起止（与课表 / 校历同一口径，见 AGENTS §9）。
    final terms = ref.watch(offlineSemesterTermsProvider);

    final standard = standardAsync.valueOrNull ?? AwardStandard.empty;
    final catalog = catalogAsync.valueOrNull ?? CompetitionCatalog.empty;
    // 材料库 → 获奖记录：**自动带入**（用户 2026-09-18 裁定「加分项自动从资料库中
    // 获取」+「直接按自动识别结果计入」，不再逐条手填）。自动条目不落库，每次由材料库
    // 现算，所以材料库一改这里立刻跟着变；被「忽略」的材料记在 store 里，映射口径
    // 全在 `material_award_bridge.dart`，页面不自己拼。
    final materialsAsync = ref.watch(zcMaterialsProvider);
    final materialLinks = materialAwardRecordLinks(
      materialsAsync.valueOrNull ?? const <ZcMaterial>[],
      excludedMaterialIds: store.excludedMaterialIds,
      existing: store.records,
    );
    final autoRecords = linkedValuesOf(materialLinks);
    // 合计必须把自动记录算进去：**手填在前、自动在后**（顺序只影响行序，不影响钱）。
    // 赛事经验系数（手动设置，用户 2026-09-18 要求）在计算层里乘在折减后、取最高前。
    final outcome = competitionAwardOutcomeOf(
      records: [...store.records, ...autoRecords],
      standard: standard,
      range: _range,
      coefficients: store.coefficientTable,
    );

    // 资料库两条解析链都还没值：仍在读 / 读失败 —— 用一张卡说清楚并给「重试」。
    // （只要有一条拿到了值就正常渲染：两条链各自还有卡内的空态提示。）
    final hasLibraryValue = catalogAsync.hasValue || standardAsync.hasValue;
    final libraryLoading =
        !hasLibraryValue && (catalogAsync.isLoading || standardAsync.isLoading);
    final libraryError =
        !hasLibraryValue && (catalogAsync.hasError || standardAsync.hasError);

    return Scaffold(
      // 设置按钮由 paneAppBar 自动追加到 actions 末尾；本页不声明 settingsSections
      // （空 = 完整设置页，与综测 / 材料库 / 竞赛等页同一档）。
      appBar: paneAppBar(
        context,
        title: const Text('竞赛奖励'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
        children: [
          AwardRangeCard(
            range: _range,
            outcome: outcome,
            now: _now,
            terms: terms,
            onChanged: (range) => setState(() => _range = range),
          ),
          const SizedBox(height: 26),
          if (libraryLoading || libraryError)
            _LibraryNoticeCard(loading: libraryLoading, onRetry: _retryLibrary)
          else
            AwardRulesCard(
              outcome: outcome,
              standard: standard,
              doc: standardDoc,
              onRetry: _retryLibrary,
            ),
          const SizedBox(height: 26),
          AwardCoefficientCard(
            coefficients: store.coefficients,
            outcome: outcome,
            loaded: store.loaded,
            onAdd: () => _addCoefficient(
              _knownCompetitionNames([...store.records, ...autoRecords]),
            ),
            onEdit: (c) => _editCoefficient(
              _knownCompetitionNames([...store.records, ...autoRecords]),
              c,
            ),
            onDelete: _deleteCoefficient,
          ),
          const SizedBox(height: 26),
          AwardRecordCard(
            outcome: outcome,
            records: store.records,
            autoRecords: autoRecords,
            skipped: unlinkedOf(materialLinks),
            ignoredMaterialIds: store.excludedMaterialIds,
            loaded: store.loaded,
            onAdd: _addRecord,
            onEdit: _editRecord,
            onDelete: _deleteRecord,
            onIgnoreMaterial: (materialId) =>
                store.excludeMaterial(materialId),
            // 忽略是可逆的（用户 2026-09-18：「可以忽略某些项，但是没有恢复手段」）：
            // 恢复 = 把材料 id 从忽略名单里摘掉，材料库本身一个字都不改。
            onRestoreMaterial: (materialId) =>
                store.includeMaterial(materialId),
          ),
          if (!libraryLoading && !libraryError) ...[
            const SizedBox(height: 26),
            AwardCatalogCard(
              catalog: catalog,
              loading: catalogAsync.isLoading,
              onBrowse: () => _browseCatalog(catalog),
              onRetry: _retryLibrary,
            ),
          ],
        ],
      ),
    );
  }
}

/// 资料库读取中 / 读取失败（卡片内居中文案 + 「重试」）。
class _LibraryNoticeCard extends StatelessWidget {
  const _LibraryNoticeCard({required this.loading, required this.onRetry});

  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return awardCard(
      context,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      child: Center(
        child: Column(
          children: [
            Icon(
              loading ? Icons.hourglass_empty : Icons.error_outline,
              size: 22,
              color: AppColors.textMuted(context),
            ),
            const SizedBox(height: 8),
            Text(
              loading ? '正在读取资料库…' : '资料库读取失败',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              loading
                  ? '正在解析《学科竞赛目录》与《学科竞赛管理办法》。'
                  : '竞赛目录 / 奖励标准没能取到，可以重试；'
                        '手动登记的获奖记录不受影响，仍保留在本地。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textMuted(context),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(
              key: const Key('awardLibraryRetry'),
              onPressed: loading ? null : onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
