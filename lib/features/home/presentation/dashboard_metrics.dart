/// 首页仪表盘「指标卡区」零件（2026-09-20 从 `dashboard_panel.dart` 外提 · 架构审查 ⑥）。
///
/// 原 `DashboardPanel._buildMetrics` 簇（左栏 4 张指标卡 + 4 个胶囊 + 空/错误态 + `_MetricCard`）。
/// **自身 `ref.watch` 取数**（不接 AsyncValue 参数）；布局常量与 `metricsLayout` 留在
/// `dashboard_panel.dart` 的 `DashboardPanel` 上（测试有 22 处运行时引用 + 10 条源码断言钉着），
/// 故本文件 import 它（Dart 允许互相 import）。
library;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_card.dart';

import 'package:smarter_jxufe/design/app_theme.dart';

import 'package:smarter_jxufe/design/feature_palette.dart';

import 'package:smarter_jxufe/features/comprehensive_service/domain/volunteer_hours_stats.dart';

import 'package:smarter_jxufe/features/comprehensive_service/presentation/volunteer_hours_screen.dart';

import 'package:smarter_jxufe/features/electricity/data/models/electricity_models.dart';

import 'package:smarter_jxufe/features/electricity/presentation/electricity_screen.dart';

import 'package:smarter_jxufe/features/home/data/providers/dashboard_providers.dart';

import 'package:smarter_jxufe/features/home/domain/grade_rank_badge.dart';

import 'package:smarter_jxufe/features/ims/grades/data/providers/weighted_grade_repository_provider.dart';

import 'package:smarter_jxufe/features/ims/grades/domain/weighted_grade.dart';

import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';

import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';

import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';

import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';

import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_screen.dart';

import 'package:smarter_jxufe/features/network_service/data/providers/network_service_providers.dart';

import 'package:smarter_jxufe/features/network_service/domain/network_service_format.dart';

import 'package:smarter_jxufe/features/network_service/domain/network_service_models.dart';

import 'package:smarter_jxufe/features/home/presentation/dashboard_common.dart';
import 'package:smarter_jxufe/features/home/presentation/dashboard_panel.dart';

Widget dashboardMetrics(BuildContext context, WidgetRef ref) {
  final scheme = Theme.of(context).colorScheme;
  final f = fp(context);
  final electricityAsync = ref.watch(dashboardElectricityProvider);
  final volunteerAsync = ref.watch(dashboardVolunteerHoursProvider);
  final gradeAsync = ref.watch(weightedGradeRankingProvider(1));
  final netFeeAsync = ref.watch(netFeeSummaryProvider);
  final networkAsync = ref.watch(networkAccountProvider);

    return LayoutBuilder(
      key: const Key('dashMetrics'),
      builder: (context, constraints) {
        // 列数公式与 [metricsLayout] 同一套（今日课程卡要用它算等高）。
        const gap = DashboardPanel.dashboardMetricGap;
        final cols = DashboardPanel.metricsLayout(constraints.maxWidth).cols;
        final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: width,
              height: DashboardPanel.dashboardMetricCardHeight,
              child: _MetricCard(
                icon: Icons.electrical_services,
                color: f.electricity,
                label: '电费余额',
                onTap: () => dashboardPush(context, const ElectricityScreen()),
                child: _valueArea<ElectricityBalance?>(
                  scheme,
                  electricityAsync,
                  valueOf: (b) => b?.balance ?? '--',
                  unitOf: (b) => b?.unit ?? '',
                  emptyText: '未绑定宿舍',
                  valueKey: const Key('dash_electricity'),
                ),
              ),
            ),
            SizedBox(
              width: width,
              height: DashboardPanel.dashboardMetricCardHeight,
              child: _MetricCard(
                icon: Icons.wifi_outlined,
                color: f.netFee,
                label: '校园网',
                onTap: () => dashboardPush(context, const NetFeeScreen()),
                // 本周期已用流量塞右上角胶囊（用户 2026-09-19：「首页校园网卡片
                // 右上角显示当前使用流量数」），与排名 / 本学年胶囊同位置。
                trailing: _networkTrafficCapsule(context, networkAsync),
                child: _valueArea<NetFeeSummary>(
                  scheme,
                  netFeeAsync,
                  valueOf: (s) =>
                      s.balance == null ? '--' : fmtYuan(s.balance!),
                  unitOf: (s) => s.balance == null ? '' : '元',
                  emptyText: '暂无数据',
                  valueKey: const Key('dash_netfee'),
                ),
              ),
            ),
            SizedBox(
              width: width,
              height: DashboardPanel.dashboardMetricCardHeight,
              child: _MetricCard(
                icon: Icons.auto_graph_outlined,
                color: f.grade,
                label: '课程加权',
                onTap: () => dashboardPush(
                  context,
                  ImsSplashScreen(initialTab: ImsTab.grade),
                ),
                // 排名不占卡片高度：塞右上角一枚胶囊（班级/专业/年级）。
                trailing: gradeAsync.valueOrNull == null
                    ? null
                    : _gradeRankCapsule(context, gradeAsync.valueOrNull!),
                child: _buildGradeContent(scheme, gradeAsync),
              ),
            ),
            SizedBox(
              width: width,
              height: DashboardPanel.dashboardMetricCardHeight,
              child: _MetricCard(
                icon: Icons.volunteer_activism,
                color: f.volunteer,
                label: '志愿时长',
                onTap: () => dashboardPush(context, const VolunteerHoursScreen()),
                // 本学年时长塞右上角胶囊（与排名胶囊同位置，不占卡片高度）。
                trailing: _volunteerYearCapsule(context, volunteerAsync),
                child: _valueArea<VolunteerHoursStats>(
                  scheme,
                  volunteerAsync,
                  valueOf: (s) => _trimHours(s.total),
                  unitOf: (_) => 'h',
                  emptyText: '0 h',
                  valueKey: const Key('dash_volunteer'),
                ),
              ),
            ),
          ],
        );
      },
    );
}

  Widget _buildGradeContent(
    ColorScheme scheme,
    AsyncValue<WeightedGrade?> async,
  ) {
    return async.when(
      loading: () => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) =>
          dashboardInlineStatus(scheme, Icons.error_outline, '获取失败，点右上角刷新'),
      data: (grade) {
        if (grade == null) {
          return dashboardInlineStatus(scheme, Icons.link_off, '暂无成绩');
        }
        return Column(
          key: const Key('dash_grade'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [_fittedValueRow(scheme, value: grade.grade, unit: '分')],
        );
      },
    );
}

  Widget _gradeRankCapsule(BuildContext context, WeightedGrade grade) {
    final accent = appCardAccent(context);
    return Tooltip(
      message: gradeRankTooltip(
        classRank: grade.classRank,
        majorRank: grade.majorRank,
        gradeRank: grade.gradeRank,
      ),
      child: Container(
        key: const Key('dash_grade_rank'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: appCardAccentSoft(context),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          gradeRankBadge(
            classRank: grade.classRank,
            majorRank: grade.majorRank,
            gradeRank: grade.gradeRank,
          ),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
}

  Widget _volunteerYearCapsule(
    BuildContext context,
    AsyncValue<VolunteerHoursStats> async,
  ) {
    final stats = async.valueOrNull;
    if (stats == null) return const SizedBox.shrink();
    final f = fp(context);
    final text = stats.yearKnown
        ? '本学年 ${_trimHours(stats.currentYear)}h'
        : '本学年 —';
    final message = stats.yearKnown
        ? '${stats.yearLabel}志愿时长 ${_trimHours(stats.currentYear)} 小时'
              '${stats.previousYear > 0 ? ' · 上一学年 ${_trimHours(stats.previousYear)} 小时' : ''}'
        : '活动日期获取失败，无法判定本学年志愿时长';
    return Tooltip(
      message: message,
      child: Container(
        key: const Key('dash_volunteer_year'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.tint(context, f.volunteer, 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: f.volunteer,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
}

  Widget _networkTrafficCapsule(
    BuildContext context,
    AsyncValue<NetworkAccount> async,
  ) {
    final account = async.valueOrNull;
    if (account == null) return const SizedBox.shrink();
    final f = fp(context);
    final message = StringBuffer('本计费周期已用流量')
      ..write(account.planName.isEmpty ? '' : ' · 套餐 ${account.planName}')
      ..write(
        account.useTime > 0
            ? ' · 已用 ${networkFormatMinutes(account.useTime)}'
            : '',
      );
    return Tooltip(
      message: message.toString(),
      child: Container(
        key: const Key('dash_netflow'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.tint(context, f.netFee, 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          // 只留流量数字（用户 2026-09-19：「校园网卡片右上角不要显示
          // "已用"二字」）；「本计费周期已用流量」的口径说明在 tooltip 里。
          networkFormatFlow(account.useFlow),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: f.netFee,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
}

  Widget _fittedValueRow(
    ColorScheme scheme, {
    required String value,
    required String unit,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            unit,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
}

  Widget _valueArea<T>(
    ColorScheme scheme,
    AsyncValue<T> async, {
    required String Function(T data) valueOf,
    required String Function(T data) unitOf,
    required String emptyText,
    required Key valueKey,
  }) {
    return async.when(
      loading: () => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, _) =>
          dashboardInlineStatus(scheme, Icons.error_outline, '获取失败，点右上角刷新'),
      data: (data) {
        if (data == null) {
          return dashboardInlineStatus(scheme, Icons.link_off, emptyText);
        }
        return FittedBox(
          key: valueKey,
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                valueOf(data),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unitOf(data),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
}

  String _trimHours(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget child;

  const _MetricCard({
    required this.icon,
    required this.color,
    required this.label,
    this.onTap,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardTheme.color,
      shape: appCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: color.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.tint(context, color, 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    trailing!,
                  ],
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
