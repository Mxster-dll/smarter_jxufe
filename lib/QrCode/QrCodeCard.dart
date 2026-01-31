import 'package:flutter/material.dart';

import 'package:smarter_jxufe/QrCode/QrCode.dart';
import 'package:smarter_jxufe/QrCode/QrCodeStatus.dart';
import 'package:smarter_jxufe/design/JxufeTheme.dart';

class QrCodeCard extends StatefulWidget {
  final String tips;
  final QrCode qrCode;

  const QrCodeCard(this.qrCode, {super.key, this.tips = ''});

  @override
  State<QrCodeCard> createState() => _QrCodeState();

  static void showQrCodeDialog(
    BuildContext context,
    QrCode qrcode, {
    required String title,
    required String info,
  }) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(26), // 半透明背景
      barrierDismissible: true, // 点击背景关闭
      builder: (context) => _buildQrCodeDialog(qrcode, title, info),
    );
    qrcode.stopPolling();
  }

  static Dialog _buildQrCodeDialog(QrCode qrCode, String title, String info) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
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
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: JxufeTheme.textColor,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      info,
                      style: TextStyle(
                        fontSize: 13,
                        color: JxufeTheme.hintColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // 二维码卡片
              QrCodeCard(qrCode),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCodeState extends State<QrCodeCard> {
  late final QrCode qrCode;

  @override
  void initState() {
    super.initState();
    qrCode = widget.qrCode;
  }

  @override
  void dispose() {
    qrCode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QrCodeStatus>(
      stream: qrCode.stateStream,
      builder: (context, snapshot) {
        final state = snapshot.data ?? qrCode.status;
        final strategy = QrCodeDisplayStrategyFactory.createStrategy(state);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: JxufeTheme.inputBgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JxufeTheme.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withAlpha(51),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(state),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: 200, minHeight: 200),
                child: strategy.buildWidget(context, qrCode),
              ),
            ),
          ),
        );
      },
    );
  }
}
