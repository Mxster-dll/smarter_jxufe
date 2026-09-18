import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/feature_palette.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/network_service/data/providers/network_service_providers.dart';
import 'package:smarter_jxufe/features/network_service/domain/network_service_models.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_actions.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_common.dart';

/// 我的设备：当前在线会话（可强制下线）+ 已绑定设备列表（可解绑）。
///
/// 两个数据源：在线会话 = `dashboard/getOnlineList`（含 sessionId，能下线）；
/// 已绑定设备 = `service/getMacList`（含绑定关系，能解绑）。二者口径不同，
/// 故分两段展示，各带自己的刷新与写操作。
class NetworkDevicesScreen extends ConsumerWidget {
  const NetworkDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('我的设备'),
        centerTitle: false,
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () {
              ref.invalidate(networkOnlineSessionsProvider);
              ref.invalidate(networkDevicesProvider);
            },
            icon: const Icon(Icons.refresh_outlined, size: 20),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(networkOnlineSessionsProvider);
          ref.invalidate(networkDevicesProvider);
          await Future.wait([
            ref.read(networkOnlineSessionsProvider.future),
            ref.read(networkDevicesProvider.future),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: const [
            _OnlineSection(),
            SizedBox(height: 22),
            _BoundDevicesSection(),
          ],
        ),
      ),
    );
  }
}

// ---------- 在线会话 ----------

class _OnlineSection extends ConsumerWidget {
  const _OnlineSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(networkOnlineSessionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        networkSectionTitle(context, '当前在线'),
        const SizedBox(height: 8),
        async.when(
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
                text: '当前没有设备在线。',
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
                    _OnlineTile(session: sessions[i]),
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

class _OnlineTile extends ConsumerWidget {
  const _OnlineTile({required this.session});

  final NetworkOnlineSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    networkBadge(context, '在线', fp(context).networkServiceOk),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'IP ${session.ip}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'MAC ${networkFormatMac(session.mac)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '上线 ${session.loginAtText}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '已用 ${networkFormatSeconds(session.useSeconds)} · '
                  '上行 ${networkFormatBytes(session.upFlow)} · '
                  '下行 ${networkFormatBytes(session.downFlow)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '会话号 ${session.sessionId}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: Key('netsvc_devices_offline_${session.sessionId}'),
            onPressed: () async {
              final ok = await networkConfirm(
                context,
                title: '强制下线',
                message:
                    '确定要断开 ${session.ip}（${session.terminalLabel}）吗？\n'
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
                  ref.invalidate(networkDevicesProvider);
                  ref.invalidate(networkAccountProvider);
                },
              );
            },
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
}

// ---------- 已绑定设备 ----------

class _BoundDevicesSection extends ConsumerWidget {
  const _BoundDevicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(networkDevicesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        networkSectionTitle(context, '已绑定设备'),
        const SizedBox(height: 8),
        async.when(
          loading: () => networkLoadingCard(context, text: '正在读取已绑定设备…'),
          error: (error, _) => networkErrorCard(
            context,
            error,
            onRetry: () => ref.invalidate(networkDevicesProvider),
          ),
          data: (devices) {
            if (devices.isEmpty) {
              return networkEmptyCard(
                context,
                icon: Icons.phonelink_lock_outlined,
                text: '没有已绑定的设备。',
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
                      for (var i = 0; i < devices.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 60,
                            color: scheme.outlineVariant,
                          ),
                        networkRecordTile(
                          context,
                          icon: devices[i].online
                              ? Icons.wifi_outlined
                              : Icons.wifi_off_outlined,
                          title: networkFormatMac(devices[i].mac),
                          subtitle: [
                            devices[i].terminalLabel.isEmpty
                                ? '未知终端'
                                : devices[i].terminalLabel,
                            if (devices[i].lastLoginText.isNotEmpty)
                              '最近登录 ${devices[i].lastLoginText}',
                            if (devices[i].lastLoginIp.isNotEmpty)
                              devices[i].lastLoginIp,
                          ].join(' · '),
                          trailing: null,
                          accent: devices[i].online
                              ? fp(context).networkServiceOk
                              : scheme.onSurfaceVariant,
                          onTap: () => _unbind(context, ref, devices[i]),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '点击设备可解绑（解绑后该设备需要重新认证）。',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _unbind(
    BuildContext context,
    WidgetRef ref,
    NetworkDevice device,
  ) async {
    final ok = await networkConfirm(
      context,
      title: '解绑设备',
      message:
          '确定解绑 ${networkFormatMac(device.mac)} 吗？\n'
          '解绑后该设备需要重新认证才能上网。',
      confirmText: '解绑',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    await runNetworkAction(
      context,
      ref,
      action: (guid) => networkSourceOf(ref).unbindDevice(guid, device.mac),
      successFallback: '已解绑该设备',
      invalidate: () {
        ref.invalidate(networkDevicesProvider);
        ref.invalidate(networkOnlineSessionsProvider);
        ref.invalidate(networkAccountProvider);
      },
    );
  }
}
