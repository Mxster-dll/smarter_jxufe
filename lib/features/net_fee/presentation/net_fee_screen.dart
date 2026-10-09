import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/section_title.dart';
import 'package:smarter_jxufe/features/net_fee/data/datasources/net_fee_remote_datasource.dart';
import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_recharge.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_pay_screen.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_recharge_sheet.dart';
import 'package:smarter_jxufe/features/network_service/data/providers/network_service_providers.dart';
import 'package:smarter_jxufe/features/network_service/presentation/network_service_section.dart';
import 'package:smarter_jxufe/features/platform_guid/data/providers/guid_providers.dart';
import 'package:smarter_jxufe/features/platform_guid/presentation/guid_guide_screen.dart';
import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/design/settings_section.dart';
import 'package:smarter_jxufe/design/app_theme.dart';

/// 校园网（原「网费」）：账户余额充值 + 网络服务。
///
/// 计费段双源兜底（用户拍板）：已配置平台 GUID → 小程序实时计费源
/// （余额 + 近一年充值记录）；未配置 → 门户个人数据中心概览源（仅余额）。
///
/// 第二段「网络服务」= 学校自助服务系统的真实数据（账号概览 / 在线设备 /
/// 近期上网记录 / 账单与服务入口），实现见 `features/network_service/`。
class NetFeeScreen extends ConsumerStatefulWidget {
  const NetFeeScreen({super.key});

  @override
  ConsumerState<NetFeeScreen> createState() => _NetFeeScreenState();
}

class _NetFeeScreenState extends ConsumerState<NetFeeScreen> {
  late final PageAutoRefresher _autoRefresh = PageAutoRefresher(
    onRefresh: _refreshAll,
  );

  @override
  void initState() {
    super.initState();
    _autoRefresh.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _autoRefresh.subscribeRoute(context);
  }

  @override
  void dispose() {
    _autoRefresh.dispose();
    super.dispose();
  }

  /// 首次进入 / 从子页面返回 / 回前台：两段一起刷新。
  void _refreshAll() {
    if (!mounted) return;
    invalidateIfLoaded(ref, netFeeSummaryProvider);
    invalidateNetworkService(ref);
  }

  Future<void> _refresh() async {
    ref.invalidate(netFeeSummaryProvider);
    await ref.read(netFeeSummaryProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summaryAsync = ref.watch(netFeeSummaryProvider);

    return Scaffold(
      appBar: paneAppBar(
        context,
        title: const Text('校园网'),
        // 实时计费源依赖平台标识（GUID）。
        settingsSections: const [SettingsSection.platformGuid],
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
                  context,
                  scheme,
                  Icons.error_outline,
                  '加载失败：${friendlyErrorText(e)}',
                ),
              ],
              data: (summary) => [
                _buildSourceRow(context, scheme, summary),
                const SizedBox(height: 12),
                _buildBalanceCard(context, scheme, summary),
                if (summary.hasGuid && summary.liveError != null) ...[
                  const SizedBox(height: 12),
                  _errorCard(
                    context,
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
            const SizedBox(height: 24),
            _sectionTitle(context, '网络服务'),
            const SizedBox(height: 10),
            NetworkServiceSection(onConfigureGuid: _showGuidDialog),
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
          onPressed: _showGuidDialog,
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
    final account = summary.username?.trim() ?? '';
    return _whiteCard(
      context,
      child: Padding(
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
                    color: AppColors.tint(context, scheme.primary, 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.wifi_outlined,
                    size: 22,
                    color: scheme.primary,
                  ),
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
                Icon(
                  Icons.badge_outlined,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '账号 ${summary.username ?? ''}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('netfee_recharge'),
                  onPressed: account.isEmpty
                      ? null
                      : () => _startRecharge(summary),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.add_card_outlined, size: 18),
                  label: const Text('充值'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 充值（2026-10-09 加） ----------

  /// 充值：面板收集「账号 + 金额」→ **App 自己的收银台**（二维码就在里面）→ 回来自动刷新。
  ///
  /// ⚠ **刻意不在这里手动 invalidate**：本页挂着 `PageAutoRefresher.subscribeRoute`，
  /// 「从子页面返回」会走 `didPopNext → _refreshAll()`。两条路都留着就是同一 tick
  /// 的重复取数（AGENTS §3 那条「能 await push 就 await push」的反面教材）。
  ///
  /// ⚠ 实测（`test/net_fee_recharge_test.dart`）：**关掉充值面板本身也会触发一次
  /// 刷新** —— `ModalBottomSheetRoute` 被 pop 时 `appRouteObserver` 同样发
  /// `didPopNext`（取数量 1 → 2）。这一次数**有意留下**：用户刚离开余额卡，
  /// 支付前后本来就该看到新值；要省掉它得引入「抑制下一次 didPopNext」的机制，不值。
  ///
  /// 口径（下单 / 取码 / 轮询那三步）见
  /// `data/datasources/net_fee_recharge_remote_datasource.dart` 文件头。
  Future<void> _startRecharge(NetFeeSummary summary) async {
    final request = await showNetFeeRechargeSheet(
      context,
      account: summary.username,
      balance: summary.balance,
    );
    if (request == null || !mounted) return;

    // 「不是给自己充」要单独确认一次：钱进了别人账号就退不回来（2026-10-09 六轮）。
    final self = summary.username?.trim() ?? '';
    if (self.isNotEmpty && request.account != self) {
      if (request.kind == NetFeeChargeKind.campusCard) {
        // 校方写死「校园卡扣费只能给自己充值」——面板里已经把账号锁回自己了，
        // 这一条是兜底（例如余额是门户兜底值、或以后面板改了）。
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('校园卡只能给自己充值（校方限制），请把账号改回自己的。'),
            ),
          );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.warning_amber_outlined),
          title: const Text('给别人充值？'),
          content: Text(
            '账号 ${request.account} 不是你的上网账号（$self）。\n\n'
            '充值成功后这笔钱会进对方账号，退不回来。',
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('netfeeOtherAccountConfirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认给别人充'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    // 校园卡：直接从卡余额扣，没有二维码那一步（校方 `…/pay/cardPay`）。
    if (request.kind == NetFeeChargeKind.campusCard) {
      await _payByCampusCard(request);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NetFeePayScreen(request: request),
      ),
    );
  }

  /// 校园卡支付：**真扣款**。
  ///
  /// 链路口径见 `data/datasources/net_fee_remote_datasource.dart` 的
  /// `fetchChargeTypes` / `payByCampusCard`：先换 `enc` + `openId`，
  /// 再向校方下发的 `card` 地址提交 `{username, openId, total_fee}`。
  ///
  /// ⚠ 校方接口一提交就扣、没有密码也没有「未支付」中间态 → 这里**必须**再确认一次
  /// （面板里已经用红字说清，但那是说明不是确认）。
  Future<void> _payByCampusCard(NetFeeRechargeRequest request) async {
    final amountText = fmtYuan(request.amount);
    final account = request.account;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.credit_card_outlined),
        title: const Text('用校园卡支付？'),
        content: Text(
          '将从校园卡余额中扣除 $amountText 元，为账号 $account 充值网费。\n\n'
          '校方说明：校园卡扣费只能给自己充值；扣款成功即为网费充值成功。',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('netfeeCampusPayConfirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('确认扣款 $amountText 元'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('正在从校园卡扣款…'),
          duration: Duration(seconds: 30),
        ),
      );
    try {
      final guid = await ref.read(platformGuidProvider.future);
      if (guid == null || guid.isEmpty) {
        throw const NetFeeApiException('未配置平台标识（GUID），无法使用校园卡支付');
      }
      final source = ref.read(netFeeRemoteDataSourceProvider);
      final identity = await source.fetchWfczIdentity(guid);
      final types = await source.fetchChargeTypes();
      WfczChargeType? card;
      for (final t in types) {
        if (t.kind == NetFeeChargeKind.campusCard) {
          card = t;
          break;
        }
      }
      if (card == null) {
        throw const NetFeeApiException('校方当前没有开通校园卡支付');
      }
      final error = await source.payByCampusCard(
        identity: identity,
        amount: request.amount,
        payUrl: card.url,
      );
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error ??
                  '校园卡扣款成功，$amountText 元已充入账号 $account。'
                      '到账可能略有延迟，余额马上刷新。',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      if (error == null) _refreshAll();
    } catch (e) {
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('校园卡支付失败：${friendlyErrorText(e)}'),
            duration: const Duration(seconds: 6),
          ),
        );
    }
  }

  // ---------- 未配置 GUID 提示 ----------

  Widget _buildGuidHint(BuildContext context, ColorScheme scheme) {
    return _whiteCard(
      context,
      color: AppColors.tint(context, scheme.primary, 0.04),
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
              color: AppColors.tint(context, scheme.primary, 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.add_card_outlined,
              size: 18,
              color: scheme.primary,
            ),
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
    final type = record.feeType.isNotEmpty
        ? record.feeType
        : record.businessType;
    if (type.contains('储值') || type.contains('充值')) return '校园网充值';
    return type.isEmpty ? '校园网记录' : type;
  }

  String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  // ---------- GUID 配置对话框 ----------

  Future<void> _showGuidDialog() async {
    if (!mounted) return;
    final box = await ref.read(platformGuidBoxProvider.future);
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
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GuidGuideScreen(),
                      ),
                    );
                  },
                  child: const Text('不知道 GUID？查看获取方法'),
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
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_GuidActionSave(controller.text.trim())),
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
    ref.invalidate(platformGuidProvider);
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

    Widget _sectionTitle(BuildContext context, String text) =>
      appSectionTitle(context, text: text);

  Widget _whiteCard(
    BuildContext context, {
    required Widget child,
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color ?? Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kAppCardRadius),
        side: appCardBorderSide(scheme),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _errorCard(
    BuildContext context,
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
            : AppColors.tint(context, scheme.error, 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: light
              ? scheme.outlineVariant
              : AppColors.tintBorder(context, scheme.error, 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: light ? scheme.onSurfaceVariant : scheme.error,
          ),
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
