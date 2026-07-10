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
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 图标 —— 企业微信品牌色圆形背景
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF73A9EC),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF73A9EC).withAlpha(50),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    ExpandIcons.wecon,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 16),
                // 标题
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: JxufeTheme.textColor,
                    letterSpacing: -0.3,
                  ),
                ),
                if (widget.info.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.info,
                    style: const TextStyle(
                      fontSize: 13,
                      color: JxufeTheme.hintColor,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),

                // 提示：使用企业微信验证
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF73A9EC).withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        ExpandIcons.wecon,
                        size: 18,
                        color: Color(0xFF73A9EC),
                      ),
                      const SizedBox(width: 8),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: '使用 ',
                              style: TextStyle(
                                fontSize: 13,
                                color: JxufeTheme.textColor,
                              ),
                            ),
                            const TextSpan(
                              text: '企业微信',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF73A9EC),
                              ),
                            ),
                            const TextSpan(
                              text: ' 查看验证码',
                              style: TextStyle(
                                fontSize: 13,
                                color: JxufeTheme.textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 验证码输入 + 发送按钮
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        style: const TextStyle(
                          fontSize: 16,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: '请输入验证码',
                          counterText: '',
                          errorText: _errorText,
                          errorMaxLines: 2,
                          filled: true,
                          fillColor: JxufeTheme.inputBgColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: JxufeTheme.borderColor,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF73A9EC),
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.red),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Colors.red,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: (_sending || _countdown > 0)
                            ? null
                            : _sendCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF73A9EC),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(
                            0xFF73A9EC,
                          ).withAlpha(100),
                          disabledForegroundColor: Colors.white70,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: Text(
                          _sending
                              ? '发送中…'
                              : _countdown > 0
                              ? '${_countdown}s'
                              : '发送验证码',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 信任设备
                Center(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _trustDevice = !_trustDevice);
                      widget.onTrustChanged?.call(_trustDevice);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _trustDevice
                            ? JxufeTheme.primaryColor
                            : JxufeTheme.inputBgColor,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: _trustDevice
                              ? JxufeTheme.primaryColor
                              : JxufeTheme.borderColor,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _trustDevice
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            size: 16,
                            color: _trustDevice
                                ? Colors.white
                                : JxufeTheme.hintColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '设为信任设备',
                            style: TextStyle(
                              fontSize: 13,
                              color: _trustDevice
                                  ? Colors.white
                                  : JxufeTheme.textColor,
                              fontWeight: _trustDevice
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 确定按钮
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _validating ? null : _validate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: JxufeTheme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: JxufeTheme.primaryColor
                          .withAlpha(150),
                      disabledForegroundColor: Colors.white70,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Text(
                      _validating ? '验证中…' : '确定',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
