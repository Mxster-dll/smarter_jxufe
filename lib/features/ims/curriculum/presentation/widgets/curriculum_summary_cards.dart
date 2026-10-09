/// 培养方案页的**顶部指标卡**：理论课程 + 实践环节，以及各大类的学分占比。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/breakpoints.dart';
import 'package:smarter_jxufe/design/fluent/fluent.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_browse.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/practice_stage.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/widgets/curriculum_common.dart';

/// 两张指标卡：**理论课程**（学分 + 门数构成 + 大类占比条）与**实践环节**。
///
/// 布局两档（同毕业学分页 §13.8 的口径）：≥ [Breakpoints.wide] 并排且等高，更窄竖着堆。
class CurriculumOverviewCards extends StatelessWidget {
  const CurriculumOverviewCards({
    super.key,
    required this.summary,
    required this.practice,
    required this.refreshing,
    required this.onRefresh,
  });

  final CurriculumSummary summary;
  final PracticeCurriculum? practice;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theory = FluentMetricCard(
      label: '理论课程（教学计划）',
      value: crCreditText(summary.totalCredits),
      unit: '学分',
      description:
          '共 ${summary.totalCount} 门 · 必修 ${summary.compulsoryCount} 门 / '
          '${crCreditText(summary.compulsoryCredits)} 学分 · '
          '选修 / 限选 ${summary.otherCount} 门 / '
          '${crCreditText(summary.otherCredits)} 学分'
          '${summary.coreCount == 0 ? '' : ' · 主干 ${summary.coreCount} 门'}',
      trailing: FluentIconButton(
        icon: Icons.refresh,
        tooltip: refreshing ? '正在更新…' : '从教务重新获取',
        onPressed: refreshing ? null : onRefresh,
      ),
      footer: CurriculumCategoryShare(shares: summary.categoryShares),
    );

    final practiceCard = FluentMetricCard(
      label: '实践环节',
      value: practice == null ? '—' : crCreditText(practice!.totalCredits),
      unit: practice == null ? null : '学分',
      description: practice == null
          ? '实践环节表未取到（需要教务会话）'
          : '共 ${practice!.stages.length} 项 · '
                '${_practiceBreakdown(practice!.stages)}',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Breakpoints.wide) {
          return Column(
            children: [
              theory,
              const SizedBox(height: FluentSpacing.md),
              practiceCard,
            ],
          );
        }
        // ⚠ 直接 `Row(stretch)` 会在 `ListView` 里拿到无界高度 → 断言崩；
        // 必须包 `IntrinsicHeight`（同 §13.8 的教训）。
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: theory),
              const SizedBox(width: FluentSpacing.md),
              Expanded(child: practiceCard),
            ],
          ),
        );
      },
    );
  }

  /// 「军训 2 · 科研创新实践 4 · …」（按首次出现顺序）。
  static String _practiceBreakdown(List<PracticeStage> stages) {
    final order = <String>[];
    final credits = <String, double>{};
    for (final stage in stages) {
      final key = stage.category.trim().isEmpty ? '未分类' : stage.category.trim();
      if (!credits.containsKey(key)) order.add(key);
      credits[key] = (credits[key] ?? 0) + stage.credit;
    }
    return [
      for (final key in order) '$key ${crCreditText(credits[key]!)}',
    ].join(' · ');
  }
}

/// 各大类学分占比：一条 [FluentShareBar] + 与条上深浅一一对应的图例。
class CurriculumCategoryShare extends StatelessWidget {
  const CurriculumCategoryShare({super.key, required this.shares});

  /// 按大类首次出现顺序（与条上从左到右一致）。
  final List<({String label, double credits})> shares;

  @override
  Widget build(BuildContext context) {
    if (shares.isEmpty) return const SizedBox.shrink();
    final p = fluent(context);
    final total = shares.fold<double>(0, (sum, s) => sum + s.credits);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FluentShareBar(
          segments: [
            for (final share in shares)
              FluentShareSegment(
                weight: share.credits,
                tooltip: '${share.label} ${crCreditText(share.credits)} 学分',
              ),
          ],
        ),
        const SizedBox(height: FluentSpacing.sm),
        Wrap(
          spacing: FluentSpacing.lg,
          runSpacing: FluentSpacing.xs,
          children: [
            for (var i = 0; i < shares.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(
                        alpha: fluentShareAlpha(i, shares.length),
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: FluentSpacing.xs),
                  // ⚠ 窄屏（280 实测）图例文字会把 Row 顶出 22~47px：文字必须可压缩 +
                  // 省略号，别指望 Wrap 会替它换行（Wrap 只管整条图例的换行）。
                  Flexible(
                    child: Text(
                      '${shares[i].label} '
                      '${crCreditText(shares[i].credits)} 学分'
                      '${total <= 0 ? '' : '（${(shares[i].credits / total * 100).round()}%）'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluentType.caption.copyWith(color: p.textSecondary),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
