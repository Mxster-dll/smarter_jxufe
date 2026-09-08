import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';

/// 网费：校园网余额 + 充值记录。
///
/// 双源兜底（用户拍板）：已配置平台 GUID → 小程序实时计费源
/// （余额 + 近一年充值记录）；未配置 → 门户个人数据中心概览源（仅余额）。
class NetFeeScreen extends ConsumerStatefulWidget {
  const NetFeeScreen({super.key});

  @override
  ConsumerState<NetFeeScreen> createState() => _NetFeeScreenState();
}

class _NetFeeScreenState extends ConsumerState<NetFeeScreen> {
  Future<void> _refresh() async {
    ref.invalidate(netFeeSummaryProvider);
    await ref.read(netFeeSummaryProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summaryAsync = ref.watch(netFeeSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('网费'),
        centerTitle: false,
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          children: [
            ...summaryAsync.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ],
              error: (e, _) => [
                _errorCard(
                  scheme,
                  Icons.error_outline,
                  '加载失败：${e.toString().replaceAll('Exception: ', '')}',
                ),
              ],
              data: (summary) => [
                _buildSourceRow(context, scheme, summary),
                const SizedBox(height: 12),
                _buildBalanceCard(context, scheme, summary),
                if (summary.hasGuid && summary.liveError != null) ...[
                  const SizedBox(height: 12),
                  _errorCard(
                    scheme,
                    Icons.cloud_off_outlined,
                    '实时计费源不可用（${summary.liveError}），已自动回退门户概览余额。',
                    light: true,
                  ),
                ],
                if (!summary.hasGuid) ...[
                  const SizedBox(height: 12),
                  _buildGuidHint(context, scheme),
                ],
                if (summary.records.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _sectionTitle(context, '充值记录'),
                  const SizedBox(height: 10),
                  _buildRecordsCard(context, scheme, summary.records),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 顶部：来源 + 配置入口 ----------

  Widget _buildSourceRow(
    BuildContext context,
    ColorScheme scheme,
    NetFeeSummary summary,
  ) {
    final live = summary.source == NetFeeSource.wxLive;
    return Row(
      children: [
        Icon(
          live ? Icons.cloud_done_outlined : Icons.storage_outlined,
          size: 16,
          color: live ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          summary.source == NetFeeSource.none
              ? '暂无可用数据源'
              : '当前数据源：${summary.source.label}${summary.hasGuid ? '' : '（免配置）'}',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () => _showGuidDialog(context),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          icon: Icon(
            summary.hasGuid ? Icons.settings_outlined : Icons.add_link_outlined,
            size: 16,
          ),
          label: Text(summary.hasGuid ? '实时源配置' : '启用实时源'),
        ),
      ],
    );
  }

  // ---------- 余额大卡 ----------

  Widget _buildBalanceCard(
    BuildContext context,
    ColorScheme scheme,
    NetFeeSummary summary,
  ) {
    return _whiteCard(context, child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.wifi_outlined,
                    size: 22, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '账户余额',
                      style: TextStyle(
                        fontSize: 13.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.source == NetFeeSource.wxLive
                          ? '实时校园网计费源'
                          : summary.source == NetFeeSource.portal
                              ? '门户概览口径（非实时）'
                              : '',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (summary.balance == null)
            Text(
              '暂无可用余额数据',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  fmtYuan(summary.balance!),
                  key: const Key('netfee_balance'),
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    color: scheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '元',
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.badge_outlined,
                  size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '账号 ${summary.username ?? ''}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    ));
  }

  // ---------- 未配置 GUID 提示 ----------

  Widget _buildGuidHint(BuildContext context, ColorScheme scheme) {
    return _whiteCard(
      context,
      color: scheme.primary.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '未配置微信平台标识，当前余额来自门户个人数据中心（非实时计费）。\n'
                '点击右上「启用实时源」填写平台标识后，可获取实时余额与充值记录。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 充值记录 ----------

  Widget _buildRecordsCard(
    BuildContext context,
    ColorScheme scheme,
    List<NetFeeRecord> records,
  ) {
    return _whiteCard(
      context,
      child: Column(
        children: [
          for (var i = 0; i < records.length; i++) ...[
            if (i > 0)
              Divider(height: 1, indent: 62, color: scheme.outlineVariant),
            _buildRecordRow(context, scheme, records[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordRow(
    BuildContext context,
    ColorScheme scheme,
    NetFeeRecord record,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.add_card_outlined,
                size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recordTitle(record),
                  style: const TextStyle(fontSize: 13.5),
                ),
                const SizedBox(height: 3),
                Text(
                  _fmtTime(record.paidAt),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '+${fmtYuan(record.payMoney)} 元',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  String _recordTitle(NetFeeRecord record) {
    final type = record.feeType.isNotEmpty ? record.feeType : record.businessType;
    if (type.contains('储值') || type.contains('充值')) return '网费充值';
    return type.isEmpty ? '网费记录' : type;
  }

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  // ---------- GUID 配置对话框 ----------

  Future<void> _showGuidDialog(BuildContext context) async {
    if (!mounted) return;
    final box = await ref.read(netFeePlatformBoxProvider.future);
    if (!mounted) return;
    final existing = box.get('guid') ?? '';
    final controller = TextEditingController(text: existing);
    final scheme = Theme.of(context).colorScheme;

    final action = await showDialog<_GuidAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('实时数据源配置'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '填写微信智慧江财平台的用户标识（GUID），即换取实时接口所需的访问凭证。'
                '它与校历页共用同一配置，填写一次两处均生效。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: false,
                decoration: const InputDecoration(
                  labelText: '平台 GUID',
                  hintText: '例如 00000000-0000-4000-8000-000000000000',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (existing.isNotEmpty)
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(const _GuidActionClear()),
              child: const Text('清除'),
            ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(const _GuidActionCancel()),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext)
                .pop(_GuidActionSave(controller.text.trim())),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (action == null || action is _GuidActionCancel) return;
    if (action is _GuidActionClear) {
      await box.delete('guid');
    } else if (action is _GuidActionSave) {
      if (action.guid.isEmpty) {
        await box.delete('guid');
      } else {
        await box.put('guid', action.guid);
      }
    }
    ref.invalidate(netFeeGuidProvider);
    ref.invalidate(netFeeSummaryProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action is _GuidActionClear
                ? '已清除平台标识，将使用门户概览源'
                : action is _GuidActionSave && action.guid.isNotEmpty
                    ? '已保存平台标识，正在刷新实时数据'
                    : '已清除平台标识',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ---------- 通用小块 ----------

  Widget _sectionTitle(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _whiteCard(
    BuildContext context, {
    required Widget child,
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color ?? Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _errorCard(
    ColorScheme scheme,
    IconData icon,
    String message, {
    bool light = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: light
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : scheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: light
              ? scheme.outlineVariant
              : scheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: light ? scheme.onSurfaceVariant : scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: light ? scheme.onSurfaceVariant : scheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- GUID 对话框动作 ----------

sealed class _GuidAction {
  const _GuidAction();
}

class _GuidActionCancel extends _GuidAction {
  const _GuidActionCancel();
}

class _GuidActionSave extends _GuidAction {
  final String guid;
  const _GuidActionSave(this.guid);
}

class _GuidActionClear extends _GuidAction {
  const _GuidActionClear();
}
