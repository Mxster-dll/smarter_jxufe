/// 图书馆订阅词云同步 · 设置页「云同步」节。
///
/// 这一节是 Q2「明示 + opt-in + 一键清除」的**唯一落地处**：
/// - 开关首次打开时**逐项列出**会同步的内容（含宿舍房间号 —— Q7-B 的直接要求）；
/// - 常驻状态行回答「它在传什么、传到哪了、云端存的是什么」；
/// - 恢复是两步确认 + 展示可读摘要（不做盲盒覆盖），恢复前自动留档在协议层完成；
/// - 「清除云端数据」按结构全删 + 对账，结果如实回报。
///
/// **关闭开关只停上传、不删云端**（Q13）：想清干净得走「清除云端数据」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_controller.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_prefs.dart';
import 'package:smarter_jxufe/features/library_sync/data/providers/libsp_providers.dart';

/// 开启同步前必须逐项展示的内容清单（**守卫测试会检查它列出了宿舍房间号**）。
const List<String> kLibspSyncDisclosureItems = <String>[
  '外观（深色模式）、校区、主页布局、校历三个开关、入馆教育模式',
  '电费绑定：校区 + 宿舍房间号',
  '分数估计：课程名、课程代码、平时占比、学分、各分项与分值、目标分、期末分、课程备注、截止日期',
  '综测里你自己填写的各项分值',
];

/// 明确不同步的内容（与 [kLibspSyncDisclosureItems] 对称，不许含糊）。
const List<String> kLibspSyncExcludedItems = <String>[
  '登录令牌（教务、畅想之星、数据中台等，换机本就该重新登录）',
  '课程备忘录的文字与图片',
  '可重新获取的缓存（成绩、课表、培养方案、学籍）',
  '设备标识（小程序 GUID）与桌面小组件配置',
];

/// 数据存放形态的说明（用户能在图书馆界面看到并自行删除）。
const String kLibspSyncStorageNote =
    '数据会以「勿删！智慧er江财云同步信息：…」开头的订阅词形式存在图书馆'
    '「我的订阅」里（约 20 条，占你订阅列表的一部分）。你能在图书馆网站看到并删除它们；'
    'App 会在下次同步时把缺的补回。你自己原来的订阅词一条都不会被改动。';

/// 设置页「云同步」卡片。
class LibspSyncCard extends ConsumerWidget {
  const LibspSyncCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsStore = ref.watch(libspSyncPrefsProvider);
    final controller = ref.watch(libspSyncControllerProvider);
    final account = ref.watch(currentAccountProvider);
    final state = prefsStore.state;
    final signedIn = account.trim().isNotEmpty;

    return Card(
      elevation: 0,
      shape: appCardShape(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            value: state.enabled,
            onChanged: controller.busy
                ? null
                : (value) async {
                    if (!signedIn) {
                      _snack(context, '请先在 App 里登录后再开启同步');
                      return;
                    }
                    if (value) {
                      final agreed = await _showDisclosure(context);
                      if (!agreed) return;
                    }
                    await prefsStore.setEnabled(value);
                  },
            title: const Text('同步我的设置与分数估计'),
            subtitle: Text(
              signedIn
                  ? '存到图书馆「我的订阅」，换机或重装后可恢复'
                  : '需要先登录（同步用的是你的统一身份认证账号）',
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusRow(
                  label: '上次同步',
                  value: state.lastUploadedAt == null
                      ? '还没同步过'
                      : _fmtTime(state.lastUploadedAt!),
                ),
                _StatusRow(
                  label: '本机改动',
                  value: controller.dirty ? '待同步（变更后约 1 分钟自动上传）' : '已是最新',
                ),
                if (controller.message != null)
                  _StatusRow(
                    label: controller.status == LibspSyncStatus.failed
                        ? '上次失败'
                        : '上次结果',
                    value: controller.message!,
                    emphasize: controller.status == LibspSyncStatus.failed,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: controller.busy || !signedIn
                      ? null
                      : () async {
                          await controller.syncNow();
                          if (!context.mounted) return;
                          _snack(context, controller.message ?? '已同步');
                        },
                  icon: controller.busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: const Text('立即同步'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.busy || !signedIn
                      ? null
                      : () => _restore(context, controller),
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('从云端恢复'),
                ),
                TextButton.icon(
                  onPressed: controller.busy || !signedIn
                      ? null
                      : () => _clear(context, controller),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清除云端数据'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(
    BuildContext context,
    LibspSyncController controller,
  ) async {
    final summary = await controller.preview();
    if (!context.mounted) return;
    if (summary == null) {
      _snack(context, '云端还没有可恢复的快照，先点「立即同步」');
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cloud_download_outlined),
        title: const Text('从云端恢复？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary.label),
            const SizedBox(height: 12),
            const Text('恢复会覆盖本机的分数估计与这几项偏好。'),
            const SizedBox(height: 8),
            const Text('恢复前会先把本机现状存到云端一份，万一恢复错了还能找回来。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('覆盖本机数据'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    final ok = await controller.restoreFromCloud();
    if (!context.mounted) return;
    _snack(context, ok ? '已从云端恢复' : (controller.message ?? '恢复失败'));
  }

  Future<void> _clear(
    BuildContext context,
    LibspSyncController controller,
  ) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('清除云端的同步数据？'),
        content: const Text(
          '会把 App 写在图书馆「我的订阅」里的全部同步词删掉，并当场对账确认删干净。\n'
          '你自己原来的订阅词不受影响；本机数据也不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    await controller.clearCloud();
    if (!context.mounted) return;
    _snack(context, controller.message ?? '清除完成');
  }

  Future<bool> _showDisclosure(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        icon: const Icon(Icons.cloud_outlined),
        title: const Text('同步会用到图书馆的「我的订阅」'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('会同步这些内容：', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final item in kLibspSyncDisclosureItems)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('· $item'),
              ),
            const SizedBox(height: 12),
            const Text('不会同步：', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final item in kLibspSyncExcludedItems)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('· $item'),
              ),
            const SizedBox(height: 12),
            Text(
              kLibspSyncStorageNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('暂不开启'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('知道了，开启'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _fmtTime(int epochMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: emphasize ? scheme.error : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
