import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/network_service/data/providers/network_service_providers.dart';
import 'package:smarter_jxufe/features/network_service/domain/network_service_models.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_actions.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_common.dart';

/// 账号服务分页：账号服务 / 资费介绍 / 办理记录。
enum NetworkServicesTab { services, plans, logs }

/// 账号服务（自助服务系统「服务」页）：账号报停 / 账号复通 / 预约套餐 /
/// 我的设备（跳设备页）/ 资费介绍 / 绑定运营商账号。
///
/// 写操作一律「二次确认 → 提交 → 写后对账刷新」；与小程序一致地给出
/// 「立即」与「预约」两种口径。
class NetworkServicesScreen extends ConsumerStatefulWidget {
  const NetworkServicesScreen({
    super.key,
    this.initialTab = NetworkServicesTab.services,
  });

  final NetworkServicesTab initialTab;

  @override
  ConsumerState<NetworkServicesScreen> createState() =>
      _NetworkServicesScreenState();
}

class _NetworkServicesScreenState extends ConsumerState<NetworkServicesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: NetworkServicesTab.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _refreshAll() {
    ref.invalidate(networkAccountProvider);
    ref.invalidate(networkPlansProvider);
    ref.invalidate(networkStopLogsProvider);
    ref.invalidate(networkReopenLogsProvider);
    ref.invalidate(networkPackageLogsProvider);
    ref.invalidate(networkPackageOptionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('账号服务'),
        centerTitle: false,
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_outlined, size: 20),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '账号服务'),
            Tab(text: '资费介绍'),
            Tab(text: '办理记录'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_servicesTab(), _plansTab(), _logsTab()],
      ),
    );
  }

  // ---------- 账号服务 ----------

  Widget _servicesTab() {
    final accountAsync = ref.watch(networkAccountProvider);
    return RefreshIndicator(
      onRefresh: () async {
        _refreshAll();
        await ref.read(networkAccountProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          accountAsync.when(
            loading: () => networkLoadingCard(context),
            error: (error, _) => networkErrorCard(
              context,
              error,
              onRetry: () => ref.invalidate(networkAccountProvider),
            ),
            data: (account) {
              final statusColor = account.active
                  ? fp(context).networkServiceOk
                  : fp(context).networkServiceStop;
              return networkCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '账号状态',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        networkBadge(context, account.statusLabel, statusColor),
                        const Spacer(),
                        Text(
                          '余额 ${account.leftMoney.toStringAsFixed(2)} 元',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: networkAccent(context),
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    networkInfoRow(
                      context,
                      label: '当前套餐',
                      value: account.planName,
                    ),
                    networkInfoRow(
                      context,
                      label: '计费方式',
                      value: account.payStyleLabel,
                    ),
                    if (account.expireAt != null)
                      networkInfoRow(
                        context,
                        label: '失效日期',
                        value: networkFormatDate(account.expireAt),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          networkCard(
            context,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                networkRecordTile(
                  context,
                  icon: Icons.pause_circle_outline,
                  title: '账号报停',
                  subtitle: '报停后状态变为「停机」，无法上网且系统停止计费',
                  trailing: '办理',
                  onTap: () => _stopDialog(),
                ),
                Divider(
                  height: 1,
                  indent: 60,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                networkRecordTile(
                  context,
                  icon: Icons.play_circle_outline,
                  title: '账号复通',
                  subtitle: '停机状态下可复通；余额不足会失败',
                  trailing: '办理',
                  onTap: () => _reopenDialog(),
                ),
                Divider(
                  height: 1,
                  indent: 60,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                networkRecordTile(
                  context,
                  icon: Icons.swap_horiz_outlined,
                  title: '预约套餐',
                  subtitle: '本计费周期结束后自动更换为新套餐',
                  trailing: '办理',
                  onTap: () => _packageDialog(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          networkCard(
            context,
            padding: EdgeInsets.zero,
            child: networkRecordTile(
              context,
              icon: Icons.hub_outlined,
              title: '绑定运营商账号',
              subtitle: '学校未启用运营商对接功能，暂不可用',
              accent: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 资费介绍 ----------

  Widget _plansTab() {
    final async = ref.watch(networkPlansProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(networkPlansProvider);
        await ref.read(networkPlansProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          async.when(
            loading: () => networkLoadingCard(context, text: '正在读取资费…'),
            error: (error, _) => networkErrorCard(
              context,
              error,
              onRetry: () => ref.invalidate(networkPlansProvider),
            ),
            data: (plans) {
              if (plans.isEmpty) {
                return networkEmptyCard(
                  context,
                  icon: Icons.price_change_outlined,
                  text: '暂无可选资费。',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  networkCard(
                    context,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < plans.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 60,
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          networkRecordTile(
                            context,
                            icon: Icons.local_offer_outlined,
                            title: plans[i].name,
                            subtitle: plans[i].description,
                            trailing: plans[i].id.isEmpty
                                ? null
                                : '资费 ${plans[i].id}',
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '资费由学校统一配置；更换套餐用上面的「预约套餐」。',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------- 办理记录 ----------

  Widget _logsTab() {
    final stops = ref.watch(networkStopLogsProvider);
    final reopens = ref.watch(networkReopenLogsProvider);
    final packages = ref.watch(networkPackageLogsProvider);
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(networkStopLogsProvider);
        ref.invalidate(networkReopenLogsProvider);
        ref.invalidate(networkPackageLogsProvider);
        await ref.read(networkStopLogsProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          networkSectionTitle(context, '报停记录'),
          const SizedBox(height: 8),
          stops.when(
            loading: () => networkLoadingCard(context, text: '正在读取报停记录…'),
            error: (error, _) => networkErrorCard(
              context,
              error,
              onRetry: () => ref.invalidate(networkStopLogsProvider),
            ),
            data: (logs) => logs.isEmpty
                ? networkEmptyCard(context, text: '暂无报停记录。')
                : networkCard(
                    context,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < logs.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 60,
                              color: scheme.outlineVariant,
                            ),
                          networkRecordTile(
                            context,
                            icon: Icons.pause_circle_outline,
                            title: networkFormatDateTime(logs[i].operatedAt),
                            subtitle: logs[i].memo,
                            accent: fp(context).networkServiceStop,
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 22),
          networkSectionTitle(context, '复通记录'),
          const SizedBox(height: 8),
          reopens.when(
            loading: () => networkLoadingCard(context, text: '正在读取复通记录…'),
            error: (error, _) => networkErrorCard(
              context,
              error,
              onRetry: () => ref.invalidate(networkReopenLogsProvider),
            ),
            data: (logs) => logs.isEmpty
                ? networkEmptyCard(context, text: '暂无复通记录。')
                : networkCard(
                    context,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < logs.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 60,
                              color: scheme.outlineVariant,
                            ),
                          networkRecordTile(
                            context,
                            icon: Icons.play_circle_outline,
                            title: networkFormatDateTime(logs[i].operatedAt),
                            subtitle: logs[i].description,
                            accent: fp(context).networkServiceOk,
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 22),
          networkSectionTitle(context, '套餐变更记录'),
          const SizedBox(height: 8),
          packages.when(
            loading: () => networkLoadingCard(context, text: '正在读取套餐记录…'),
            error: (error, _) => networkErrorCard(
              context,
              error,
              onRetry: () => ref.invalidate(networkPackageLogsProvider),
            ),
            data: (logs) => logs.isEmpty
                ? networkEmptyCard(context, text: '暂无套餐变更记录。')
                : networkCard(
                    context,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < logs.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 60,
                              color: scheme.outlineVariant,
                            ),
                          networkRecordTile(
                            context,
                            icon: Icons.swap_horiz_outlined,
                            title: '${logs[i].fromPlan} → ${logs[i].toPlan}',
                            subtitle: [
                              if (logs[i].changedAt != null)
                                '操作 ${networkFormatDateTime(logs[i].changedAt)}',
                              if (logs[i].effectiveAt != null)
                                '生效 ${networkFormatDateTime(logs[i].effectiveAt)}',
                              if (logs[i].state.isNotEmpty) logs[i].state,
                              if (logs[i].memo.isNotEmpty) logs[i].memo,
                            ].join(' · '),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ---------- 写操作 ----------

  Future<void> _stopDialog() async {
    final choice = await showDialog<_StopChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.pause_circle_outline),
        title: const Text('账号报停'),
        content: const Text(
          '停机后将无法继续使用网络，且系统停止计费。\n\n'
          '· 立即报停：提交后马上停机；\n'
          '· 预约报停：本计费周期结束后自动停机。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_StopChoice.scheduled),
            child: const Text('预约报停'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_StopChoice.now),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.errorFill(context),
              foregroundColor: AppColors.onErrorFill(context),
            ),
            child: const Text('立即报停'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await runNetworkAction(
      context,
      ref,
      action: (guid) => networkSourceOf(
        ref,
      ).stopAccount(guid, immediate: choice == _StopChoice.now),
      successFallback: choice == _StopChoice.now ? '已提交立即报停' : '已提交预约报停',
      invalidate: _refreshAll,
    );
  }

  Future<void> _reopenDialog() async {
    final choice = await showDialog<_ReopenChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.play_circle_outline),
        title: const Text('账号复通'),
        content: const Text(
          '复通成功后即可继续使用网络并继续计费；余额不足时复通会失败。\n\n'
          '· 立即复通：提交后马上恢复；\n'
          '· 预约复通：选择未来某一天自动复通。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_ReopenChoice.scheduled),
            child: const Text('预约复通'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_ReopenChoice.now),
            child: const Text('立即复通'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    // 预约复通必须带日期（服务端要求，且只能是明天及以后）。
    DateTime? date;
    if (choice == _ReopenChoice.scheduled) {
      date = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 1)),
        firstDate: DateTime.now().add(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 90)),
        helpText: '选择预约复通日期',
      );
      if (date == null || !mounted) return;
    }

    await runNetworkAction(
      context,
      ref,
      action: (guid) => networkSourceOf(
        ref,
      ).reopenAccount(guid, immediate: choice == _ReopenChoice.now, date: date),
      successFallback: choice == _ReopenChoice.now ? '已提交立即复通' : '已提交预约复通',
      invalidate: _refreshAll,
    );
  }

  Future<void> _packageDialog() async {
    final NetworkPackageOptions options;
    try {
      options = await ref.read(networkPackageOptionsProvider.future);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      return;
    }
    if (!mounted || options.options.isEmpty) return;

    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.swap_horiz_outlined),
        title: const Text('预约套餐'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '办理预约套餐后，系统将在本计费周期结束后自动为您更换为新套餐。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 12),
            for (final plan in options.options)
              ListTile(
                key: Key('netsvc_package_${plan.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(plan.name, style: const TextStyle(fontSize: 13.5)),
                subtitle: plan.description.isEmpty
                    ? null
                    : Text(
                        plan.description,
                        style: const TextStyle(fontSize: 11.5, height: 1.4),
                      ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => Navigator.of(dialogContext).pop(plan.id),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await runNetworkAction(
      context,
      ref,
      action: (guid) => networkSourceOf(ref).reservePackage(guid, picked),
      successFallback: '已提交预约套餐',
      invalidate: _refreshAll,
    );
  }
}

enum _StopChoice { now, scheduled }

enum _ReopenChoice { now, scheduled }
