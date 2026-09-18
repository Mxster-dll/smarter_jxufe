import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/curriculum_importance_provider.dart';
import 'package:smarter_jxufe/features/materials/domain/material_award_bridge.dart';
import 'package:smarter_jxufe/features/recommendation/data/providers/recommendation_providers.dart';
import 'package:smarter_jxufe/features/recommendation/data/recommendation_store.dart';
import 'package:smarter_jxufe/features/recommendation/domain/bonus_catalog.dart';
import 'package:smarter_jxufe/features/recommendation/domain/recommendation_calc.dart';
import 'package:smarter_jxufe/features/recommendation/domain/recommendation_item.dart';
import 'package:smarter_jxufe/features/rules/domain/rule_doc.dart';
import 'package:smarter_jxufe/features/rules/presentation/rules_reader_screen.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';
import 'package:smarter_jxufe/features/zongce/domain/zc_models.dart';

/// 推免成绩（推荐免试研究生综合成绩测算）。
///
/// 用户 2026-09-17 原话：「我希望编写一个新功能，推免成绩 / 自动从资料库里获取加分项 /
/// 具体的加分项参考 app 目前『规章制度』部分里有相关文件」。
///
/// 口径（已拍板）：
/// - 综合成绩 = **推免加权平均成绩 + 附加分**（资料库《推免工作办法（2024年修订）》第十五条）；
/// - 推免加权平均成绩**自动取数**（主干×0.7 + 非主干×0.3，见
///   `lib/features/ims/grades/domain/recommendation_weighted.dart`）；
/// - 加分项**自动从资料库获取**（`bonusCatalogProvider` 解析 r08a 附件表格）；
/// - 每类别只计一项、不累加，附加分总分 10 分封顶（第十条）。
///
/// 页面结构（自上而下）：汇总卡 → 加分项卡 → 不累加对照卡 → 规则出处卡。
class RecommendationScreen extends ConsumerStatefulWidget {
  const RecommendationScreen({super.key});

  @override
  ConsumerState<RecommendationScreen> createState() =>
      _RecommendationScreenState();
}

class _RecommendationScreenState extends ConsumerState<RecommendationScreen> {
  late final PageAutoRefresher _refresher;

  /// 汇总卡的「推免加权构成」明细，默认收起。
  bool _weightedExpanded = false;

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

  /// 缓存型 provider 全部在这里列清（依赖者在前，被依赖者在后不影响失效语义，
  /// 但保持「文档 → 目录 → 加权」的阅读顺序）。
  void _refreshAll() {
    if (!mounted) return;
    invalidateIfLoaded(ref, recommendationRuleDocProvider);
    invalidateIfLoaded(ref, bonusCatalogProvider);
    invalidateIfLoaded(ref, recommendationWeightedResultProvider);
    // 加分项自动来自材料库：从材料库返回 / 回前台也要重取（材料库那边保存时
    // 也会 invalidate 它，这里保证「进了本页就一定是新的」）。
    invalidateIfLoaded(ref, zcMaterialsProvider);
  }

  void _retryCatalog() {
    ref.invalidate(recommendationRuleDocProvider);
    ref.invalidate(bonusCatalogProvider);
  }

  void _retryWeighted() {
    ref.invalidate(recommendationWeightedResultProvider);
    ref.invalidate(curriculumImportanceMapProvider);
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(bonusCatalogProvider);
    final weightedAsync = ref.watch(recommendationWeightedResultProvider);
    final doc = ref.watch(recommendationRuleDocProvider).valueOrNull;
    final store = ref.watch(recommendationStoreProvider);
    // 材料库 → 加分项：**自动带入**（用户 2026-09-18 裁定「自动从资料库获取」+
    // 「直接按自动识别结果计入」）。自动条目不落库，每次由材料库现算，因此改了
    // 材料库这里立刻跟着变；被「忽略」的材料记在 store 里（见 material_award_bridge）。
    final materialsAsync = ref.watch(zcMaterialsProvider);

    final catalog = catalogAsync.valueOrNull ?? BonusCatalog.empty;
    final weightedResult = weightedAsync.valueOrNull;
    final weighted = weightedResult?.weighted;
    final materialLinks = materialBonusItemLinks(
      materialsAsync.valueOrNull ?? const <ZcMaterial>[],
      catalog,
      excludedMaterialIds: store.excludedMaterialIds,
      existing: store.items,
    );
    final autoItems = linkedValuesOf(materialLinks);
    final outcome = recommendationOutcomeOf(
      weightedAverage: weightedResult?.importanceAvailable == true
          ? weighted!.score
          : 0,
      items: [...store.items, ...autoItems],
      catalog: catalog,
    );

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('推免成绩'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
        children: [
          _SummaryCard(
            key: const Key('recSummaryCard'),
            weightedResult: weightedResult,
            loading: weightedAsync.isLoading,
            outcome: outcome,
            catalog: catalog,
            expanded: _weightedExpanded,
            onToggle: () =>
                setState(() => _weightedExpanded = !_weightedExpanded),
            onRetry: _retryWeighted,
          ),
          const SizedBox(height: 12),
          if (catalogAsync.isLoading && !catalogAsync.hasValue)
            const _LoadingCard()
          else if (!catalog.hasData)
            _CatalogMissingCard(onRetry: _retryCatalog)
          else
            _BonusCard(
              key: const Key('recBonusCard'),
              outcome: outcome,
              catalog: catalog,
              skipped: unlinkedOf(materialLinks),
              ignoredMaterialIds: store.excludedMaterialIds,
              materialsLoading:
                  materialsAsync.isLoading && !materialsAsync.hasValue,
              onIgnore: (materialId) => store.excludeMaterial(materialId),
              // 忽略是可逆的（用户 2026-09-18：「可以忽略某些项，但是没有恢复手段」）。
              onRestore: (materialId) => store.includeMaterial(materialId),
              onAdd: () => showRecommendationItemSheet(
                context,
                ref,
                catalog: catalog,
              ),
              onEdit: (item) => showRecommendationItemSheet(
                context,
                ref,
                catalog: catalog,
                editing: item,
              ),
              onDelete: (item) => _deleteItem(store, item),
            ),
          if (_compareCategories(outcome).isNotEmpty) ...[
            const SizedBox(height: 12),
            _CompareCard(
              key: const Key('recCompareCard'),
              outcome: outcome,
              catalog: catalog,
              categories: _compareCategories(outcome),
            ),
          ],
          const SizedBox(height: 12),
          _RulesCard(
            key: const Key('recRulesCard'),
            catalog: catalog,
            doc: doc,
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(
    RecommendationStore store,
    BonusItemOutcome item,
  ) async {
    final ok = await geConfirmDelete(
      context,
      title: '删除加分项',
      message: '确定删除「${item.label}」吗？删除后不计入附加分。',
    );
    if (!ok) return;
    await store.remove(item.item.id);
  }
}

/// 「不累加对照」需要展示的类别 = 登记条目数 > 1 的类别。
List<BonusCategory> _compareCategories(RecommendationOutcome outcome) => [
  for (final c in BonusCategory.values)
    if (outcome.items.where((o) => o.item.category == c).length > 1) c,
];

String _fmt2(double v) => v.toStringAsFixed(2);

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// 统一卡片外壳（形状 / 底色 / 内边距一律走 `lib/design/app_card.dart`）。
Widget _card(BuildContext context, {required Widget child}) => Card(
  elevation: 0,
  margin: EdgeInsets.zero,
  shape: appCardShape(context),
  clipBehavior: Clip.antiAlias,
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: child,
  ),
);

/// 「标签 —— 值」一行（汇总卡的构成明细用）。
class _KvRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool strong;

  const _KvRow(this.label, this.value, {this.valueColor, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 13.5 : 12.5,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                color: AppColors.textMuted(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 14 : 13,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// 明细行（小字，缩进在标签右侧）。
class _DetailLine extends StatelessWidget {
  final String text;

  const _DetailLine(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.5,
        color: AppColors.textMuted(context),
      ),
    ),
  );
}

/// 加载中占位卡（资料库解析尚未返回）。
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => _card(
    context,
    child: const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    ),
  );
}

/// 资料库未解析到加分标准。
class _CatalogMissingCard extends StatelessWidget {
  final VoidCallback onRetry;

  const _CatalogMissingCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).recommendation;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          geCardTitle(
            context,
            text: '加分项',
            accent: accent,
            trailing: Icon(Icons.menu_book_outlined, size: 18, color: accent),
          ),
          const SizedBox(height: 8),
          Text(
            '资料库未解析到加分标准，请确认「规章制度」里有《…推免…工作办法》。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: AppColors.textMuted(context),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新解析'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 汇总卡：综合成绩 = 推免加权平均成绩 + 附加分。
class _SummaryCard extends StatelessWidget {
  final RecommendationWeightedResult? weightedResult;
  final bool loading;
  final RecommendationOutcome outcome;
  final BonusCatalog catalog;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onRetry;

  const _SummaryCard({
    super.key,
    required this.weightedResult,
    required this.loading,
    required this.outcome,
    required this.catalog,
    required this.expanded,
    required this.onToggle,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).recommendation;
    final result = weightedResult;

    if (result == null) {
      return _card(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(context, text: '综合成绩', accent: accent),
            const SizedBox(height: 12),
            if (loading)
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              _notReady(context),
          ],
        ),
      );
    }

    if (!result.importanceAvailable) {
      return _card(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(context, text: '综合成绩', accent: accent),
            const SizedBox(height: 12),
            _notReady(context),
          ],
        ),
      );
    }

    final w = result.weighted;
    final bonus = outcome.bonusTotal;

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '综合成绩',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textBase(context),
                ),
              ),
              const Spacer(),
              Text(
                _fmt2(outcome.total),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _KvRow(
            '推免加权平均成绩',
            _fmt2(outcome.weightedAverage),
            valueColor: AppColors.textBase(context),
          ),
          _KvRow(
            '附加分',
            '+${_fmt2(bonus)}${outcome.capped ? '（已封顶 ${geFmt(catalog.cap)} 分，未封顶 ${_fmt2(outcome.uncappedBonus)}）' : ''}',
            valueColor: bonus > 0
                ? AppColors.success(context)
                : AppColors.textMuted(context),
          ),
          _KvRow(
            '= 综合成绩',
            _fmt2(outcome.total),
            valueColor: accent,
            strong: true,
          ),
          const SizedBox(height: 6),
          InkWell(
            key: const Key('recWeightedToggle'),
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.textMuted(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    expanded ? '收起推免加权构成' : '展开推免加权构成',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            _DetailLine(
              '主干课程 ${geFmt(w.coreCredits)} 学分 · 加权 ${_fmt2(w.coreAverage)}'
              '（${w.coreCount} 门）',
            ),
            _DetailLine(
              '非主干课程 ${geFmt(w.nonCoreCredits)} 学分 · 加权 ${_fmt2(w.nonCoreAverage)}'
              '（${w.nonCoreCount} 门）',
            ),
            const _DetailLine('口径：主干×0.7 + 非主干×0.3'),
            _DetailLine(
              '参与计算 ${w.totalCount} 门'
              '（已排除军事训练等）',
            ),
          ],
          if (catalog.formulaNote != null || catalog.sourceTitle != null) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: AppColors.hairline(context)),
            const SizedBox(height: 8),
            if (catalog.formulaNote != null)
              Text(
                catalog.formulaNote!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: AppColors.textMuted(context),
                ),
              ),
            if (catalog.sourceTitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  '出处：${catalog.sourceTitle}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _notReady(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '培养方案未就绪，推免加权暂不可算',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.caution(context),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '推免加权平均成绩 = 主干课程加权×0.7 + 非主干课程加权×0.3，'
        '需要本专业培养方案判定课程地位。请先在「培养方案」里取到本专业方案后重试。',
        style: TextStyle(
          fontSize: 11.5,
          height: 1.6,
          color: AppColors.textMuted(context),
        ),
      ),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const Key('recRetryWeighted'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('重试'),
        ),
      ),
    ],
  );
}

/// 加分项卡：按五大类分组列出加分项，右上角「添加」。
///
/// 条目有两个来源：**材料库自动带入**（id 带 [kMaterialAwardIdPrefix] 前缀，行上
/// 打「材料库」徽标、只能「忽略」不能编辑/删除）与**手工登记**（可编辑/删除）。
/// 卡片底部另列「材料库里没算进来的条目」+ 原因（不是错误，是让人对得上账）。
class _BonusCard extends StatelessWidget {
  final RecommendationOutcome outcome;
  final BonusCatalog catalog;

  /// 材料库里没能自动计入的条目（含原因）。
  final List<MaterialAwardLink<RecommendationBonusItem>> skipped;

  /// 被手动「忽略」的材料 id（= store 的忽略名单）：这些条目从 [skipped] 里挪出来
  /// 单列一节并给「恢复」按钮（用户 2026-09-18：「可以忽略某些项，但是没有恢复手段」）。
  final Set<String> ignoredMaterialIds;

  /// 材料库是否还在读（读的时候不显示「未计入」以免闪一下「全都没算」）。
  final bool materialsLoading;

  final void Function(String materialId) onIgnore;

  /// 「恢复」一条被忽略的材料（参数 = 材料 id）：从忽略名单里摘掉，当帧重新计入。
  final void Function(String materialId) onRestore;

  final VoidCallback onAdd;
  final void Function(RecommendationBonusItem item) onEdit;
  final void Function(BonusItemOutcome item) onDelete;

  const _BonusCard({
    super.key,
    required this.outcome,
    required this.catalog,
    this.skipped = const [],
    this.ignoredMaterialIds = const {},
    this.materialsLoading = false,
    required this.onIgnore,
    required this.onRestore,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).recommendation;
    // 未计入的材料分两拨：被忽略的（要能恢复）与其它没算进来的。
    final materials = splitIgnoredMaterials(skipped, ignoredMaterialIds);
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          geCardTitle(
            context,
            text: '加分项（附加分 ${_fmt2(outcome.bonusTotal)} 分）',
            accent: accent,
            trailing: TextButton.icon(
              key: const Key('recAddItem'),
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加'),
            ),
          ),
          if (!outcome.hasItems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '还没有加分项。材料库里登记的竞赛 / 专利 / 著作权 / 荣誉 / 论文会自动'
                '带进来并计入；也可以点右上「添加」手工补一条。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: AppColors.textMuted(context),
                ),
              ),
            )
          else
            for (final category in BonusCategory.values)
              if (outcome.items.any((o) => o.item.category == category)) ...[
                const SizedBox(height: 6),
                _groupLabel(context, category),
                for (final o in outcome.items)
                  if (o.item.category == category)
                    _ItemRow(
                      outcome: o,
                      onEdit: () => onEdit(o.item),
                      onDelete: () => onDelete(o),
                      onIgnore: _ignoreActionFor(o.item.id),
                    ),
              ],
          if (!materialsLoading && materials.ignored.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: AppColors.hairline(context)),
            const SizedBox(height: 8),
            Text(
              '已忽略 ${materials.ignored.length} 条',
              key: const Key('recIgnoredMaterials'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textBase(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '这些材料库条目被你在页面上忽略了，不计入附加分；点「恢复」就重新算进来。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: AppColors.textMuted(context),
                ),
              ),
            ),
            for (final link in materials.ignored)
              _ignoredRow(context, link.material),
          ],
          if (!materialsLoading && materials.skipped.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: AppColors.hairline(context)),
            const SizedBox(height: 8),
            Row(
              key: const Key('recSkippedMaterials'),
              children: [
                Text(
                  '材料库里还有 ${materials.skipped.length} 条没算进来',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textBase(context),
                  ),
                ),
              ],
            ),
            for (final link in materials.skipped)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '· ${link.material.displayName}：${link.reason ?? '未识别'}',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ),
          ],
          if (outcome.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: AppColors.hairline(context)),
            const SizedBox(height: 8),
            for (final w in outcome.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  w,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.caution(context),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 自动带入的条目（id = `material:<材料 id>`）→ 「忽略」回调；手填条目返回 null。
  VoidCallback? _ignoreActionFor(String itemId) {
    final materialId = materialIdOfAwardId(itemId);
    return materialId == null ? null : () => onIgnore(materialId);
  }

  /// 「已忽略」里的一行：材料名 + 「恢复」。
  Widget _ignoredRow(BuildContext context, ZcMaterial material) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '· ${material.displayName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textMuted(context),
              ),
            ),
          ),
          TextButton.icon(
            key: Key('recRestoreMaterial-${material.id}'),
            onPressed: () => onRestore(material.id),
            icon: const Icon(Icons.undo, size: 14),
            label: const Text('恢复'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 26),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupLabel(BuildContext context, BonusCategory category) {
    final count = catalog.optionsOf(category).length;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        children: [
          Text(
            category.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textBase(context),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count 个项目',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textMuted(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一条加分项。自动带入的（[onIgnore] 非空）打「材料库」徽标、只能忽略不能改删。
class _ItemRow extends StatelessWidget {
  final BonusItemOutcome outcome;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 非空 = 这条来自材料库，点击这里是「忽略」（不改材料库本身）。
  final VoidCallback? onIgnore;

  const _ItemRow({
    required this.outcome,
    required this.onEdit,
    required this.onDelete,
    this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final item = outcome.item;
    final counted = outcome.counted;
    final auto = onIgnore != null;
    final subtitle = counted
        ? item.summary
        : '${item.summary} · ${outcome.reason}';

    return InkWell(
      key: Key('recItemTile-${item.id}'),
      onTap: auto ? null : onEdit,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: counted ? 1 : 0.55,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            outcome.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textBase(context),
                            ),
                          ),
                        ),
                        if (auto) ...[
                          const SizedBox(width: 6),
                          _MaterialBadge(itemId: item.id),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: AppColors.textMuted(context),
                      ),
                    ),
                    if (item.note != null && item.note!.isNotEmpty)
                      Text(
                        item.note!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+${_fmt2(outcome.points)}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: counted
                        ? AppColors.success(context)
                        : AppColors.textMuted(context),
                  ),
                ),
              ),
              if (auto)
                IconButton(
                  key: Key('recIgnoreItem-${item.id}'),
                  onPressed: onIgnore,
                  tooltip: '忽略这条（自动带入）· 忽略后可在卡片下方「已忽略」里恢复',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.visibility_off_outlined,
                    color: AppColors.textMuted(context),
                  ),
                )
              else
                IconButton(
                  key: Key('recDeleteItem-${item.id}'),
                  onPressed: onDelete,
                  tooltip: '删除',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline,
                    color: AppColors.textMuted(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「材料库」来源徽标（自动带入的条目上）。
class _MaterialBadge extends StatelessWidget {
  final String itemId;

  const _MaterialBadge({required this.itemId});

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).recommendation;
    return Container(
      key: Key('recAutoBadge-$itemId'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.tint(context, accent, 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '材料库',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}

/// 不累加对照卡：办法口径（每类只计一项）vs 若按条目累加。
class _CompareCard extends StatelessWidget {
  final RecommendationOutcome outcome;
  final BonusCatalog catalog;
  final List<BonusCategory> categories;

  const _CompareCard({
    super.key,
    required this.outcome,
    required this.catalog,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).recommendation;
    final note = catalog.notes.firstWhere(
      (n) => n.contains('只计一项'),
      orElse: () => '',
    );
    final headerStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted(context),
    );

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          geCardTitle(context, text: '不累加对照', accent: accent),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text('办法口径（每类只计一项）', style: headerStyle)),
              Expanded(
                child: Text(
                  '若按条目累加（对照）',
                  style: headerStyle,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${category.label}：'
                      '${_fmt2(outcome.categoryBest[category] ?? 0)} 分',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textBase(context),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${category.label}：'
                      '${_fmt2(outcome.categorySum[category] ?? 0)} 分',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted(context),
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Divider(height: 1, color: AppColors.hairline(context)),
            const SizedBox(height: 6),
            Text(
              '第十条：$note',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textMuted(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 规则出处卡：附件名 + 前三条注记 + 原文入口。
class _RulesCard extends StatelessWidget {
  final BonusCatalog catalog;
  final RuleDoc? doc;

  const _RulesCard({super.key, required this.catalog, required this.doc});

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).recommendation;
    final notes = catalog.notes.take(3).toList();
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          geCardTitle(
            context,
            text: catalog.attachmentTitle ?? '加分标准出处',
            accent: accent,
          ),
          if (catalog.sourceTitle != null) ...[
            const SizedBox(height: 6),
            Text(
              catalog.sourceTitle!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textBase(context),
              ),
            ),
          ],
          const SizedBox(height: 6),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                note,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: AppColors.textMuted(context),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('recOpenSource'),
              onPressed: doc == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => RulesReaderScreen(doc: doc!),
                      ),
                    ),
              child: const Text('查看规章制度原文'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── 添加 / 编辑弹层 ───────────────────────────

/// 打开「添加 / 编辑加分项」底部弹层。
///
/// [catalog] 省略时从 [bonusCatalogProvider] 取当前缓存值（取不到 = 空目录）。
Future<void> showRecommendationItemSheet(
  BuildContext context,
  WidgetRef ref, {
  BonusCatalog? catalog,
  RecommendationBonusItem? editing,
}) {
  final resolved =
      catalog ??
      ref.read(bonusCatalogProvider).valueOrNull ??
      BonusCatalog.empty;
  final store = ref.read(recommendationStoreProvider);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        RecommendationItemSheet(catalog: resolved, store: store, editing: editing),
  );
}

/// 加分项登记表单（类别 → 项目 → 等级/排名/日期 → 备注）。
class RecommendationItemSheet extends StatefulWidget {
  final BonusCatalog catalog;
  final RecommendationStore store;
  final RecommendationBonusItem? editing;

  const RecommendationItemSheet({
    super.key,
    required this.catalog,
    required this.store,
    this.editing,
  });

  @override
  State<RecommendationItemSheet> createState() =>
      _RecommendationItemSheetState();
}

class _RecommendationItemSheetState extends State<RecommendationItemSheet> {
  late BonusCategory _category;
  BonusOption? _option;
  String? _tier;
  int? _rank;
  DateTime? _awardDate;

  final _searchCtrl = TextEditingController();
  final _rankCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _category =
        editing?.category ?? _firstCategoryWithOptions(widget.catalog);
    if (editing != null) {
      _option = widget.catalog.optionById(editing.optionId);
      _tier = editing.tierLabel;
      _rank = editing.rank;
      _awardDate = editing.awardDate;
      _rankCtrl.text = editing.rank?.toString() ?? '';
      _noteCtrl.text = editing.note ?? '';
      if (editing.awardDate != null) {
        _dateCtrl.text = _fmtDate(editing.awardDate!);
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _rankCtrl.dispose();
    _noteCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  static BonusCategory _firstCategoryWithOptions(BonusCatalog catalog) {
    for (final c in BonusCategory.values) {
      if (catalog.optionsOf(c).isNotEmpty) return c;
    }
    return BonusCategory.contest;
  }

  List<BonusOption> get _visibleOptions {
    final q = _searchCtrl.text.trim();
    return [
      for (final o in widget.catalog.optionsOf(_category))
        if (q.isEmpty ||
            o.label.contains(q) ||
            (o.detail ?? '').contains(q) ||
            (o.group ?? '').contains(q))
          o,
    ];
  }

  bool get _needsTier => _option?.hasTiers ?? false;

  bool get _canSave => _option != null && (!_needsTier || _tier != null);

  void _selectCategory(BonusCategory c) {
    setState(() {
      _category = c;
      _option = null;
      _tier = null;
      _searchCtrl.clear();
    });
  }

  void _selectOption(BonusOption o) {
    setState(() {
      _option = o;
      _tier = o.tiers.length == 1 ? o.tiers.first.label : null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _awardDate ?? now,
      firstDate: DateTime(now.year - 12),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: '选择获奖日期',
      cancelText: '清除',
    );
    if (!mounted) return;
    if (picked == null) {
      // showDatePicker 的「取消」在本表单里等于「清除已选日期」。
      setState(() {
        _awardDate = null;
        _dateCtrl.clear();
      });
      return;
    }
    setState(() {
      _awardDate = picked;
      _dateCtrl.text = _fmtDate(picked);
    });
  }

  Future<void> _save() async {
    final option = _option;
    if (option == null) return;
    final note = _noteCtrl.text.trim();
    final item = RecommendationBonusItem(
      id: widget.editing?.id ?? newRecommendationItemId(),
      category: _category,
      optionId: option.id,
      optionLabel: option.label,
      tierLabel: _tier,
      rank: _category == BonusCategory.contest ? _rank : null,
      awardDate: _awardDate,
      note: note.isEmpty ? null : note,
    );
    final store = widget.store;
    if (widget.editing == null) {
      await store.add(item);
    } else {
      await store.update(item);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).recommendation;
    final option = _option;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.editing == null ? '添加加分项' : '编辑加分项',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textBase(context),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in BonusCategory.values)
                  ChoiceChip(
                    key: Key('recCategoryChip-${c.name}'),
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => _selectCategory(c),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _category.hint,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textMuted(context),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('recOptionSearch'),
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                labelText: '搜索项目',
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: _visibleOptions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '该类别没有匹配的项目。',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _visibleOptions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) => _optionTile(
                        context,
                        _visibleOptions[i],
                        accent,
                      ),
                    ),
            ),
            if (option != null && option.hasTiers) ...[
              const SizedBox(height: 12),
              Text(
                '获奖等级',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textBase(context),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in option.tiers)
                    ChoiceChip(
                      key: Key('recTierChip-${t.label}'),
                      label: Text('${t.label} ${geFmt(t.points)} 分'),
                      selected: _tier == t.label,
                      onSelected: (_) => setState(() => _tier = t.label),
                    ),
                ],
              ),
            ],
            if (_category == BonusCategory.contest) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('recRankField'),
                controller: _rankCtrl,
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() {
                  _rank = int.tryParse(v.trim());
                }),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '排名（1 起）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('recDateField'),
                controller: _dateCtrl,
                readOnly: true,
                onTap: _pickDate,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '获奖日期',
                  hintText: '未填写',
                  suffixIcon: Icon(Icons.event, size: 18),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_fmtDate(widget.catalog.legacyCutoff)} 前取得的获奖，'
                '排名第 6 及以后按满分 '
                '×${geFmt(widget.catalog.legacyFactor)}',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: AppColors.textMuted(context),
                ),
              ),
              if (widget.catalog.rankFactors.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  '排名系数：'
                  '${widget.catalog.rankFactors.map((f) => '${f.label} ×${geFmt(f.factor)}').join(' · ')}',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            TextField(
              key: const Key('recNoteField'),
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                isDense: true,
                labelText: '备注（可空）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const Key('recSaveItem'),
                    onPressed: _canSave ? _save : null,
                    child: const Text('保存'),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(BuildContext context, BonusOption o, Color accent) {
    final selected = _option?.id == o.id;
    return InkWell(
      key: Key('recOptionTile-${o.id}'),
      onTap: () => _selectOption(o),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.tint(context, accent, 0.10)
              : AppColors.fillSoft(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.5)
                : AppColors.stroke(context),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              o.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: AppColors.textBase(context),
              ),
            ),
            if (o.detail != null && o.detail!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                o.detail!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted(context),
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              o.pointsHint,
              style: TextStyle(fontSize: 11.5, color: accent),
            ),
          ],
        ),
      ),
    );
  }
}
