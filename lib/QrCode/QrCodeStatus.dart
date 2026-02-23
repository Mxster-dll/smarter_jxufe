import 'package:flutter/material.dart';

import 'package:smarter_jxufe/QrCode/QrCode.dart';
import 'package:smarter_jxufe/Services/MfaService.dart';
import 'package:smarter_jxufe/Services/ScanLogin.dart';
import 'package:smarter_jxufe/Services/WechatLogin.dart';
import 'package:smarter_jxufe/design/JxufeTheme.dart';

enum QrCodeStatus {
  loading, // 包括未初始化状态
  pending, // 待扫描
  scanned, // 已扫描/待验证
  cancelled, // 手机端已取消
  authorized, // 手机端已确认
  expired, // 失效
  error;

  bool get isFinal => !isNotFinal;
  bool get isNotFinal =>
      this == .loading || this == .pending || this == .scanned;
}

abstract class QrCodeDisplayStrategy {
  Widget buildWidget(BuildContext context, QrCode qrCode);
}

class LoadingDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  buildWidget(BuildContext context, QrCode qrCode) =>
      CircularProgressIndicator(color: JxufeTheme.primaryColor);
}

class PendingDisplayStrategy implements QrCodeDisplayStrategy {
  static const hints = {
    MfaService: '使用微信或者企业微信扫一扫完成验证',
    ScanLogin: '使用微信或者企业微信扫一扫登录',
    WeChatLogin: '使用微信扫一扫登录',
  };

  @override
  Widget buildWidget(BuildContext context, QrCode qrCode) {
    final String? hint = hints[qrCode.networkService.runtimeType];
    final bool showHint = hint != null && hint.isNotEmpty;

    return Column(
      children: [
        const SizedBox(width: 200, height: 200),

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
  Widget buildWidget(BuildContext context, QrCode qrCode) => Column(
    children: [
      const Icon(Icons.refresh, color: JxufeTheme.secondaryColor, size: 64),
      const SizedBox(height: 16),
      Text('二维码已失效', style: Theme.of(context).textTheme.headlineSmall),
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

class QrCodeDisplayStrategyFactory {
  static QrCodeDisplayStrategy createStrategy(QrCodeStatus status) =>
      switch (status) {
        QrCodeStatus.loading => LoadingDisplayStrategy(),
        QrCodeStatus.pending => PendingDisplayStrategy(),
        QrCodeStatus.scanned => ScannedDisplayStrategy(),
        QrCodeStatus.authorized => AuthorizedDisplayStrategy(),
        QrCodeStatus.cancelled => CancelledDisplayStrategy(),
        QrCodeStatus.expired => ExpiredDisplayStrategy(),
        QrCodeStatus.error => ErrorDisplayStrategy(),
      };
}
