import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/design/Icons.dart';
import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/qr_code_card.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/verification_code_input.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/account_screen.dart';
import 'package:smarter_jxufe/shared/widgets/carousel_switcher.dart';

/// 修复与整理后的统一 MFA 对话框
class UnifiedMfaDialog extends ConsumerStatefulWidget {
  final String title;
  final String info;
  final bool startInQrMode;
  final Stream<dynamic> qrStatusStream;
  final Future<void> Function() onSwitchToQr;
  final Future<String?> Function() onSwitchToSms;
  final Future<void> Function() onSendCode;
  final Future<bool> Function(String code) onValidate;
  final VoidCallback? onQrAuthorized;
  final bool showSwitchAccount;

  const UnifiedMfaDialog({
    super.key,
    required this.title,
    this.info = '',
    this.startInQrMode = true,
    required this.qrStatusStream,
    required this.onSwitchToQr,
    required this.onSwitchToSms,
    required this.onSendCode,
    required this.onValidate,
    this.onQrAuthorized,
    this.showSwitchAccount = false,
  });

  static Future<({bool authorized, bool trustDevice})> show(
    BuildContext context, {
    String title = '',
    String info = '',
    bool startInQrMode = true,
    bool showSwitchAccount = false,
    required Stream<dynamic> qrStatusStream,
    required Future<void> Function() onSwitchToQr,
    required Future<String?> Function() onSwitchToSms,
    required Future<void> Function() onSendCode,
    required Future<bool> Function(String code) onValidate,
  }) async {
    bool authorized = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UnifiedMfaDialog(
        title: title,
        info: info,
        startInQrMode: startInQrMode,
        showSwitchAccount: showSwitchAccount,
        qrStatusStream: qrStatusStream,
        onSwitchToQr: onSwitchToQr,
        onSwitchToSms: onSwitchToSms,
        onSendCode: onSendCode,
        onValidate: (code) async {
          final ok = await onValidate(code);
          if (ok) authorized = true;
          return ok;
        },
        onQrAuthorized: () {
          authorized = true;
        },
      ),
    );

    final trustDevice = ProviderScope.containerOf(
      context,
    ).read(qrLoginViewModelProvider).trustDevice;
    return (authorized: authorized, trustDevice: trustDevice);
  }

  @override
  ConsumerState<UnifiedMfaDialog> createState() => _UnifiedMfaDialogState();
}

class _UnifiedMfaDialogState extends ConsumerState<UnifiedMfaDialog>
    with SingleTickerProviderStateMixin {
  bool _dismissed = false;
  StreamSubscription<dynamic>? _qrSub;
  final _codeInputKey = GlobalKey<VerificationCodeInputState>();
  String _smsCode = '';
  bool _sending = false;
  String? _errorText;
  int _countdown = 0;
  bool _qrMode = true;
  String? _phoneHint;
  bool _validating = false;
  bool _loadingSms = false;
  bool _transitioning = false;
  bool _targetIsQr = true;

  late final AnimationController _collapseCtrl;
  late final Animation<double> _shrinkAnim;
  late final SlideCarouselController _bodyCtrl;
  late final SlideCarouselController _hintCtrl;

  @override
  void initState() {
    super.initState();
    _qrMode = widget.startInQrMode;
    _targetIsQr = _qrMode;
    _collapseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _shrinkAnim = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _collapseCtrl, curve: Curves.easeInOut));
    // 强制绑定到当前 tick，避免首帧闪动
    _shrinkAnim.addListener(() {});
    _collapseCtrl.addStatusListener(_onCollapseDone);
    _bodyCtrl = SlideCarouselController(totalItems: 2);
    _hintCtrl = SlideCarouselController(totalItems: 2);
    if (_qrMode) _listenQrStatus();
  }

  void _listenQrStatus() {
    _qrSub?.cancel();
    _qrSub = widget.qrStatusStream.listen(
      (event) {
        if (!mounted || _dismissed) return;
        if (event is QrCodeStatus && event == QrCodeStatus.authorized) {
          widget.onQrAuthorized?.call();
          // 短暂延迟让用户看到"验证成功"后再关闭
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted && !_dismissed) {
              Navigator.of(context).pop();
            }
          });
        }
      },
      onError: (e) {
        // ignore errors for now
      },
    );
  }

  @override
  void dispose() {
    _dismissed = true;
    _qrSub?.cancel();
    _collapseCtrl.dispose();
    super.dispose();
  }

  bool _collapseRunning = false;

  void _onCollapseDone(AnimationStatus status) async {
    if (status != AnimationStatus.completed) return;
    if (_collapseRunning) return;
    _collapseRunning = true;
    // 收缩完成 → 加载
    await _executeModeSwitch();
    // 展开
    _collapseCtrl.reverse();
    await _collapseCtrl.reverse().orCancel;
    _collapseRunning = false;
    if (mounted) setState(() => _transitioning = false);
  }

  Future<void> _executeModeSwitch() async {
    if (_dismissed) return;
    setState(() => _loadingSms = true);
    try {
      if (_targetIsQr) {
        await widget.onSwitchToQr();
      } else {
        final hint = await widget.onSwitchToSms();
        if (_dismissed) return;
        _phoneHint = hint;
      }
    } catch (e) {
      if (mounted) setState(() => _errorText = e.toString());
    } finally {
      if (mounted && !_dismissed) {
        setState(() => _loadingSms = false);
      }
    }
  }

  Future<void> _switchToQr() async {
    if (_dismissed || _transitioning || _collapseRunning) return;
    _qrMode = true;
    _targetIsQr = true;
    _bodyCtrl.previous(); // 内容区：倒向（新QR从左入，旧SMS向右出）
    _hintCtrl.forward(1); // 信息条：始终正向
    _listenQrStatus();
    setState(() {
      _transitioning = true;
    });
    _collapseCtrl.forward();
  }

  Future<void> _switchToSms() async {
    if (_dismissed || _transitioning || _collapseRunning) return;
    _qrMode = false;
    _targetIsQr = false;
    _bodyCtrl.forward(1); // 内容区：正向（新SMS从右入，旧QR向左出）
    _hintCtrl.forward(1); // 信息条：始终正向
    setState(() {
      _transitioning = true;
    });
    _collapseCtrl.forward();
  }

  Future<void> _sendCode() async {
    setState(() {
      _sending = true;
      _errorText = null;
    });
    try {
      await widget.onSendCode();
      setState(() => _countdown = 60);
      _startCountdown();
    } catch (e) {
      setState(() => _errorText = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        if (_countdown > 0) {
          _countdown--;
          _startCountdown();
        }
      });
    });
  }

  Future<void> _validate() async {
    final code = _smsCode;
    if (code.isEmpty) {
      setState(() => _errorText = '请输入验证码');
      return;
    }
    setState(() {
      _validating = true;
      _errorText = null;
    });
    try {
      final ok = await widget.onValidate(code);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      } else {
        setState(() => _errorText = '验证失败，请重新输入');
      }
    } catch (e) {
      if (mounted) setState(() => _errorText = e.toString());
    } finally {
      if (mounted) setState(() => _validating = false);
    }
  }

  Widget _buildModeButton({
    required IconData icon,
    required Color color,
    required bool active,
    required VoidCallback? onTap,
  }) {
    final isHovering = ValueNotifier<bool>(false);
    return MouseRegion(
      onEnter: (_) => isHovering.value = true,
      onExit: (_) => isHovering.value = false,
      child: GestureDetector(
        onTap: _transitioning ? null : onTap,
        child: ValueListenableBuilder<bool>(
          valueListenable: isHovering,
          builder: (context, hovering, child) {
            final showActive = active || hovering;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: showActive ? color : JxufeTheme.inputBgColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: showActive ? color : JxufeTheme.borderColor,
                  width: showActive ? 2 : 1,
                ),
                boxShadow: showActive
                    ? [
                        BoxShadow(
                          color: color.withAlpha(60),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: showActive ? Colors.white : color,
                size: 21,
              ),
            );
          },
        ),
      ),
    );
  }

  /// 操作芯片 — AnimatedCrossFade 实现按钮左右换位动画，Row 自适应宽度
  Widget _buildActionChip() {
    final isQr = _qrMode;
    final isQrTarget = _targetIsQr;
    final label = isQr
        ? '刷新二维码'
        : _sending
        ? '发送中…'
        : _countdown > 0
        ? '${_countdown}s 后重发'
        : '发送验证码';
    final isQrLoading =
        isQr &&
        ref.watch(qrLoginViewModelProvider).status == QrCodeStatus.loading;
    final showLoading = isQrLoading || (!isQr && _loadingSms);
    final enabled =
        !_transitioning &&
        !showLoading &&
        (isQr || (!_sending && _countdown == 0));
    final onTap = isQr
        ? () => ref.read(qrLoginViewModelProvider.notifier).refresh()
        : _sendCode;

    final buttonWidget = SizedBox(
      width: 24,
      height: 24,
      child: showLoading
          ? const Center(
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(JxufeTheme.primaryColor),
                ),
              ),
            )
          : IconButton(
              onPressed: enabled ? onTap : null,
              padding: EdgeInsets.zero,
              icon: Icon(
                isQr ? Icons.refresh_rounded : Icons.send_rounded,
                size: 16,
              ),
              style: IconButton.styleFrom(
                backgroundColor: JxufeTheme.primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: JxufeTheme.primaryColor.withAlpha(100),
                disabledForegroundColor: Colors.white70,
              ),
            ),
    );

    final textWidget = Text(
      label,
      style: const TextStyle(fontSize: 13, color: JxufeTheme.textColor),
    );

    return AnimatedAlign(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: _targetIsQr ? Alignment.centerLeft : Alignment.centerRight,
      child: AnimatedBuilder(
        animation: _collapseCtrl,
        builder: (context, child) {
          final fadingText = ClipRect(
            child: SizeTransition(
              sizeFactor: _shrinkAnim,
              axis: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 8),
                  textWidget,
                  const SizedBox(width: 8),
                ],
              ),
            ),
          );

          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: JxufeTheme.inputBgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: JxufeTheme.borderColor),
            ),
            child: AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: isQrTarget
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Row(
                mainAxisSize: MainAxisSize.min,
                children: [buttonWidget, fadingText],
              ),
              secondChild: Row(
                mainAxisSize: MainAxisSize.min,
                children: [fadingText, buttonWidget],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 统一提示条：浅蓝背景 + 图标 + 富文本，固定宽度 300
  Widget _buildHintBar({
    required IconData icon,
    required List<InlineSpan> spans,
  }) {
    return SizedBox(
      width: 300,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF73A9EC).withAlpha(15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: const Color(0xFF73A9EC)),
            const SizedBox(width: 8),
            Expanded(child: Text.rich(TextSpan(children: spans))),
          ],
        ),
      ),
    );
  }

  // ── QR 模式 ──

  Widget _buildQrBody() {
    return const QrCodeCard(
      showOuterDecoration: false,
      showRefreshButton: false,
      showHint: false,
    );
  }

  List<InlineSpan> get _qrHintSpans => const [
    TextSpan(
      text: '使用 ',
      style: TextStyle(fontSize: 13, color: JxufeTheme.textColor),
    ),
    TextSpan(
      text: '微信',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF14c468),
      ),
    ),
    TextSpan(
      text: ' 或 ',
      style: TextStyle(fontSize: 13, color: JxufeTheme.textColor),
    ),
    TextSpan(
      text: '企业微信',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF73A9EC),
      ),
    ),
    TextSpan(
      text: ' 扫码完成验证',
      style: TextStyle(fontSize: 13, color: JxufeTheme.textColor),
    ),
  ];

  List<InlineSpan> get _smsHintSpans => const [
    TextSpan(
      text: '输入 ',
      style: TextStyle(fontSize: 13, color: JxufeTheme.textColor),
    ),
    TextSpan(
      text: '企业微信',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF73A9EC),
      ),
    ),
    TextSpan(
      text: ' 中收到的验证码完成验证',
      style: TextStyle(fontSize: 13, color: JxufeTheme.textColor),
    ),
  ];

  Widget _buildHint() {
    if (!_qrMode && (_phoneHint ?? '').isEmpty) return const SizedBox.shrink();
    return _buildHintBar(
      icon: Icons.info_outline,
      spans: _qrMode ? _qrHintSpans : _smsHintSpans,
    );
  }

  Widget _qrHintBar() =>
      _buildHintBar(icon: Icons.info_outline, spans: _qrHintSpans);

  Widget _smsHintBar() {
    if ((_phoneHint ?? '').isEmpty) return const SizedBox.shrink();
    return _buildHintBar(icon: Icons.info_outline, spans: _smsHintSpans);
  }

  // ── SMS 模式 ──

  Widget _buildSmsBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 48),
        Text("请输入验证码", style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 28),
        Center(
          child: VerificationCodeInput(
            key: _codeInputKey,
            length: 4,
            cellSize: 52,
            gap: 12,
            disabled: _validating,
            onChanged: (v) => _smsCode = v,
            onCompleted: (v) {
              _smsCode = v;
              _validate();
            },
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 208,
          height: 20,
          child: _errorText != null
              ? Row(
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      size: 14,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          // width: 208,
          height: 48,
          child: ElevatedButton(
            onPressed: _validating ? null : _validate,
            style: ElevatedButton.styleFrom(
              backgroundColor: JxufeTheme.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: JxufeTheme.primaryColor.withAlpha(150),
              disabledForegroundColor: Colors.white70,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: Text(
              _validating ? '验证中…' : '确 定',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = ref.read(qrLoginViewModelProvider.notifier);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: IntrinsicWidth(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(30),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 10, 28, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // header: mode buttons + title
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: JxufeTheme.textColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      // if (widget.info.isNotEmpty) ...[
                      //   const SizedBox(height: 6),
                      //   Text(
                      //     widget.info,
                      //     style: const TextStyle(
                      //       fontSize: 13,
                      //       color: JxufeTheme.hintColor,
                      //       height: 1.4,
                      //     ),
                      //     textAlign: TextAlign.center,
                      //   ),
                      // ],
                    ],
                  ),
                ),

                // body: shared header (account) + switchable inner container
                Consumer(
                  builder: (context, ref, child) {
                    final state = ref.watch(qrLoginViewModelProvider);
                    if (state.username.isNotEmpty) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 头像 —— IMS 个人信息页同款（用姓）
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            child: state.displayName.isNotEmpty
                                ? Text(
                                    state.displayName[0],
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onError,
                                    ),
                                  )
                                : Icon(
                                    Icons.person,
                                    size: 26,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onError,
                                  ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (widget.showSwitchAccount)
                                  const SizedBox(width: 36),

                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      text: state.username,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: JxufeTheme.textColor,
                                      ),
                                    ),

                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.showSwitchAccount) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const AccountScreen(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.logout, size: 18),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                    tooltip: '切换账户',
                                  ),
                                ],
                              ],
                            ),
                          ),

                          Center(
                            child: GestureDetector(
                              onTap: () {
                                viewModel.setTrustDevice(!state.trustDevice);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: state.trustDevice
                                      ? JxufeTheme.primaryColor
                                      : JxufeTheme.inputBgColor,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: state.trustDevice
                                        ? JxufeTheme.primaryColor
                                        : JxufeTheme.borderColor,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      state.trustDevice
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      size: 16,
                                      color: state.trustDevice
                                          ? Colors.white
                                          : JxufeTheme.hintColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '设为信任设备',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: state.trustDevice
                                            ? Colors.white
                                            : JxufeTheme.textColor,
                                        fontWeight: state.trustDevice
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // 共享的外层卡片容器
                // Action chip 在 AnimatedSwitcher 外，模式切换时左右滑动
                Container(
                  width: 318,
                  height: 375,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: JxufeTheme.borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(8),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionChip(),
                      // 主体区
                      CarouselSwitcher(
                        totalItems: 2,
                        controller: _bodyCtrl,
                        isHorizontal: true,
                        distanceScale: 0.15,
                        itemBuilder: (_, i) =>
                            i == 0 ? _buildQrBody() : _buildSmsBody(),
                      ),
                      const SizedBox(height: 12),
                      // 提示条
                      CarouselSwitcher(
                        totalItems: 2,
                        controller: _hintCtrl,
                        distanceScale: 0.4,
                        itemBuilder: (_, i) =>
                            i == 0 ? _qrHintBar() : _smsHintBar(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 将顶部的模式按钮移动到卡片底部，便于先显示主要内容
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildModeButton(
                      icon: Icons.qr_code_scanner_rounded,
                      color: JxufeTheme.primaryColor,
                      active: _qrMode,
                      onTap: _qrMode ? null : _switchToQr,
                    ),
                    const SizedBox(width: 14),
                    _buildModeButton(
                      icon: ExpandIcons.wecon,
                      color: const Color(0xFF73A9EC),
                      active: !_qrMode,
                      onTap: !_qrMode ? null : _switchToSms,
                    ),
                  ],
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
