import 'package:flutter/material.dart';

import 'QrCode.dart';

class QrCodeCard extends StatefulWidget {
  final String tips;

  static const Color _primaryColor = Color(0xFFC3282E);
  static const Color _secondaryColor = Color(0xFF8B0000);
  static const Color _backgroundColor = Color(0xFFF5F5F5);
  static const Color _inputBgColor = Color(0xFFF8F8F8);
  static const Color _borderColor = Color(0xFFE0E0E0);
  static const Color _textColor = Color(0xFF333333);
  static const Color _hintColor = Color(0xFF999999);

  const QrCodeCard({super.key, this.tips = ''});

  @override
  State<QrCodeCard> createState() => _QrCodeState();

  static void showQrCodeDialog(
    BuildContext context,
    QrCode qrcode, {
    required String title,
    required String info,
  }) => showDialog(
    context: context,
    barrierColor: Colors.black.withAlpha(0x1A), // 半透明背景
    barrierDismissible: true, // 点击背景关闭
    builder: (context) => _buildQrCodeDialog(qrcode, title, info),
  );

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
              color: Colors.black.withAlpha(0x26),
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
                        color: _primaryColor,
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
                        color: _textColor,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      info,
                      style: TextStyle(fontSize: 13, color: _hintColor),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // 二维码卡片
              QrCodeCard(tips: '使用微信或者企业微信扫一扫完成验证'),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCodeState extends State<QrCodeCard> {
  QrCode? qrCode;

  static const Color _primaryColor = Color(0xFFC3282E);
  static const Color _secondaryColor = Color(0xFF8B0000);
  static const Color _backgroundColor = Color(0xFFF5F5F5);
  static const Color _inputBgColor = Color(0xFFF8F8F8);
  static const Color _borderColor = Color(0xFFE0E0E0);
  static const Color _textColor = Color(0xFF333333);
  static const Color _hintColor = Color(0xFF999999);

  @override
  Container build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _inputBgColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _borderColor),
    ),
    child: Column(
      children: [
        qrCode == null || qrCode!.isLoading
            ? const SizedBox(
                height: 200,
                width: 200,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Image.memory(
                qrCode!.img!,
                height: 200,
                width: 200,
                fit: BoxFit.contain,
              ),

        if (widget.tips.isNotEmpty) const SizedBox(height: 16),

        if (widget.tips.isNotEmpty)
          Text(widget.tips, style: TextStyle(fontSize: 13, color: _hintColor)),
      ],
    ),
  );
}
