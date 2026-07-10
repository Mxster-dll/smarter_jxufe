import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/widgets/qr_code_card.dart';

/// QR码对话框——纯UI组件
class QrCodeDialog extends ConsumerWidget {
  final String title;
  final String info;

  const QrCodeDialog({super.key, required this.title, this.info = ''});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(qrLoginViewModelProvider);
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
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 图标
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: JxufeTheme.primaryColor,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: JxufeTheme.primaryColor.withAlpha(50),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: JxufeTheme.textColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (info.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          info,
                          style: const TextStyle(
                            fontSize: 13,
                            color: JxufeTheme.hintColor,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
                const QrCodeCard(),
                const SizedBox(height: 12),
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
            ),
          ),
        ),
      ),
    );
  }
}
