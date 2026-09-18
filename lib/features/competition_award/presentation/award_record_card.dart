/// 竞赛奖励 · 「获奖记录」卡（用户登记的获奖 + 材料库自动带入的获奖）。
///
/// 四条口径写死在这里：
/// 1. **未计入的记录也要显示**（用户口径「手动选择时间范围」的代价就是会有记录
///    落在区间外），但**表现分两档**（用户 2026-09-18：「不计入的项变暗，而不是
///    显示那个什么第九条的提示」）：
///    - 被取最高挤掉的（`AwardRecordOutcome.suppressed`，同一奖项 / 同类里已有更高的
///      一项）→ **整行变暗 + 金额处写「未计入」**，不再印原因（那是正常取舍，
///      办法条款留在「本次统计口径」卡里）；
///    - 压根算不出来的（缺日期 / 超范围 / 无标准 / Ⅳ类 / 等次认不出）→ 同样变暗，
///      但**原因照旧印出来** —— 那是唯一能解释「为什么没算钱」的信息，静默丢弃
///      会让人以为记录丢了 / 算错了；
/// 2. 金额一律 `fmtAwardAmount`（≥1 万走「万元」），未计入则显示「未计入」而不是 0 元；
/// 3. 记录有**两个来源**（用户 2026-09-18 裁定「加分项自动从资料库中获取」）：
///    材料库自动带入的（id 带 `material:` 前缀，行上打「材料库」徽标、**只能忽略
///    不能编辑 / 删除** —— 它由材料库派生，改了也留不住）与手工登记的（可增删改）；
/// 4. 材料库里**没算进来**的条目另起一节列清（材料名 + 原因）：口径是「这些条目没有
///    对得上的奖励标准」，是让人对得上账，**不是错误提示**；
/// 5. **被「忽略」的条目单独一节 + 逐条「恢复」**（用户 2026-09-18：「竞赛奖励功能里
///    可以忽略某些项，但是没有恢复手段」）：忽略名单记在 store 里、材料库本身一个字
///    都不改，但页面上必须能撤回来 —— 否则忽略是单向操作，材料会永远消失。所以忽略
///    过的条目归到「已忽略」节（带「恢复」按钮），**不再混在「没算进来」那节里**
///    （那节是「材料库的问题」，这节是「你自己的选择」）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/materials/domain/material_award_bridge.dart';
import 'package:smarter_jxufe/features/score_estimate/presentation/ge_common.dart';

import '../domain/award_calc.dart';
import '../domain/award_coefficient.dart';
import '../domain/award_record.dart';
import 'award_common.dart';

/// 未计入行的压暗系数（两侧同一个值）。
///
/// 0.55 = 明显「灰掉」但仍读得出是哪一条；只压**信息**那一列 —— 行尾的
/// 「忽略 / 删除」按钮不动，压暗了会让唯一能撤销动作的入口跟着变模糊。
const double kAwardDimOpacity = 0.55;

class AwardRecordCard extends StatelessWidget {
  const AwardRecordCard({
    super.key,
    required this.outcome,
    required this.records,
    this.autoRecords = const [],
    this.skipped = const [],
    this.ignoredMaterialIds = const {},
    required this.loaded,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onIgnoreMaterial,
    required this.onRestoreMaterial,
  });

  final CompetitionAwardOutcome outcome;

  /// 用户手工登记的记录（存在本地 Hive 里）。
  final List<CompetitionAwardRecord> records;

  /// 材料库自动带入的记录（每次从材料库现算，**不落库**）。
  final List<CompetitionAwardRecord> autoRecords;

  /// 材料库里没能自动计入的条目（含原因），逐条列在卡片底部「未计入」小节。
  final List<MaterialAwardLink<CompetitionAwardRecord>> skipped;

  /// 被手动「忽略」的材料 id（= store 的忽略名单）。
  ///
  /// [skipped] 里属于这一批的会挪到「已忽略」小节并给「恢复」按钮
  /// （口径见 [splitIgnoredMaterials]），不再算进「还有 N 条没算进来」的条数。
  final Set<String> ignoredMaterialIds;

  /// 本地记录是否已从 Hive 读出（未读出时显示「正在载入」而不是「空空如也」）。
  final bool loaded;

  final VoidCallback onAdd;
  final ValueChanged<CompetitionAwardRecord> onEdit;
  final ValueChanged<CompetitionAwardRecord> onDelete;

  /// 「忽略」一条自动带入的记录（参数 = 材料 id，不改材料库本身）。
  final ValueChanged<String> onIgnoreMaterial;

  /// 「恢复」一条被忽略的材料（参数 = 材料 id）：从忽略名单里摘掉，当帧重新计入。
  final ValueChanged<String> onRestoreMaterial;

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).competitionAward;
    final excluded = outcome.excludedItems;
    // 未计入的材料分两拨：被忽略的（要能恢复）与其它没算进来的。
    final materials = splitIgnoredMaterials(skipped, ignoredMaterialIds);
    // 行数 = 手填 + 自动（`outcome.items` 里两者都有，顺序 = 手填在前、自动在后）。
    final rowCount = records.length + autoRecords.length;
    return KeyedSubtree(
      key: const Key('awardRecordCard'),
      child: awardCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            geCardTitle(
              context,
              text: '获奖记录（$rowCount 条）',
              accent: accent,
              trailing: TextButton.icon(
                key: const Key('awardAddRecord'),
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ),
            const SizedBox(height: 6),
            if (!loaded)
              AwardEmptyHint(
                icon: Icons.hourglass_empty,
                text: '正在载入本地记录…',
              )
            else if (rowCount == 0)
              AwardEmptyHint(
                icon: Icons.emoji_events_outlined,
                text: '还没有登记获奖记录。',
                hint:
                    '材料库里登记的学科竞赛获奖会自动带进来并计入；'
                    '也可以点右上「添加」手工补录。',
                actionLabel: '添加',
                actionKey: const Key('awardAddRecordEmpty'),
                onAction: onAdd,
              )
            else
              for (final item in outcome.items)
                _tile(context, item, accent),
            if (loaded && excluded.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '未计入的 ${excluded.length} 条已变暗',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted(context),
                  ),
                ),
              ),
            if (loaded && materials.ignored.isNotEmpty)
              _ignoredSection(context, materials.ignored),
            if (loaded && materials.skipped.isNotEmpty)
              _skippedSection(context, materials.skipped),
          ],
        ),
      ),
    );
  }

  /// 「材料库里没算进来」小节：逐条列材料名 + 原因。
  ///
  /// 口径 = **对账，不是报错**（一条都没有时整节不渲染）。被「忽略」的条目不在这一节，
  /// 见 [_ignoredSection]。
  Widget _skippedSection(
    BuildContext context,
    List<MaterialAwardLink<CompetitionAwardRecord>> skipped,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        key: const Key('awardSkippedMaterials'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '材料库里还有 ${skipped.length} 条没算进来',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textBase(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '不是出错 —— 材料库这些条目没有对得上的奖励标准，列出来让你对得上账：',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textMuted(context),
              ),
            ),
          ),
          for (final link in skipped)
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
      ),
    );
  }

  /// 「已忽略」小节：逐条给「恢复」按钮（用户 2026-09-18：「可以忽略某些项，但是
  /// 没有恢复手段」）。
  ///
  /// 恢复 = 把材料 id 从忽略名单里摘掉，材料库本身一个字都不改；恢复后当帧就重新
  /// 计入（自动条目不落库，每次由材料库现算）。
  Widget _ignoredSection(
    BuildContext context,
    List<MaterialAwardLink<CompetitionAwardRecord>> ignored,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        key: const Key('awardIgnoredMaterials'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '已忽略 ${ignored.length} 条',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textBase(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '这些材料库条目被你在页面上忽略了，不计入合计；点「恢复」就重新算进来。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textMuted(context),
              ),
            ),
          ),
          for (final link in ignored) _ignoredRow(context, link),
        ],
      ),
    );
  }

  Widget _ignoredRow(
    BuildContext context,
    MaterialAwardLink<CompetitionAwardRecord> link,
  ) {
    final material = link.material;
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
            key: Key('awardRestoreMaterial-${material.id}'),
            onPressed: () => onRestoreMaterial(material.id),
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

  Widget _tile(
    BuildContext context,
    AwardRecordOutcome item,
    Color accent,
  ) {
    final record = item.record;
    final counted = item.counted;
    // 自动带入的行（id = `material:<材料 id>`）由材料库派生 → 不给编辑 / 删除，
    // 只给「忽略」（忽略名单记在 store 里，材料库本身一个字都不改）。
    final materialId = materialIdOfAwardId(record.id);
    final auto = materialId != null;

    // 未计入 → 整列信息压暗（用户 2026-09-18：「不计入的项变暗，而不是显示那个什么
    // 第九条的提示」）。只压信息那一列，行尾的「忽略 / 删除」保持原样 —— 一起压暗
    // 会让唯一能撤销动作的入口跟着变模糊。
    final dimmed = !counted;

    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  // Key 只为守卫测试能取到这个值（未计入 = 0.55、计入 = 1）。
                  key: Key('awardDim-${record.id}'),
                  opacity: dimmed ? kAwardDimOpacity : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              record.competitionName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                          if (auto) ...[
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: _MaterialBadge(recordId: record.id),
                            ),
                          ],
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: AwardClassChip(klass: item.effectiveKlass),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        record.summary,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                      if (record.note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            record.note!,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: AppColors.textMuted(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // 被「取最高」挤掉的（suppressed）不印原因 —— 变暗就已经说明了；
                // 压根算不出来的仍要写清楚为什么（否则「为什么没算钱」无从得知），
                // 而且**压在压暗之外**（0.55 的警示色只剩 ~1.7:1，等于看不清）。
                if (!counted && !item.suppressed)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.reason,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppColors.caution(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 行内明算（用户 2026-09-18 拍板）：被赛事经验系数缩减过的记录，
              // 把「标准金额 × 系数 =」也写出来，别让人以为算错了。
              if (item.scaled)
                Text(
                  '${fmtAwardAmount(item.baseAmount)} '
                  '×${fmtAwardCoefficient(item.coefficient)} =',
                  key: Key('awardScaleExpr-${record.id}'),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: AppColors.textMuted(context),
                  ),
                ),
              Text(
                counted ? fmtAwardAmount(item.amount) : '未计入',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: counted ? FontWeight.w700 : FontWeight.w500,
                  color: counted ? accent : AppColors.textMuted(context),
                ),
              ),
              SizedBox(
                width: 32,
                height: 26,
                child: auto
                    ? IconButton(
                        key: Key('awardIgnoreMaterial-$materialId'),
                        padding: EdgeInsets.zero,
                        tooltip: '忽略这条（自动带入）· 忽略后可在卡片下方「已忽略」里恢复',
                        iconSize: 17,
                        icon: Icon(
                          Icons.visibility_off_outlined,
                          color: AppColors.textMuted(context),
                        ),
                        onPressed: () => onIgnoreMaterial(materialId),
                      )
                    : IconButton(
                        key: Key('awardDeleteRecord-${record.id}'),
                        padding: EdgeInsets.zero,
                        tooltip: '删除',
                        iconSize: 17,
                        icon: Icon(
                          Icons.delete_outline,
                          color: AppColors.textMuted(context),
                        ),
                        onPressed: () => onDelete(record),
                      ),
              ),
            ],
          ),
        ],
      ),
    );

    // 自动行不给编辑入口（点行 = 什么都不发生），手填行行为与从前完全一致。
    if (auto) {
      return KeyedSubtree(
        key: Key('awardRecordTile-${record.id}'),
        child: body,
      );
    }
    return InkWell(
      key: Key('awardRecordTile-${record.id}'),
      onTap: () => onEdit(record),
      borderRadius: BorderRadius.circular(8),
      child: body,
    );
  }
}

/// 「材料库」来源徽标（自动带入的行上）。
class _MaterialBadge extends StatelessWidget {
  const _MaterialBadge({required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context) {
    final accent = fp(context).competitionAward;
    return Container(
      key: Key('awardAutoBadge-$recordId'),
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
