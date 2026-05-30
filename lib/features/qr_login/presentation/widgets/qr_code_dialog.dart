import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/qr_code_card.dart';

/// QR码对话框——纯UI组件
class QrCodeDialog extends StatelessWidget {
  final String title;
  final String info;

  const QrCodeDialog({
    super.key,
    required this.title,
    this.info = '',
  });

  /// 显示二维码对话框
  static Future<void> show(
    BuildContext context, {
    String title = '',
    String info = '',
  }) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(26),
      barrierDismissible: true,
      builder: (_) => QrCodeDialog(title: title, info: info),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 360),
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
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
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
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: JxufeTheme.textColor,
                        ),
                      ),
                      if (info.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          info,
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
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
