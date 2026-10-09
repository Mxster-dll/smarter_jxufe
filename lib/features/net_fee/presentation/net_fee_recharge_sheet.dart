import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_recharge.dart';

/// 打开「校园网充值」面板，返回用户填好的 [NetFeeRechargeRequest]；
/// `null` = 用户取消。
///
/// **面板只收集输入，不发任何请求** —— 「打开校方支付页 + 回来后刷新」是调用方的
/// 事（`net_fee_screen.dart` 的 `_startRecharge`）。这样面板本身没有网络依赖、
/// 也不必知道内嵌/外部的分流口径。
Future<NetFeeRechargeRequest?> showNetFeeRechargeSheet(
  BuildContext context, {
  String? account,
  double? balance,
}) {
  return showModalBottomSheet<NetFeeRechargeRequest>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => NetFeeRechargeSheet(account: account, balance: balance),
  );
}

/// 校园网充值面板：**选金额 + 确认账号 → 去校方支付页**。
///
/// 为什么是这个形态（口径见 `domain/net_fee_recharge.dart`）：
/// 小程序侧的「网费充值」是微信原生小程序，支付走 `wx.requestPayment`，
/// App 无法复刻；校方网页支付页则可以**吃 URL 里的 amount 预填**。
/// 于是 App 的价值就是把用户在手机上要点的三件事（改账号、选金额、找入口）
/// 压成一次选择。
class NetFeeRechargeSheet extends StatefulWidget {
  const NetFeeRechargeSheet({super.key, this.account, this.balance});

  /// 预填的上网账号（取校园网页当前的计费账号）。
  final String? account;

  /// 当前余额，用于「充值后预计」那一行；`null` = 不显示该行。
  final double? balance;

  @override
  State<NetFeeRechargeSheet> createState() => _NetFeeRechargeSheetState();
}

class _NetFeeRechargeSheetState extends State<NetFeeRechargeSheet> {
  final TextEditingController _accountCtrl = TextEditingController();
  final TextEditingController _customCtrl = TextEditingController();
  final TextEditingController _targetCtrl = TextEditingController();

  /// 用户是**直接说充多少钱**，还是**说想让余额变成多少**（2026-10-09 五轮）。
  ///
  /// 后者更贴近实际想法（「我想充到 50」），实际充值金额 = 目标 − 当前余额。
  bool _byTarget = false;

  /// 选中的快速档；`null` = 用「其他」里的自填金额。
  double? _quick;

  /// 目标余额模式下选中的档；`null` = 用目标输入框里的自填值。
  double? _targetQuick;

  /// 充值方式（2026-10-09 四轮 · 用户「网费充值中有一步选择充值方式」）。
  ///
  /// 默认微信 —— 它是校方唯一开通的扫码通道；校园卡是**直接扣卡余额**，
  /// 所以只有用户显式选了才走。
  NetFeeChargeKind _kind = NetFeeChargeKind.weixin;

  String? _error;

  @override
  void initState() {
    super.initState();
    _accountCtrl.text = widget.account?.trim() ?? '';
    // 默认选第一档：与校方页面自己的默认一致（`recharge.js` 也会 `#moneybut1.click()`），
    // 屏幕上按钮同时把金额写出来，用户看到不对会自己改。
    _quick = kNetFeeRechargeQuickAmounts.first;
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    _customCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  /// 目标余额模式下用户填的目标（`null` = 还没填出合法数字）。
  double? get _targetAmount {
    final quick = _targetQuick;
    if (quick != null) return quick;
    final text = _targetCtrl.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  /// 目标模式下**还需充值多少**（= 目标 − 当前余额，规整到分）。
  ///
  /// 余额拿不到（`widget.balance == null`）时返回 `null` —— 那种情况下这个模式没法算。
  double? get _needToReachTarget {
    final target = _targetAmount;
    final balance = widget.balance;
    if (target == null || balance == null) return null;
    return netFeeNormalizeAmount(target - balance);
  }

  /// 当前金额（`null` = 还没填出合法数字）。
  double? get _amount {
    if (_byTarget) {
      final need = _needToReachTarget;
      return (need == null || need <= 0) ? null : need;
    }
    final quick = _quick;
    if (quick != null) return quick;
    final text = _customCtrl.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  void _pickQuick(double value) {
    setState(() {
      _quick = value;
      _customCtrl.clear();
      _error = null;
    });
  }

  void _pickTarget(double value) {
    setState(() {
      _targetQuick = value;
      _targetCtrl.clear();
      _error = null;
    });
  }

  void _setByTarget(bool byTarget) {
    setState(() {
      _byTarget = byTarget;
      _error = null;
    });
  }

  /// 切换充值方式。
  ///
  /// 选校园卡时要把账号**还原成自己**：校方写死「校园卡扣费只能给自己充值」，
  /// 而用户可能先改成别人的账号再切过来 —— 光把输入框禁用会留下「锁着一个别人的账号」
  /// 这种更难查的状态。小程序 `chargeTypeChange` 里也是这么做的
  /// （`t.account = this.data.currrentUsername`）。
  void _setKind(NetFeeChargeKind kind) {
    setState(() {
      _kind = kind;
      _error = null;
      if (kind == NetFeeChargeKind.campusCard) {
        final self = widget.account?.trim() ?? '';
        if (self.isNotEmpty) _accountCtrl.text = self;
      }
    });
  }

  void _onCustomChanged(String value) {
    setState(() {
      if (value.trim().isNotEmpty) _quick = null;
      _error = null;
    });
  }

  void _submit() {
    final accountError = netFeeRechargeAccountError(_accountCtrl.text);
    if (accountError != null) {
      setState(() => _error = accountError);
      return;
    }

    final double amount;
    if (_byTarget) {
      final balance = widget.balance;
      if (balance == null) {
        setState(() => _error = '当前拿不到账户余额，请改用「按金额充值」');
        return;
      }
      if (_targetAmount == null) {
        setState(() => _error = '请选择或输入目标余额');
        return;
      }
      final need = _needToReachTarget;
      if (need == null || need <= 0) {
        setState(
          () => _error = '目标余额要高于当前余额（${fmtYuan(balance)} 元）',
        );
        return;
      }
      amount = need;
    } else {
      final raw = _quick?.toString() ?? _customCtrl.text;
      final amountError = netFeeRechargeAmountError(raw);
      if (amountError != null) {
        setState(() => _error = amountError);
        return;
      }
      amount = netFeeNormalizeAmount(double.parse(raw.trim()));
    }

    Navigator.of(context).pop(
      NetFeeRechargeRequest(
        account: _accountCtrl.text.trim(),
        amount: amount,
        kind: _kind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amount = _amount;
    final balance = widget.balance;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.tint(context, scheme.primary, 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.add_card_outlined,
                    size: 21,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '校园网充值',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '在校方支付页完成支付 · App 不接触支付凭据',
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
            const SizedBox(height: 18),
            _label(context, '上网账号'),
            const SizedBox(height: 6),
            TextField(
              key: const Key('netfeeRechargeAccount'),
              controller: _accountCtrl,
              // 校方写死了「校园卡扣费只能给自己充值」→ 选校园卡时把账号锁住，
              // 别让用户改完再被校方拒一次（那一次拒得莫名其妙）。
              enabled: _kind != NetFeeChargeKind.campusCard,
              decoration: const InputDecoration(
                hintText: '宽带账号，通常就是学号',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // 两种口径：直接说充多少钱，或者说想让余额变成多少（后者自动算差额）。
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  key: const Key('netfeeModeAmount'),
                  label: const Text(
                    '按金额充值',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  selected: !_byTarget,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _setByTarget(false),
                ),
                ChoiceChip(
                  key: const Key('netfeeModeTarget'),
                  label: const Text(
                    '充到目标余额',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  selected: _byTarget,
                  visualDensity: VisualDensity.compact,
                  onSelected: widget.balance == null
                      ? null
                      : (_) => _setByTarget(true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_byTarget) ...[
              _label(context, '充值金额'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final value in kNetFeeRechargeQuickAmounts)
                    ChoiceChip(
                      // key 与标签都走 `fmtYuan`：12.5 显示「12.5 元」，
                      // 10 显示「10 元」而不是「10.0 元」。
                      key: Key('netfeeRechargeAmount${fmtYuan(value)}'),
                      label: Text(
                        '${fmtYuan(value)} 元',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      selected: _quick == value,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _pickQuick(value),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('netfeeRechargeCustom'),
                controller: _customCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: _onCustomChanged,
                decoration: const InputDecoration(
                  labelText: '其他金额',
                  hintText: '例如 30',
                  prefixText: '¥ ',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ] else ...[
              _label(context, '目标余额'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final value in kNetFeeRechargeTargetAmounts)
                    ChoiceChip(
                      key: Key('netfeeTarget${fmtYuan(value)}'),
                      label: Text(
                        '${fmtYuan(value)} 元',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      selected: _targetQuick == value,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _pickTarget(value),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('netfeeTargetCustom'),
                controller: _targetCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {
                  _targetQuick = null;
                  _error = null;
                }),
                decoration: const InputDecoration(
                  labelText: '其他目标余额',
                  hintText: '例如 60',
                  prefixText: '¥ ',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.balance != null) ...[
                const SizedBox(height: 10),
                _targetPreview(context, scheme),
              ],
            ],
            const SizedBox(height: 14),
            _label(context, '充值方式'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final kind in NetFeeChargeKind.values)
                  ChoiceChip(
                    key: Key('netfeeChargeKind${kind.key}'),
                    avatar: Icon(
                      kind == NetFeeChargeKind.weixin
                          ? Icons.qr_code_2_outlined
                          : Icons.credit_card_outlined,
                      size: 16,
                      color: _kind == kind
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    label: Text(
                      kind.label,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    selected: _kind == kind,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _setKind(kind),
                  ),
              ],
            ),
            if (_kind == NetFeeChargeKind.campusCard) ...[
              const SizedBox(height: 8),
              _notice(
                context,
                scheme,
                Icons.warning_amber_outlined,
                '校园卡支付**直接从校园卡余额扣款**（校方接口提交即扣，没有密码那一步），'
                '且校方限制「只能给自己充值」。余额不足会由校方拒绝。',
                warn: true,
              ),
            ],
            if (balance != null && amount != null && amount > 0) ...[
              const SizedBox(height: 14),
              _balancePreview(context, scheme, balance, amount),
            ],
            const SizedBox(height: 14),
            _notes(context, scheme),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      key: const Key('netfeeRechargeError'),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                TextButton(
                  key: const Key('netfeeRechargeCancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const Key('netfeeRechargeGo'),
                  onPressed: _submit,
                  icon: Icon(
                    _kind == NetFeeChargeKind.campusCard
                        ? Icons.credit_card_outlined
                        : Icons.qr_code_2_outlined,
                    size: 18,
                  ),
                  label: Text(
                    '${_kind == NetFeeChargeKind.campusCard ? '校园卡支付' : '扫码支付'}'
                    '${amount == null || amount <= 0 ? '' : ' ¥${fmtYuan(netFeeNormalizeAmount(amount))}'}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 「当前余额 → 充值后预计」。
  ///
  /// 措辞用**预计**而不是承诺：余额可能在别处已经变过，且到账本身有延迟。
  Widget _balancePreview(
    BuildContext context,
    ColorScheme scheme,
    double balance,
    double amount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tint(context, scheme.primary, 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.tintBorder(context, scheme.primary, 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.trending_up, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前余额 ${fmtYuan(balance)} 元 → 充值后预计 '
              '${fmtYuan(balance + netFeeNormalizeAmount(amount))} 元',
              key: const Key('netfeeRechargePreview'),
              style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  /// 目标模式的算式条：**当前余额 → 目标余额，还需充值多少**（2026-10-09 五轮）。
  ///
  /// 算式本身用的是页面传进来的余额快照 —— 文案里要把「当前余额」写出来，
  /// 免得用户拿一个几分钟前的数字当准数。
  Widget _targetPreview(BuildContext context, ColorScheme scheme) {
    final balance = widget.balance ?? 0;
    final target = _targetAmount;
    final need = _needToReachTarget;
    final invalid = target != null && (need == null || need <= 0);
    final String text;
    if (target == null) {
      text = '当前余额 ${fmtYuan(balance)} 元 —— 选个目标，这里会算出还要充多少';
    } else if (invalid) {
      text = '目标 ${fmtYuan(target)} 元不高于当前余额 ${fmtYuan(balance)} 元，不需要充值';
    } else {
      text = '当前余额 ${fmtYuan(balance)} 元 → 目标 ${fmtYuan(target)} 元，'
          '还需充值 ${fmtYuan(need!)} 元';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.tint(
          context,
          invalid ? scheme.error : scheme.primary,
          0.05,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.tintBorder(
            context,
            invalid ? scheme.error : scheme.primary,
            0.25,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            invalid ? Icons.info_outline : Icons.calculate_outlined,
            size: 16,
            color: invalid ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              key: const Key('netfeeTargetPreview'),
              style: TextStyle(
                fontSize: 12.5,
                color: invalid ? scheme.error : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 支付方式与到账说明 —— 口径来自校方页面实测：选微信后内嵌页会**自动提交**，
  /// 直接落到 `/WebPay/wxPaySaoma` 的扫码页（见 `domain/net_fee_recharge.dart`）。
  Widget _notes(BuildContext context, ColorScheme scheme) {
    final campus = _kind == NetFeeChargeKind.campusCard;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                campus
                    ? Icons.credit_card_outlined
                    : Icons.qr_code_2_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  campus
                      ? '直接从校园卡余额扣款，扣款成功即为网费充值成功'
                      : '打开后直接是微信收款二维码（账号与金额已替你填好）',
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            campus
                ? '校方口径：校园卡扣费只能给自己充值。到账可能略有延迟，'
                      '返回校园网页时余额与充值记录会自动刷新。'
                : '扫码前请核对二维码上方的金额。付款成功后校方页面会自己跳转；'
                      '回到本页时余额与充值记录会自动刷新（校方口径：到账可能有所延迟）。'
                      '若改用系统浏览器打开，则需要你在页面上点一次「立即支付」。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  /// 一行提示条（`warn: true` = 用错误色，给「校园卡直接扣款」这种要说清的场合）。
  Widget _notice(
    BuildContext context,
    ColorScheme scheme,
    IconData icon,
    String text, {
    bool warn = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: warn
            ? AppColors.tint(context, scheme.error, 0.06)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: warn
              ? AppColors.tintBorder(context, scheme.error, 0.35)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: warn ? scheme.error : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: warn ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
