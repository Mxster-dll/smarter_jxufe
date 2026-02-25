import 'package:flutter/material.dart';

import 'package:smarter_jxufe/qrCode/QrCode.dart';
import 'package:smarter_jxufe/qrCode/QrCodeStatus.dart';
import 'package:smarter_jxufe/design/JxufeTheme.dart';

// BUG 如果点击微信登录（其他也一样）选项过快，可能导致两个dialog被显示
class QrCodeCard extends StatefulWidget {
  final String tips;
  final QrCode qrCode;

  const QrCodeCard(this.qrCode, {super.key, this.tips = ''});

  @override
  State<QrCodeCard> createState() => _QrCodeState();

  static void showQrCodeDialog(
    BuildContext context,
    QrCode qrcode, {
    String title = '',
    String info = '',
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
      insetPadding: const .symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 360),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: .circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(38),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const .all(24),
            child: Column(
              mainAxisSize: .min,
              children: [
                Container(
                  margin: const .only(bottom: 20),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: JxufeTheme.primaryColor,
                          borderRadius: .circular(20),
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: .bold,
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
                        textAlign: .center,
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
    const double sideLength = 200;
    return StreamBuilder<QrCodeStatus>(
      stream: qrCode.stateStream,
      builder: (context, snapshot) {
        final state = snapshot.data ?? qrCode.status;
        final strategy = QrCodeDisplayStrategyFactory.createStrategy(state);

        return Container(
          padding: const .all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: .circular(12),
            border: Border.all(color: JxufeTheme.borderColor),
            // boxShadow: [
            //   BoxShadow(
            //     color: Colors.grey.withAlpha(51),
            //     blurRadius: 10,
            //     spreadRadius: 2,
            //   ),
            // ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: sideLength,
              minHeight: sideLength,
            ),
            child: Column(
              mainAxisAlignment: .center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(state),
                    child: Stack(
                      alignment: .topCenter,
                      children: [
                        if (!qrCode.isLoading)
                          ImageFiltered(
                            imageFilter: .blur(
                              sigmaX: qrCode.isPending ? 0 : 5,
                              sigmaY: qrCode.isPending ? 0 : 5,
                            ),
                            child: Opacity(
                              opacity: qrCode.isPending ? 1 : 0.5,
                              child: Image.memory(
                                qrCode.img,
                                height: sideLength,
                                width: sideLength,
                                fit: .contain,
                              ),
                            ),
                          ),

                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: sideLength,
                            minHeight: sideLength,
                          ),
                          child: Center(
                            widthFactor: 1,
                            heightFactor: 1,
                            child: strategy.buildWidget(context, qrCode),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (qrCode.status.isFinal) const SizedBox(height: 12),

                if (qrCode.status.isFinal)
                  OutlinedButton(
                    onPressed: qrCode.refresh,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: JxufeTheme.secondaryColor,
                        width: 1,
                      ),
                    ),
                    child: const Text(
                      '刷新',
                      style: TextStyle(color: JxufeTheme.secondaryColor),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
