import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/Icons.dart';
import 'package:smarter_jxufe/design/JxufeTheme.dart';

/// 手机验证码 MFA 对话框。
///
/// 显示掩码手机号，用户点击"发送验证码"后输入验证码并提交。
class MobileMfaDialog extends StatefulWidget {
  final String title;
  final String info;
  final String phoneNumber;
  final ValueChanged<bool>? onTrustChanged;
  final Future<void> Function() onSendCode;
  final Future<bool> Function(String code) onValidate;

  const MobileMfaDialog({
    super.key,
    required this.title,
    this.info = '',
    required this.phoneNumber,
    this.onTrustChanged,
    required this.onSendCode,
    required this.onValidate,
  });

  /// 显示手机验证码对话框，返回 (是否验证成功, 是否信任设备)
  static Future<({bool authorized, bool trustDevice})> show(
    BuildContext context, {
    String title = '',
    String info = '',
    required String phoneNumber,
    required Future<void> Function() onSendCode,
    required Future<bool> Function(String code) onValidate,
  }) async {
    bool trustDevice = false;
    bool authorized = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => MobileMfaDialog(
          title: title,
          info: info,
          phoneNumber: phoneNumber,
          onTrustChanged: (v) => trustDevice = v,
          onSendCode: onSendCode,
          onValidate: (code) async {
            final ok = await onValidate(code);
            if (ok) authorized = true;
            return ok;
          },
        ),
      ),
    );

    return (authorized: authorized, trustDevice: trustDevice);
  }

  @override
  State<MobileMfaDialog> createState() => _MobileMfaDialogState();
}

class _MobileMfaDialogState extends State<MobileMfaDialog> {
  bool _trustDevice = false;
  bool _sending = false;
  bool _codeSent = false;
  bool _validating = false;
  int _countdown = 0;
  final _codeController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _sending = true;
      _errorText = null;
    });

    try {
      await widget.onSendCode();
      setState(() {
        _codeSent = true;
        _countdown = 60;
      });
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
                // 企业微信图标
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF73A9EC),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    ExpandIcons.wecon,
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
                  ),
                ),
                if (widget.info.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.info,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),

                // 企业微信验证提示
                const Text('使用企业微信验证', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                const Text(
                  '请在企业微信查看消息验证码',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),

                // 验证码输入 + 发送按钮
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

                // 信任设备复选框
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
                        '登录成功后，设为可信客户端',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 确定按钮
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
            ),
          ),
        ),
      ),
    );
  }
}
