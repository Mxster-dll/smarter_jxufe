import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/qr_code_card.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/account_screen.dart';

/// 统一 MFA 对话框 — 支持扫码验证和短信验证码切换。
class UnifiedMfaDialog extends StatefulWidget {
  final String title;
  final String info;
  final bool startInQrMode;
  final Uint8List? Function() getQrImage;
  final Stream<QrCodeStatus> qrStatusStream;
  final Future<void> Function() onSwitchToQr;
  final Future<String> Function() onSwitchToSms;
  final Future<void> Function() onSendCode;
  final Future<bool> Function(String code) onValidate;
  final VoidCallback? onQrAuthorized;
  final ValueChanged<bool>? onTrustChanged;
  final bool showSwitchAccount;

  const UnifiedMfaDialog({
    super.key,
    required this.title,
    this.info = '',
    this.startInQrMode = true,
    required this.getQrImage,
    required this.qrStatusStream,
    required this.onSwitchToQr,
    required this.onSwitchToSms,
    required this.onSendCode,
    required this.onValidate,
    this.onQrAuthorized,
    this.onTrustChanged,
    this.showSwitchAccount = true,
  });

  static Future<({bool authorized, bool trustDevice})> show(
    BuildContext context, {
    String title = '',
    String info = '',
    bool startInQrMode = true,
    required Uint8List? Function() getQrImage,
    required Stream<QrCodeStatus> qrStatusStream,
    required Future<void> Function() onSwitchToQr,
    required Future<String> Function() onSwitchToSms,
    required Future<void> Function() onSendCode,
    required Future<bool> Function(String code) onValidate,
    bool showSwitchAccount = true,
  }) async {
    bool trustDevice = false;
    bool authorized = false;

    try {
      await showDialog(
        context: context,
        barrierColor: Colors.black.withAlpha(26),
        barrierDismissible: true,
        builder: (_) => UnifiedMfaDialog(
          title: title,
          info: info,
          startInQrMode: startInQrMode,
          showSwitchAccount: showSwitchAccount,
          getQrImage: getQrImage,
          qrStatusStream: qrStatusStream,
          onSwitchToQr: onSwitchToQr,
          onSwitchToSms: onSwitchToSms,
          onSendCode: onSendCode,
          onValidate: (code) async {
            final ok = await onValidate(code);
            if (ok) authorized = true;
            return ok;
          },
          onQrAuthorized: () => authorized = true,
          onTrustChanged: (v) => trustDevice = v,
        ),
      );
    } catch (_) {
      // 对话框内部异常（如在关闭过程中异步回调访问已销毁的 Widget）
      // → 静默吞掉，返回未授权状态
    }
    return (authorized: authorized, trustDevice: trustDevice);
  }

  @override
  State<UnifiedMfaDialog> createState() => _UnifiedMfaDialogState();
}

class _UnifiedMfaDialogState extends State<UnifiedMfaDialog> {
  bool _qrMode = true;
  bool _switching = false;
  StreamSubscription<QrCodeStatus>? _qrSub;
  bool _dismissed = false;

  bool _trustDevice = false;
  bool _sending = false;
  bool _validating = false;
  int _countdown = 0;
  final _codeController = TextEditingController();
  String? _errorText;
  String _phoneHint = '';

  @override
  void initState() {
    super.initState();
    _qrMode = widget.startInQrMode;
    _listenQrStatus();
  }

  void _listenQrStatus() {
    _qrSub?.cancel();
    _qrSub = widget.qrStatusStream.listen(
      (status) {
        if (!mounted || _dismissed) return;
        try {
          if (status == QrCodeStatus.authorized) {
            widget.onQrAuthorized?.call();
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted && !_dismissed) Navigator.of(context).pop();
            });
          }
        } catch (_) {}
      },
      onError: (_) {}, // 流错误静默处理
    );
  }

  @override
  void dispose() {
    _dismissed = true;
    _qrSub?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _switchMode() async {
    if (_dismissed) return;
    setState(() => _switching = true);
    try {
      if (_qrMode) {
        _phoneHint = await widget.onSwitchToSms();
        if (_dismissed) return;
        _qrMode = false;
      } else {
        await widget.onSwitchToQr();
        if (_dismissed) return;
        _qrMode = true;
        _listenQrStatus();
      }
    } finally {
      if (mounted && !_dismissed) setState(() => _switching = false);
    }
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
      setState(() => _sending = false);
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
    final code = _codeController.text.trim();
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: IntrinsicWidth(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(38),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: JxufeTheme.primaryColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: JxufeTheme.textColor,
                        ),
                      ),
                      if (widget.info.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          widget.info,
                          style: const TextStyle(
                            fontSize: 13,
                            color: JxufeTheme.hintColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),

                if (_qrMode)
                  const QrCodeCard()
                else ...[
                  if (_phoneHint.isNotEmpty) ...[
                    const Text('使用企业微信验证', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 4),
                    const Text(
                      '请在企业微信查看消息验证码',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: InputDecoration(
                            hintText: '请输入验证码',
                            counterText: '',
                            errorText: _errorText,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          onPressed: (_sending || _countdown > 0)
                              ? null
                              : _sendCode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: JxufeTheme.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            _sending
                                ? '发送中…'
                                : _countdown > 0
                                ? '${_countdown}s'
                                : '发送验证码',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _validating ? null : _validate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JxufeTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_validating ? '验证中…' : '确定'),
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _trustDevice,
                        activeColor: Theme.of(context).colorScheme.error,
                        checkColor: Theme.of(context).colorScheme.onError,
                        onChanged: (v) {
                          setState(() => _trustDevice = v ?? false);
                          widget.onTrustChanged?.call(_trustDevice);
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        setState(() => _trustDevice = !_trustDevice);
                        widget.onTrustChanged?.call(_trustDevice);
                      },
                      child: const Text(
                        '设为信任设备',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _switching ? null : _switchMode,
                  icon: Icon(
                    _qrMode ? Icons.sms : Icons.qr_code_scanner,
                    size: 18,
                  ),
                  label: Text(
                    _switching
                        ? '切换中…'
                        : _qrMode
                        ? '切换到短信验证'
                        : '切换到扫码验证',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (widget.showSwitchAccount) ...[
                  const Divider(height: 24),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AccountScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      '切换账户',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
