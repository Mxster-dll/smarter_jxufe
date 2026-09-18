import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/network_service/data/providers/network_service_providers.dart';
import 'package:smarter_jxufe/features/network_service/domain/network_service_models.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_common.dart';

/// 账单与记录（网上自助服务系统「账单」页）：上网记录 / 历史账单 / 充值明细 /
/// 业务办理记录 四个分页。
enum NetworkRecordsTab { usage, bills, payments, operatorLogs }

class NetworkRecordsScreen extends ConsumerStatefulWidget {
  const NetworkRecordsScreen({
    super.key,
    this.initialTab = NetworkRecordsTab.usage,
  });

  final NetworkRecordsTab initialTab;

  @override
  ConsumerState<NetworkRecordsScreen> createState() =>
      _NetworkRecordsScreenState();
}

class _NetworkRecordsScreenState extends ConsumerState<NetworkRecordsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: NetworkRecordsTab.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );

  /// 历史账单页选中的年份（服务端按年查询，默认今年）。
  late int _year = DateTime.now().year;

  /// 上网记录页的查询窗口（服务端**必须**带日期范围，默认近一年）。
  late NetworkUsageQuery _usageRange = NetworkUsageQuery.recentYear(
    DateTime.now(),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('账单与记录'),
        centerTitle: false,
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: '上网记录'),
            Tab(text: '历史账单'),
            Tab(text: '充值明细'),
            Tab(text: '业务办理'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_usageTab(), _billsTab(), _paymentsTab(), _operatorTab()],
      ),
    );
  }

  // ---------- 上网记录 ----------

  Widget _usageTab() {
    final async = ref.watch(networkUsageRecordsProvider(_usageRange));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(networkUsageRecordsProvider);
        await ref.read(networkUsageRecordsProvider(_usageRange).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          _rangeRow(),
          const SizedBox(height: 12),
          async.when(
            loading: () => networkLoadingCard(context, text: '正在读取上网记录…'),
            error: (error, _) => networkErrorCard(
              context,
              error,
              onRetry: () => ref.invalidate(networkUsageRecordsProvider),
            ),
            data: (records) {
              if (records.isEmpty) {
                return networkEmptyCard(
                  context,
                  icon: Icons.history_toggle_off_outlined,
                  text:
                      '该时间范围内没有上网记录。\n'
                      '（服务端要求必须指定日期范围，默认近一年）',
                );
              }
              final totalMinutes = records.fold<int>(
                0,
                (sum, r) => sum + r.minutes,
              );
              final totalFlow = records.fold<double>(
                0,
                (sum, r) => sum + r.flowMb,
              );
              final totalCost = records.fold<double>(
                0,
                (sum, r) => sum + r.costMoney,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  networkCard(
                    context,
                    child: Row(
                      children: [
                        networkMetric(
                          context,
                          label: '记录数',
                          value: '${records.length}',
                        ),
                        const SizedBox(width: 20),
                        networkMetric(
                          context,
                          label: '总时长',
                          value: networkFormatMinutes(totalMinutes),
                        ),
                        const SizedBox(width: 20),
                        networkMetric(
                          context,
                          label: '总流量',
                          value: networkFormatFlow(totalFlow),
                        ),
                        const Spacer(),
                        networkMetric(
                          context,
                          label: '计费合计',
                          value: totalCost.toStringAsFixed(2),
                          unit: '元',
                          color: networkAccent(context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  networkCard(
                    context,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < records.length; i++) ...[
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
                            icon: Icons.wifi_tethering_outlined,
                            title: networkFormatDateTime(records[i].loginAt),
                            subtitle:
                                '→ ${networkFormatDateTime(records[i].logoutAt)}\n'
                                '${records[i].userIp} · ${networkFormatMac(records[i].mac)}'
                                '\n国内 ↑${networkFormatFlow(records[i].chinanetUpFlow)} '
                                '↓${networkFormatFlow(records[i].chinanetDownFlow)}'
                                '${records[i].costMoney > 0 ? ' · 计费 ${records[i].costMoney.toStringAsFixed(2)} 元' : ''}',
                            trailing: networkFormatFlow(records[i].flowMb),
                            trailingNote: networkFormatMinutes(
                              records[i].minutes,
                            ),
                          ),
                        ],
                      ],
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

  Widget _rangeRow() {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final presets = <(String, NetworkUsageQuery)>[
      ('近一年', NetworkUsageQuery.recentYear(now)),
      ('今年', NetworkUsageQuery.yearOf(now.year)),
      ('去年', NetworkUsageQuery.yearOf(now.year - 1)),
    ];
    return Row(
      children: [
        Icon(
          Icons.date_range_outlined,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          '${networkFormatDate(_usageRange.from)} ~ ${networkFormatDate(_usageRange.to)}',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        for (final preset in presets)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(
              label: Text(preset.$1, style: const TextStyle(fontSize: 12)),
              selected: _usageRange == preset.$2,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => setState(() => _usageRange = preset.$2),
            ),
          ),
      ],
    );
  }

  // ---------- 历史账单 ----------

  Widget _billsTab() {
    final async = ref.watch(networkMonthBillsProvider(_year));
    final years = [for (var i = 0; i < 6; i++) DateTime.now().year - i];
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(networkMonthBillsProvider);
        await ref.read(networkMonthBillsProvider(_year).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '账单年份',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              for (final year in years.take(4))
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text('$year', style: const TextStyle(fontSize: 12)),
                    selected: _year == year,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _year = year),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          async.when(
            loading: () => networkLoadingCard(context, text: '正在读取历史账单…'),
            error: (error, _) => networkErrorCard(
              context,
              error,
              onRetry: () => ref.invalidate(networkMonthBillsProvider),
            ),
            data: (bills) {
              if (bills.items.isEmpty) {
                return networkEmptyCard(
                  context,
                  icon: Icons.receipt_long_outlined,
                  text: '$_year 年没有出账记录。',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  networkCard(
                    context,
                    child: Row(
                      children: [
                        networkMetric(
                          context,
                          label: '基本月租',
                          value: bills.summary.baseMoney.toStringAsFixed(2),
                          unit: '元',
                          color: networkAccent(context),
                        ),
                        const SizedBox(width: 20),
                        networkMetric(
                          context,
                          label: '时长/流量计费',
                          value: bills.summary.usageMoney.toStringAsFixed(2),
                          unit: '元',
                        ),
                        const Spacer(),
                        networkMetric(
                          context,
                          label: '$_year 年合计',
                          value: bills.summary.total.toStringAsFixed(2),
                          unit: '元',
                          key: const Key('netsvc_bill_total'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '用量合计：${networkFormatMinutes(bills.summary.minutes)} · '
                    '${networkFormatFlow(bills.summary.flowMb)} · 共 ${bills.items.length} 期',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  networkCard(
                    context,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < bills.items.length; i++) ...[
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
                            icon: Icons.description_outlined,
                            title:
                                '${networkFormatDate(bills.items[i].startAt)} ~ '
                                '${networkFormatDate(bills.items[i].endDay)}',
                            subtitle:
                                '${_planLabel(bills.items[i].planName)}'
                                '${bills.items[i].minutes > 0 || bills.items[i].flowMb > 0 ? '\n用量 ${networkFormatMinutes(bills.items[i].minutes)} · ${networkFormatFlow(bills.items[i].flowMb)}' : ''}'
                                '${bills.items[i].billedAt != null ? '\n出账 ${networkFormatDate(bills.items[i].billedAt)}' : ''}',
                            trailing:
                                '${bills.items[i].total.toStringAsFixed(2)} 元',
                          ),
                        ],
                      ],
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

  /// 套餐名在账单里形如 `GPON学生12.5/月|fid=scholar_deny|` → 取 `|` 前一段。
  String _planLabel(String raw) {
    final index = raw.indexOf('|');
    return index > 0 ? raw.substring(0, index) : raw;
  }

  // ---------- 充值明细 ----------

  Widget _paymentsTab() {
    final async = ref.watch(networkPaymentsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(networkPaymentsProvider);
        await ref.read(networkPaymentsProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          async.when(
            loading: () => networkLoadingCard(context, text: '正在读取充值明细…'),
            error: (error, _) => networkErrorCard(
              context,
              error,
              onRetry: () => ref.invalidate(networkPaymentsProvider),
            ),
            data: (payments) {
              if (payments.isEmpty) {
                return networkEmptyCard(
                  context,
                  icon: Icons.account_balance_wallet_outlined,
                  text:
                      '暂无充值记录。\n'
                      '（自助服务系统的交费明细；通过小程序充值后这里会出现记录）',
                );
              }
              final total = payments.fold<double>(
                0,
                (sum, p) => sum + p.amount,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  networkCard(
                    context,
                    child: networkMetric(
                      context,
                      label: '充值合计',
                      value: total.toStringAsFixed(2),
                      unit: '元',
                      color: networkAccent(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  networkCard(
                    context,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < payments.length; i++) ...[
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
                            icon: Icons.add_card_outlined,
                            title: payments[i].kind.isEmpty
                                ? '校园网充值'
                                : payments[i].kind,
                            subtitle: [
                              payments[i].paidAtText,
                              if (payments[i].terminal.isNotEmpty)
                                '受理终端 ${payments[i].terminal}',
                              if (payments[i].memo.isNotEmpty) payments[i].memo,
                            ].join(' · '),
                            trailing:
                                '+${payments[i].amount.toStringAsFixed(2)} 元',
                          ),
                        ],
                      ],
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

  // ---------- 业务办理记录 ----------

  Widget _operatorTab() {
    final async = ref.watch(networkOperatorLogsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(networkOperatorLogsProvider);
        await ref.read(networkOperatorLogsProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          async.when(
            loading: () => networkLoadingCard(context, text: '正在读取业务办理记录…'),
            error: (error, _) => networkErrorCard(
              context,
              error,
              onRetry: () => ref.invalidate(networkOperatorLogsProvider),
            ),
            data: (logs) {
              if (logs.isEmpty) {
                return networkEmptyCard(
                  context,
                  icon: Icons.assignment_turned_in_outlined,
                  text: '暂无业务办理记录。',
                );
              }
              return networkCard(
                context,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < logs.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 60,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      networkRecordTile(
                        context,
                        icon: Icons.assignment_outlined,
                        title: logs[i].description.isEmpty
                            ? '业务办理'
                            : logs[i].description,
                        subtitle: [
                          logs[i].operatedAtText,
                          if (logs[i].terminal.isNotEmpty)
                            '受理终端 ${logs[i].terminal}',
                          if (logs[i].memo.isNotEmpty) logs[i].memo,
                        ].join(' · '),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
