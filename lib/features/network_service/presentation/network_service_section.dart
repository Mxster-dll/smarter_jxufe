import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/web/external_url.dart';
import 'package:smarter_jxufe/core/web/in_app_web_screen.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/features/network_service/data/providers/network_service_providers.dart';
import 'package:smarter_jxufe/features/network_service/domain/network_service_models.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_actions.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_common.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_devices_screen.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_profile_screen.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_records_screen.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_services_screen.dart';

/// 校园网页第二段「网络服务」：学校自助服务系统的**真实数据**（用户 2026-09-16 拍板）。
///
/// 段内展示账号概览（余额 / 套餐 / 状态 / 本周期用量 / 有效期）、在线设备（可强制
/// 下线）、近期上网记录，并给账单、充值明细、业务办理记录、资费、账号服务、
/// 个人设置的入口；明细都在子页里。
///
/// 未配置平台 GUID 时给「去配置」（回调交给宿主页面弹它自己的配置框）。
class NetworkServiceSection extends ConsumerWidget {
  const NetworkServiceSection({
    super.key,
    required this.onConfigureGuid,
    this.onRefreshRequested,
  });

  /// 「去配置平台标识」回调（宿主页面已有配置对话框，直接复用）。
  final VoidCallback onConfigureGuid;

  /// 段内刷新时通知宿主（宿主的下拉刷新要连带刷新本段）。
  final VoidCallback? onRefreshRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(networkAccountProvider);

    return accountAsync.when(
      loading: () => networkLoadingCard(context),
      error: (error, _) => networkErrorCard(
        context,
        error,
        onRetry: () => invalidateNetworkService(ref),
        onConfigureGuid: error.toString().contains('GUID')
            ? onConfigureGuid
            : null,
      ),
      data: (account) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AccountCard(account: account),
          const SizedBox(height: 12),
          const _OnlineDevicesCard(),
          const SizedBox(height: 12),
          const _RecentRecordsCard(),
          const SizedBox(height: 12),
          const _EntriesCard(),
        ],
      ),
    );
  }
}

// ---------- 账号概览 ----------

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account});

  final NetworkAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
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
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.tint(context, networkAccent(context), 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.lan_outlined,
                  size: 22,
                  color: networkAccent(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '网络服务',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        networkBadge(context, account.statusLabel, statusColor),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '用户自助服务系统（校园网账号）',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              networkMetric(
                context,
                label: '账户余额',
                value: account.leftMoney.toStringAsFixed(2),
                unit: '元',
                color: networkAccent(context),
                key: const Key('netsvc_balance'),
              ),
              const SizedBox(width: 22),
              networkMetric(
                context,
                label: '本周期时长',
                value: networkFormatMinutes(account.useTime),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextButton.icon(
                  key: const Key('netsvc_refresh'),
                  onPressed: () => invalidateNetworkService(ref),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.refresh_outlined, size: 16),
                  label: const Text('刷新'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 8),
          networkInfoRow(context, label: '套餐', value: account.planName),
          networkInfoRow(
            context,
            label: '计费方式',
            value: [
              account.payStyleLabel,
              if (account.planGroupDesc.isNotEmpty) account.planGroupDesc,
            ].where((e) => e.isNotEmpty).join(' · '),
          ),
          networkInfoRow(
            context,
            label: '本周期流量',
            value: networkFormatFlow(account.useFlow),
          ),
          if (account.planArea.isNotEmpty)
            networkInfoRow(context, label: '适用范围', value: account.planArea),
          networkInfoRow(context, label: '上网账号', value: account.userName),
          _PasswordRow(password: account.password),
        ],
      ),
    );
  }
}

/// 上网密码行（掩码 + 显示/隐藏 + 复制；复制的是真值）。
class _PasswordRow extends StatefulWidget {
  const _PasswordRow({required this.password});

  final String password;

  @override
  State<_PasswordRow> createState() => _PasswordRowState();
}

class _PasswordRowState extends State<_PasswordRow> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPassword = widget.password.isNotEmpty;
    final shown = !hasPassword
        ? '—'
        : (_visible ? widget.password : networkMaskPassword(widget.password));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '上网密码',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              shown,
              key: const Key('netsvc_password'),
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (hasPassword) ...[
            TextButton(
              key: const Key('netsvc_password_toggle'),
              onPressed: () => setState(() => _visible = !_visible),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
              ),
              child: Text(
                _visible ? '隐藏' : '显示',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              key: const Key('netsvc_password_copy'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.password));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(
                      content: Text('上网密码已复制'),
                      duration: Duration(seconds: 2),
                    ),
                  );
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
              ),
              child: const Text('复制', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------- 在线设备 ----------

class _OnlineDevicesCard extends ConsumerWidget {
  const _OnlineDevicesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final sessionsAsync = ref.watch(networkOnlineSessionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        networkSectionTitle(
          context,
          '在线设备',
          trailing: TextButton(
            key: const Key('netsvc_devices_all'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NetworkDevicesScreen(),
              ),
            ),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('全部设备'),
          ),
        ),
        const SizedBox(height: 8),
        sessionsAsync.when(
          loading: () => networkLoadingCard(context, text: '正在读取在线设备…'),
          error: (error, _) => networkErrorCard(
            context,
            error,
            onRetry: () => ref.invalidate(networkOnlineSessionsProvider),
          ),
          data: (sessions) {
            if (sessions.isEmpty) {
              return networkEmptyCard(
                context,
                icon: Icons.devices_other_outlined,
                text:
                    '当前没有在线设备。\n（同一账号最多 '
                    '${ref.watch(networkAccountProvider).valueOrNull?.ipMaxCount ?? 3} 台设备同时在线）',
              );
            }
            return networkCard(
              context,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < sessions.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 60,
                        color: scheme.outlineVariant,
                      ),
                    _SessionTile(session: sessions[i]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});

  final NetworkOnlineSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.tint(context, networkAccent(context), 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              session.terminalLabel.contains('移动')
                  ? Icons.smartphone_outlined
                  : Icons.computer_outlined,
              size: 17,
              color: networkAccent(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      session.terminalLabel.isEmpty
                          ? '未知终端'
                          : session.terminalLabel,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    const SizedBox(width: 6),
                    networkBadge(
                      context,
                      '在线',
                      fp(context).networkServiceOk,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${session.ip} · ${networkFormatMac(session.mac)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '上线 ${session.loginAtText} · 已用 '
                  '${networkFormatSeconds(session.useSeconds)} · 下行 '
                  '${networkFormatBytes(session.downFlow)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: Key('netsvc_offline_${session.sessionId}'),
            onPressed: () => _forceOffline(context, ref),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: scheme.error,
            ),
            child: const Text('下线', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Future<void> _forceOffline(BuildContext context, WidgetRef ref) async {
    final ok = await networkConfirm(
      context,
      title: '强制下线',
      message:
          '确定要断开 ${session.ip}（${session.terminalLabel}）的在线连接吗？\n'
          '该设备会立刻掉线，需要重新认证才能上网。',
      confirmText: '强制下线',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await runNetworkAction(
      context,
      ref,
      action: (guid) =>
          networkSourceOf(ref).forceOffline(guid, session.sessionId),
      successFallback: '已强制下线',
      invalidate: () {
        ref.invalidate(networkOnlineSessionsProvider);
        ref.invalidate(networkLoginHistoryProvider);
      },
    );
  }
}

// ---------- 近期上网记录 ----------

class _RecentRecordsCard extends ConsumerWidget {
  const _RecentRecordsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final historyAsync = ref.watch(networkLoginHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        networkSectionTitle(
          context,
          '近期上网记录',
          trailing: TextButton(
            key: const Key('netsvc_records_all'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NetworkRecordsScreen(
                  initialTab: NetworkRecordsTab.usage,
                ),
              ),
            ),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('全部记录'),
          ),
        ),
        const SizedBox(height: 8),
        historyAsync.when(
          loading: () => networkLoadingCard(context, text: '正在读取上网记录…'),
          error: (error, _) => networkErrorCard(
            context,
            error,
            onRetry: () => ref.invalidate(networkLoginHistoryProvider),
          ),
          data: (records) {
            if (records.isEmpty) {
              return networkEmptyCard(context, text: '暂无上网记录。');
            }
            return networkCard(
              context,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < records.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 60,
                        color: scheme.outlineVariant,
                      ),
                    networkRecordTile(
                      context,
                      icon: records[i].online
                          ? Icons.play_circle_outline
                          : Icons.history_outlined,
                      title: records[i].online
                          ? '${records[i].terminalLabel} · 在线中'
                          : networkFormatDateTime(records[i].loginAt),
                      subtitle:
                          '${records[i].ip} · ${networkFormatMac(records[i].mac)}'
                          '${records[i].online ? '' : ' → ${networkFormatDateTime(records[i].logoutAt)}'}',
                      trailing: networkFormatFlow(records[i].flowMb),
                      trailingNote: networkFormatMinutes(records[i].minutes),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ---------- 明细与业务入口 ----------

class _EntriesCard extends ConsumerWidget {
  const _EntriesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final entries =
        <({IconData icon, String title, String subtitle, Widget screen})>[
          (
            icon: Icons.receipt_long_outlined,
            title: '历史账单',
            subtitle: '按月基本月租 · 时长流量计费 · 用量汇总',
            screen: const NetworkRecordsScreen(
              initialTab: NetworkRecordsTab.bills,
            ),
          ),
          (
            icon: Icons.account_balance_wallet_outlined,
            title: '充值明细',
            subtitle: '交费时间 · 金额 · 受理终端',
            screen: const NetworkRecordsScreen(
              initialTab: NetworkRecordsTab.payments,
            ),
          ),
          (
            icon: Icons.assignment_turned_in_outlined,
            title: '业务办理记录',
            subtitle: '报停 / 复通 / 套餐变更等办理流水',
            screen: const NetworkRecordsScreen(
              initialTab: NetworkRecordsTab.operatorLogs,
            ),
          ),
          (
            icon: Icons.price_change_outlined,
            title: '资费介绍',
            subtitle: '当前可选套餐与价格',
            screen: const NetworkServicesScreen(
              initialTab: NetworkServicesTab.plans,
            ),
          ),
          (
            icon: Icons.tune_outlined,
            title: '账号服务',
            subtitle: '报停 · 复通 · 预约套餐',
            screen: const NetworkServicesScreen(),
          ),
          (
            icon: Icons.manage_accounts_outlined,
            title: '账号设置',
            subtitle: '详细资料 · 修改上网密码',
            screen: const NetworkProfileScreen(),
          ),
        ];
    final account = ref.watch(networkAccountProvider).valueOrNull;

    return networkCard(
      context,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 60, color: scheme.outlineVariant),
            networkRecordTile(
              context,
              icon: entries[i].icon,
              title: entries[i].title,
              subtitle: entries[i].subtitle,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => entries[i].screen),
              ),
            ),
          ],
          if (account != null && account.userName.isNotEmpty) ...[
            Divider(height: 1, indent: 60, color: scheme.outlineVariant),
            networkRecordTile(
              context,
              key: const Key('netsvc_wechat_recharge'),
              icon: Icons.qr_code_2_outlined,
              title: '微信充值',
              subtitle: '跳转学校支付页（上网账号已预填）',
              onTap: () => _openRecharge(context, ref, account.userName),
            ),
          ],
        ],
      ),
    );
  }

  /// 微信充值：学校自助支付页（`self.jxufe.cn/WebPay/recharge`）。
  ///
  /// 与小程序「账户充值 > 微信充值」同款：App 只负责带上账号打开它，支付本身在
  /// 学校页面里完成（App 不接触任何支付凭据）。
  Future<void> _openRecharge(
    BuildContext context,
    WidgetRef ref,
    String account,
  ) async {
    final url =
        'https://self.jxufe.cn/WebPay/recharge?paytype=3'
        '&account=${Uri.encodeComponent(account)}';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (ref.read(inAppWebViewSupportedProvider)) {
      final builder = ref.read(webViewScreenBuilderProvider);
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => builder('微信充值', url)));
      return;
    }
    await ref.read(externalUrlOpenerProvider)(uri);
  }
}
