import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:smarter_jxufe/QrCode/QrCode.dart';
import 'package:smarter_jxufe/design/JxufeTheme.dart';

enum QrCodeStatus {
  loading(false), // 包括未初始化状态
  pending(false), // 待扫描
  scanned(false), // 已扫描/待验证
  cancelled(true), // 手机端已取消
  authorized(true), // 手机端已确认
  expired(true),
  error(true);

  const QrCodeStatus(this.isFinal);

  final bool isFinal;
  bool get isNotFinal => !isFinal;
}

abstract class QrCodeDisplayStrategy {
  Widget buildWidget(BuildContext context, QrCode qrCode);
}

class LoadingDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  SizedBox buildWidget(BuildContext context, QrCode qrCode) => SizedBox(
    width: 200,
    height: 200,
    child: Center(
      child: CircularProgressIndicator(color: JxufeTheme.primaryColor),
    ),
  );
}

class PendingDisplayStrategy implements QrCodeDisplayStrategy {
  static const hints = {MfaQrCode: '使用微信或者企业微信扫一扫完成验证'};

  @override
  Widget buildWidget(BuildContext context, QrCode qrCode) {
    final String? hint = hints[qrCode.runtimeType];
    final bool showHint = hint != null && hint.isNotEmpty;

    return Column(
      children: [
        Image.memory(qrCode.img, height: 200, width: 200, fit: BoxFit.contain),

        if (showHint) const SizedBox(height: 16),

        if (showHint)
          Text(
            hint,
            style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
          ),
      ],
    );
  }
}

class ScannedDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrCode qrCode) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.check_circle, color: Colors.green, size: 64),
      const SizedBox(height: 16),
      Text('已扫描', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('请在手机上确认登录', style: TextStyle(color: Colors.grey)),
      if (qrCode.verifyCode != null) const SizedBox(height: 8),
      if (qrCode.verifyCode != null)
        Text(
          '确认码: ${qrCode.verifyCode!}',
          style: TextStyle(color: Colors.grey),
        ),
    ],
  );
}

class AuthorizedDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrCode qrCode) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.done_all, color: Colors.blue, size: 64),
      const SizedBox(height: 16),
      Text('验证成功', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text('欢迎回来', style: TextStyle(color: Colors.grey.shade600)),
    ],
  );
}

class CancelledDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrCode qrCode) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.cancel, color: Colors.orange, size: 64),
      const SizedBox(height: 16),
      Text('已取消', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('请在手机上重新扫码', style: TextStyle(color: Colors.grey)),
    ],
  );
}

class ExpiredDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrCode qrCode) => Stack(
    alignment: Alignment.center,
    children: [
      ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Opacity(
          opacity: 0.5,
          child: Image.memory(
            qrCode.img,
            height: 200,
            width: 200,
            fit: BoxFit.contain,
          ),
        ),
      ),

      Column(
        children: [
          const Icon(Icons.refresh, color: JxufeTheme.secondaryColor, size: 64),
          const SizedBox(height: 16),
          Text('二维码已失效', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    ],
  );
}

class ErrorDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrCode qrCode) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.error_outline, color: Colors.red, size: 64),
      const SizedBox(height: 16),
      Text('二维码请求出错', style: Theme.of(context).textTheme.headlineSmall),
    ],
  );
}

// 策略工厂
class QrCodeDisplayStrategyFactory {
  static QrCodeDisplayStrategy createStrategy(QrCodeStatus status) {
    switch (status) {
      case QrCodeStatus.loading:
        return LoadingDisplayStrategy();
      case QrCodeStatus.pending:
        return PendingDisplayStrategy();
      case QrCodeStatus.scanned:
        return ScannedDisplayStrategy();
      case QrCodeStatus.authorized:
        return AuthorizedDisplayStrategy();
      case QrCodeStatus.cancelled:
        return CancelledDisplayStrategy();
      case QrCodeStatus.expired:
        return ExpiredDisplayStrategy();
      case QrCodeStatus.error:
        return ErrorDisplayStrategy();
    }
  }
}
