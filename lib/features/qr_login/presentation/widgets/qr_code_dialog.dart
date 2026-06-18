import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/qr_code_card.dart';

/// QR码对话框——纯UI组件
class QrCodeDialog extends StatefulWidget {
  final String title;
  final String info;
  final ValueChanged<bool>? onTrustChanged;

  const QrCodeDialog({
    super.key,
    required this.title,
    this.info = '',
    this.onTrustChanged,
  });

  /// 显示二维码对话框
  static Future<void> show(
    BuildContext context, {
    String title = '',
    String info = '',
    ValueChanged<bool>? onTrustChanged,
  }) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(26),
      barrierDismissible: true,
      builder: (_) => QrCodeDialog(
        title: title,
        info: info,
        onTrustChanged: onTrustChanged,
      ),
    );
  }

  @override
  State<QrCodeDialog> createState() => _QrCodeDialogState();
}

class _QrCodeDialogState extends State<QrCodeDialog> {
  bool _trustDevice = false;

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
                QrCodeCard(),
                const SizedBox(height: 8),
                // 信任设备复选框（紧凑）
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
