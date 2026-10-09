import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/errors/app_exception.dart';
import 'package:smarter_jxufe/core/web/external_url.dart';
import 'package:smarter_jxufe/core/web/in_app_web_screen.dart';
import 'package:smarter_jxufe/core/web/web_session.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_states.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/net_fee/data/providers/net_fee_providers.dart';
import 'package:smarter_jxufe/features/net_fee/data/qr_pay_url.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_models.dart';
import 'package:smarter_jxufe/features/net_fee/domain/net_fee_recharge.dart';

/// 轮询间隔（校方扫码页自己也是 3 秒一次，见 `wxpaySaoma.js`）。
const Duration kNetFeePayPollInterval = Duration(seconds: 3);

/// 轮询上限：超过就停手并提示「订单可能已超时」，别让计时器无限跑。
const Duration kNetFeePayPollTimeout = Duration(minutes: 10);

/// 本平台要不要走「**唤起微信 App**」而不是「显示二维码让人扫」。
///
/// 手机（Android / iOS）没有第二台设备可扫，而微信 Native 支付的 code_url
/// （`weixin://wxpay/bizpayurl?pr=…`，从校方二维码里解出来）本来就能被系统直接打开
/// → 微信弹出确认付款页；桌面（Windows / macOS / Linux）没有这个 scheme 的接收方，
/// 照旧显示二维码让人用手机扫。
///
/// provider 形态是为了测试：override 一下就能分别覆盖两条路。
bool inAppWeChatPaySupported(String platformName) =>
    platformName == 'android' || platformName == 'ios';

/// [inAppWeChatPaySupported] 的 provider 形态。
final inAppWeChatPaySupportedProvider = Provider<bool>(
  (ref) => inAppWeChatPaySupported(defaultTargetPlatform.name),
);

/// 校园网**收银台** —— App 自己的界面显示校方订单的微信二维码。
///
/// 用户 2026-10-09：「不要内嵌网页，把二维码封装到我们的 UI 里」。实现方式是把
/// 校方那条链路（下单 → 取码 → 轮询）用 `dio` 复刻（见
/// `data/datasources/net_fee_recharge_remote_dataource.dart`），二维码就是服务端
/// 生成的那张 jpg，取回来直接 `Image.memory` 显示 —— 不需要二维码渲染库，
/// 也不需要把整张网页嵌进来。
///
/// 四轮追加（用户「我希望在手机端可以唤起微信支付」）：手机上把那张 jpg **本地解码**
/// 成 `weixin://wxpay/bizpayurl?pr=…`（见 `data/qr_pay_url.dart`），交给系统打开
/// → 微信弹出付款页；桌面端保持二维码。二维码在两端都留着当兜底。
///
/// 进页即下单；下单失败才给「改用校方网页支付」的兜底（那条路是已验证的内嵌页 +
/// 自动提交脚本，见 `domain/net_fee_recharge.dart`）。
class NetFeePayScreen extends ConsumerStatefulWidget {
  const NetFeePayScreen({super.key, required this.request});

  final NetFeeRechargeRequest request;

  @override
  ConsumerState<NetFeePayScreen> createState() => _NetFeePayScreenState();
}

class _NetFeePayScreenState extends ConsumerState<NetFeePayScreen> {
  NetFeeOrder? _order;
  Uint8List? _qrBytes;
  String? _error;
  bool _creating = true;
  bool _paid = false;
  bool _expired = false;
  Timer? _poller;
  DateTime? _startedAt;

  /// 从二维码里解出来的微信支付链接（`weixin://…`）；解不出来就是 null。
  String? _payUrl;

  /// 是否已经替用户唤起过一次微信（避免重建页面时反复弹）。
  bool _wechatOpened = false;

  /// 唤起失败的原因（没装微信 / 系统不认这个 scheme）。
  String? _launchError;

  @override
  void initState() {
    super.initState();
    unawaited(_createOrder());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  /// 下单 + 取二维码 + 开始轮询；手机端顺带解出 `weixin://` 并唤起微信。
  Future<void> _createOrder() async {
    _poller?.cancel();
    setState(() {
      _creating = true;
      _error = null;
      _paid = false;
      _expired = false;
      _order = null;
      _qrBytes = null;
      _payUrl = null;
      _wechatOpened = false;
      _launchError = null;
    });
    try {
      final source = ref.read(netFeeRechargeRemoteDataSourceProvider);
      final order = await source.createOrder(
        account: widget.request.account,
        amount: widget.request.amount,
      );
      final bytes = await source.fetchQrImage(order.orderNo);
      // 解码是纯本地计算（139×139 的图，毫秒级），失败也不影响下面的二维码显示。
      final payUrl = decodeWeChatPayUrl(bytes);
      if (!mounted) return;
      setState(() {
        _order = order;
        _qrBytes = bytes;
        _payUrl = payUrl;
        _creating = false;
        _startedAt = DateTime.now();
      });
      _startPolling();
      // 手机端：进页就把微信叫起来（用户点「扫码支付」的意图就是付款）。
      if (payUrl != null && ref.read(inAppWeChatPaySupportedProvider)) {
        await _openWeChat();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _creating = false;
      });
    }
  }

  /// 交给系统打开 `weixin://…` → 微信弹出确认付款页。
  ///
  /// 失败**不阻断**：页面上还有二维码，用户可以换台设备扫。
  Future<void> _openWeChat() async {
    final url = _payUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    bool opened = false;
    try {
      opened = await ref.read(externalUrlOpenerProvider)(uri);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _wechatOpened = true;
      _launchError = opened
          ? null
          : '没能唤起微信（可能没装微信）—— 可以改用下面的二维码让另一台设备扫。';
    });
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(kNetFeePayPollInterval, (_) => _checkOnce());
  }

  /// 查一次订单状态；已支付就切成功态。
  Future<void> _checkOnce() async {
    final order = _order;
    if (order == null || _paid) return;
    final started = _startedAt;
    if (started != null &&
        DateTime.now().difference(started) > kNetFeePayPollTimeout) {
      _poller?.cancel();
      if (mounted) setState(() => _expired = true);
      return;
    }
    try {
      final state = await ref
          .read(netFeeRechargeRemoteDataSourceProvider)
          .fetchPayState(order.orderNo);
      if (!mounted) return;
      if (state == kNetFeePayStatePaid) {
        _poller?.cancel();
        setState(() {
          _paid = true;
          _order = order.copyWith(payState: state);
        });
      }
    } catch (_) {
      // 轮询失败不打扰用户（服务端偶发 403 很常见），下一次自然重试。
    }
  }

  /// 「改用校方网页支付」：内嵌校方支付页（带自动提交脚本）。
  ///
  /// 只在**下单失败**时才给这个入口 —— 下单成功就没必要再走一遍网页（会多下一单）。
  Future<void> _openWebPay() async {
    if (!mounted) return;
    final url = widget.request.url;
    if (!ref.read(inAppWebViewSupportedProvider)) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await ref.read(externalUrlOpenerProvider)(uri);
      }
      return;
    }
    final builder = ref.read(webViewScreenBuilderProvider);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => builder(
          EmbeddedWebRequest(
            title: '校园网充值',
            url: url,
            pageScript: netFeeRechargePageScript(
              amount: widget.request.amount,
              submitToken: newNetFeeRechargeSubmitToken(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      // 二级页用裸 AppBar（与阅读器 / 答题页 / 课程详情同款，不带设置齿轮）。
      appBar: AppBar(
        title: const Text('校园网充值'),
        centerTitle: false,
        backgroundColor: Theme.of(context).cardTheme.color,
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildBody(context, scheme),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme scheme) {
    if (_creating) {
      return const AppLoadingState(message: '正在向校方下单…');
    }
    if (_error != null) {
      return Column(
        children: [
          Expanded(
            child: AppErrorState(
              error: _error!,
              title: '没能生成二维码',
              onRetry: _createOrder,
              retryKey: const Key('netfeePayRetry'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: OutlinedButton.icon(
              key: const Key('netfeePayFallbackWeb'),
              onPressed: _openWebPay,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('改用校方网页支付'),
            ),
          ),
        ],
      );
    }
    if (_paid) return _buildPaid(context, scheme);
    return _buildQr(context, scheme);
  }

  // ---------- 二维码 / 唤起微信 ----------

  Widget _buildQr(BuildContext context, ColorScheme scheme) {
    final order = _order;
    final mobile = ref.watch(inAppWeChatPaySupportedProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      children: [
        Center(
          child: Text(
            '¥ ${fmtYuan(widget.request.amount)}',
            key: const Key('netfeePayAmount'),
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '账号 ${widget.request.account}',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 18),
        // 手机端：**唤起微信**是主路径，二维码降为兜底（换台设备扫）。
        if (mobile) ...[
          _wechatPanel(context, scheme),
          const SizedBox(height: 20),
          Center(child: _qrCard(context, size: 170)),
          const SizedBox(height: 10),
          Center(
            child: Text(
              '也可以让另一台设备扫这个码',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ] else ...[
          Center(child: _qrCard(context, size: 220)),
          const SizedBox(height: 16),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.qr_code_scanner_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  '打开手机微信扫一扫付款',
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        if (_expired)
          _notice(
            context,
            scheme,
            Icons.timer_off_outlined,
            '这笔订单可能已经超时了。可以点「刷新二维码」重新下单，'
            '或者直接点「我已完成支付」再核对一次。',
            warn: true,
          ),
        if (_expired) const SizedBox(height: 12),
        _notice(
          context,
          scheme,
          Icons.info_outline,
          '付款成功后本页会自动变成成功状态；到账可能略有延迟，'
          '返回校园网页时余额与充值记录会自动刷新。',
        ),
        if (order != null) ...[
          const SizedBox(height: 14),
          Center(
            child: Text(
              '订单号 ${order.orderNo}',
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('netfeePayRefreshQr'),
                onPressed: _creating ? null : _createOrder,
                child: const Text('刷新二维码'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('netfeePayCheck'),
                onPressed: _checkOnce,
                child: const Text('我已完成支付'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 白底二维码卡片 —— 二维码是白底 jpg，深色模式下也得贴在白卡上才扫得出来。
  Widget _qrCard(BuildContext context, {required double size}) {
    final bytes = _qrBytes;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ShapeDecoration(
        shape: appCardShape(context),
        color: Colors.white,
      ),
      child: bytes == null
          ? SizedBox(width: size, height: size)
          : Image.memory(
              bytes,
              key: const Key('netfeePayQr'),
              width: size,
              height: size,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
    );
  }

  /// 手机端的「唤起微信」面板：一个主按钮 + 一行状态。
  ///
  /// 二维码解不出 `weixin://`（`_payUrl == null`）时按钮禁用 —— 那种情况下
  /// 下面的二维码仍然可用，不耽误付款。
  Widget _wechatPanel(BuildContext context, ColorScheme scheme) {
    final canOpen = _payUrl != null;
    final failed = _launchError != null;
    return Column(
      children: [
        FilledButton.icon(
          key: const Key('netfeePayOpenWeChat'),
          onPressed: canOpen ? _openWeChat : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          icon: const Icon(Icons.wechat, size: 20),
          label: const Text('打开微信支付'),
        ),
        const SizedBox(height: 10),
        Text(
          failed
              ? _launchError!
              : (_wechatOpened ? '已打开微信：在微信里完成付款后回到本页' : '点上面的按钮，在微信里完成付款'),
          key: const Key('netfeePayWeChatHint'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: failed ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ---------- 成功 ----------

  Widget _buildPaid(BuildContext context, ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.tint(context, scheme.primary, 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_outline,
              size: 40,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            '支付成功',
            key: const Key('netfeePayPaid'),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '¥ ${fmtYuan(widget.request.amount)} · 账号 ${widget.request.account}',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 20),
        _notice(
          context,
          scheme,
          Icons.schedule_outlined,
          '校方到账可能略有延迟。返回校园网页后余额与充值记录会自动刷新；'
          '若几分钟后仍未到账，可下拉刷新或稍后再看。',
        ),
        const SizedBox(height: 26),
        FilledButton(
          key: const Key('netfeePayDone'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _notice(
    BuildContext context,
    ColorScheme scheme,
    IconData icon,
    String text, {
    bool warn = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
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
