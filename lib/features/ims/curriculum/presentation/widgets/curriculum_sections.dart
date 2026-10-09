/// 培养方案页的**主体渲染**：理论课程的分组卡 + 实践环节那一段。
///
/// 每张卡的结构 = 组头（二级分类 / 环节类别）+ 行 + 组间分隔线；
/// 行本身在 `curriculum_common.dart`（课程行 / 实践环节行）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/fluent/fluent.dart';
import 'package:smarter_jxufe/features/ims/curriculum/domain/curriculum_browse.dart';
import 'package:smarter_jxufe/features/ims/curriculum/presentation/widgets/curriculum_common.dart';

/// 理论课程：按 [CurriculumBrowseResult.sections] 逐节画「节标题 + 卡片」。
class CurriculumSections extends StatelessWidget {
  const CurriculumSections({
    super.key,
    required this.result,
    required this.mode,
    required this.expandedKeys,
    required this.onToggle,
  });

  final CurriculumBrowseResult result;

  /// 当前分组形态：「按分类」时组头已经是二级分类，行内不再重复写一遍。
  final CurriculumGroupMode mode;

  /// 已展开学时明细的课程（[CurriculumCourseItem.key]）。
  final Set<String> expandedKeys;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in result.sections) ...[
          FluentSectionHeader(
            title: section.title,
            description:
                '${section.count} 门 · ${crCreditText(section.credits)} 学分'
                '${section.code == null ? '' : ' · ${section.code}'}',
          ),
          FluentCard(
            padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < section.groups.length; i++) ...[
                  if (i > 0)
                    const FluentDivider(
                      indent: FluentSpacing.md,
                      endIndent: FluentSpacing.md,
                    ),
                  if (section.groups[i].title.isNotEmpty)
                    _GroupHeader(group: section.groups[i]),
                  for (final item in section.groups[i].items)
                    CurriculumCourseRow(
                      item: item,
                      expanded: expandedKeys.contains(item.key),
                      onToggle: () => onToggle(item.key),
                      showCategory: mode != CurriculumGroupMode.category,
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: FluentSpacing.xl),
        ],
      ],
    );
  }
}

/// 组头：二级分类（或学期里的大类）+ 门数与学分小计。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final CurriculumGroup group;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FluentSpacing.lg,
        FluentSpacing.md,
        FluentSpacing.lg,
        FluentSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.title,
              style: FluentType.bodyStrong.copyWith(color: p.textPrimary),
            ),
          ),
          const SizedBox(width: FluentSpacing.sm),
          Text(
            '${group.count} 门 · ${crCreditText(group.credits)} 学分',
            style: FluentType.caption.copyWith(color: p.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 实践环节那一段（培养方案第二张表）。
///
/// 三种状态如实分开：**没取到**（[error]）／**还没取到**（[loading]）／
/// **取到了但一条都没命中**（[browse] 为空）—— 不把「没取到」说成「没有」。
class PracticeSection extends StatelessWidget {
  const PracticeSection({
    super.key,
    required this.browse,
    required this.error,
    required this.loading,
    required this.onRetry,
  });

  final PracticeBrowseResult? browse;
  final String? error;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final result = browse;
    final description = switch ((result, error, loading)) {
      (null, _, true) => '正在读取教务「培养方案 → 实践环节」…',
      (null, final e?, _) => '没取到：$e',
      (null, null, _) => '教务没有返回实践环节表',
      (final r?, _, _) =>
        '共 ${r.totalCount} 项 · ${crCreditText(r.totalCredits)} 学分'
            '${r.filtered ? '（当前命中 ${r.matchedCount} 项）' : ''}',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FluentSectionHeader(
          title: '实践环节',
          description: description,
          trailing: loading
              ? null
              : FluentIconButton(
                  icon: Icons.refresh,
                  tooltip: '重新获取实践环节',
                  onPressed: onRetry,
                ),
        ),
        if (error != null && result == null)
          FluentInfoBar(
            severity: FluentInfoSeverity.warning,
            message: '实践环节表没取到（$error）。它需要教务会话；'
                '理论课程与开课学期不受影响。',
            action: FluentButton(label: '重试', onPressed: onRetry),
          )
        else if (result == null)
          const FluentCard(
            padding: EdgeInsets.all(FluentSpacing.lg),
            child: FluentLoading(message: '正在读取实践环节…'),
          )
        else if (result.isEmpty)
          FluentInfoBar(
            message: result.totalCount == 0
                ? '教务「实践环节」表里没有条目（这个专业的方案可能还没下发这一张表）。'
                : '当前的搜索 / 筛选下没有命中的实践环节（共 ${result.totalCount} 项）。',
          )
        else
          FluentCard(
            padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < result.groups.length; i++) ...[
                  if (i > 0)
                    const FluentDivider(
                      indent: FluentSpacing.md,
                      endIndent: FluentSpacing.md,
                    ),
                  if (result.groups[i].title.isNotEmpty)
                    _PracticeGroupHeader(group: result.groups[i]),
                  for (final stage in result.groups[i].stages)
                    PracticeStageRow(stage: stage),
                ],
              ],
            ),
          ),
        const SizedBox(height: FluentSpacing.xl),
      ],
    );
  }
}

class _PracticeGroupHeader extends StatelessWidget {
  const _PracticeGroupHeader({required this.group});

  final PracticeGroup group;

  @override
  Widget build(BuildContext context) {
    final p = fluent(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FluentSpacing.lg,
        FluentSpacing.md,
        FluentSpacing.lg,
        FluentSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.title,
              style: FluentType.bodyStrong.copyWith(color: p.textPrimary),
            ),
          ),
          const SizedBox(width: FluentSpacing.sm),
          Text(
            '${group.count} 项 · ${crCreditText(group.credits)} 学分',
            style: FluentType.caption.copyWith(color: p.textTertiary),
          ),
        ],
      ),
    );
  }
}
