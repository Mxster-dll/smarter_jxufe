import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/fluent/fluent.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/data/providers/graduation_requirements_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/graduation_requirements/domain/graduation_requirement.dart';

/// 毕业学分要求数据 Provider。
final graduationRequirementsProvider =
    FutureProvider<List<GraduationRequirement>>((ref) async {
      final repo = await ref.watch(
        graduationRequirementsRepositoryProvider.future,
      );
      final result = await repo.getGraduationRequirements();
      return result.fold(
        (failure) => throw Exception(failure.message ?? '获取毕业学分要求失败'),
        (requirements) => requirements,
      );
    });

/// 毕业学分要求页面（Fluent / WinUI 3 视觉）。
///
/// 结构：Hero 指标卡（合计学分 + 占比条 + 刷新）→「要求明细」节标题 → 卡片列表
/// （每项一行：序号徽标 / 项目名 / 占比说明 / 学分）+ 合计行。
///
/// 数据仍来自教务 `DataTable.jsp?tableId=6033`（选修学分要求），页面**不重算口径**，
/// 合计优先取教务给的合计行，缺了才退回各项求和（见 [_RequirementsView]）。
class GraduationRequirementsScreen extends ConsumerWidget {
  /// 是否自建 AppBar：`ImsTabContainer` 里以 tab 正文形式挂载时为 false。
  final bool showAppBar;

  const GraduationRequirementsScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncRequirements = ref.watch(graduationRequirementsProvider);

    final body = FluentPageBackground(
      child: asyncRequirements.when(
        loading: () => const FluentLoading(message: '正在获取毕业学分要求…'),
        error: (error, _) => _ErrorView(
          message: '$error',
          onRetry: () => ref.invalidate(graduationRequirementsProvider),
        ),
        data: (requirements) => _RequirementsView(
          requirements: requirements,
          refreshing: asyncRequirements.isLoading,
          onRefresh: () => ref.invalidate(graduationRequirementsProvider),
        ),
      ),
    );

    if (!showAppBar) return body;

    return Scaffold(
      backgroundColor: FluentColors.bgBase,
      appBar: AppBar(
        backgroundColor: FluentColors.bgBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: FluentColors.textPrimary),
        title: Text(
          '毕业学分要求',
          style: FluentType.subtitle.copyWith(color: FluentColors.textPrimary),
        ),
      ),
      body: body,
    );
  }
}

/// 学分数字展示：数字（默认 14/600）+ 单位「学分」（12/400 次要色），基线对齐。
class _CreditValue extends StatelessWidget {
  const _CreditValue({
    required this.credit,
    this.valueStyle,
    this.valueColor,
    this.unitColor,
  });

  final double credit;
  final TextStyle? valueStyle;
  final Color? valueColor;
  final Color? unitColor;

  @override
  Widget build(BuildContext context) {
    final style = valueStyle ?? FluentType.bodyStrong;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _creditText(credit),
          style: style.copyWith(color: valueColor ?? FluentColors.textPrimary),
        ),
        const SizedBox(width: FluentSpacing.xs),
        Text(
          '学分',
          style: FluentType.caption.copyWith(
            color: unitColor ?? FluentColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// 取数据失败：Fluent InfoBar（错误态）+ 重试按钮。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FluentSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: FluentInfoBar(
            severity: FluentInfoSeverity.error,
            title: '获取毕业学分要求失败',
            message: message,
            action: FluentButton(label: '重试', onPressed: onRetry),
          ),
        ),
      ),
    );
  }
}

/// 主内容：Hero 指标卡 + 明细列表卡。
class _RequirementsView extends StatelessWidget {
  const _RequirementsView({
    required this.requirements,
    required this.refreshing,
    required this.onRefresh,
  });

  final List<GraduationRequirement> requirements;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    if (requirements.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(FluentSpacing.xl),
          child: FluentInfoBar(message: '教务未返回毕业学分要求数据，可稍后重试。'),
        ),
      );
    }

    final items =
        requirements.where((r) => !r.isTotal).toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    final totalRows = requirements.where((r) => r.isTotal).toList();
    // 合计优先用教务给的合计行（口径以教务为准），没有才退回各项求和。
    final total = totalRows.isNotEmpty
        ? totalRows.first.credit
        : items.fold<double>(0, (sum, r) => sum + r.credit);
    final top = items.isEmpty
        ? null
        : items.reduce((a, b) => a.credit >= b.credit ? a : b);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final pagePadding = wide ? FluentSpacing.xl : FluentSpacing.lg;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            pagePadding,
            pagePadding,
            pagePadding,
            FluentSpacing.xxxl,
          ),
          children: [
            FluentMetricCard(
              label: '选修课学分合计',
              value: _creditText(total),
              unit: '学分',
              description: [
                '共 ${items.length} 项要求',
                if (top != null)
                  '最高 ${_creditText(top.credit)} 学分（${top.item}）',
              ].join(' · '),
              trailing: FluentIconButton(
                icon: Icons.refresh,
                tooltip: '刷新',
                onPressed: refreshing ? null : onRefresh,
              ),
              footer: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FluentShareBar(
                    segments: [
                      for (final item in items)
                        FluentShareSegment(
                          weight: item.credit,
                          tooltip:
                              '${item.item} · ${_creditText(item.credit)} 学分',
                        ),
                    ],
                  ),
                  const SizedBox(height: FluentSpacing.sm),
                  Text(
                    '按学分占比（顺序与下表一致）',
                    style: FluentType.caption.copyWith(
                      color: FluentColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.xl),
            const FluentSectionHeader(
              title: '要求明细',
              description: '按教务培养方案顺序排列',
            ),
            FluentCard(
              padding: const EdgeInsets.symmetric(vertical: FluentSpacing.xs),
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const FluentDivider(),
                    FluentListRow(
                      leading: FluentIndexBadge(index: i + 1),
                      title: items[i].item,
                      description: total > 0
                          ? '占 ${(items[i].credit / total * 100).toStringAsFixed(1)}%'
                          : null,
                      trailing: _CreditValue(credit: items[i].credit),
                    ),
                  ],
                  const FluentDivider(),
                  _TotalRow(count: items.length, total: total),
                ],
              ),
            ),
            const SizedBox(height: FluentSpacing.lg),
            Text(
              '数据来自教务系统「毕业学分要求」· 该表为选修学分要求（年级 / 专业列为空时返回通用要求）',
              style: FluentType.caption.copyWith(
                color: FluentColors.textTertiary,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 合计行：accent 8% 淡染底 + accent 字，压在明细卡最下方。
class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.count, required this.total});

  final int count;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FluentSpacing.lg,
        vertical: FluentSpacing.md,
      ),
      decoration: const BoxDecoration(color: FluentColors.accentSubtle),
      child: Row(
        children: [
          Text(
            '合计',
            style: FluentType.bodyStrong.copyWith(color: FluentColors.accent),
          ),
          const Spacer(),
          Text(
            '$count 项',
            style: FluentType.caption.copyWith(
              color: FluentColors.textSecondary,
            ),
          ),
          const SizedBox(width: FluentSpacing.md),
          _CreditValue(
            credit: total,
            valueStyle: FluentType.subtitle,
            valueColor: FluentColors.accent,
            unitColor: FluentColors.accent,
          ),
        ],
      ),
    );
  }
}

/// 学分文本：整数不留小数位，非整数保留必要位数（2.00 → 「2」，1.25 → 「1.25」）。
String _creditText(double value) {
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}
