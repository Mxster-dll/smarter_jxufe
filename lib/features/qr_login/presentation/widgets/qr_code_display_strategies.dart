import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/JxufeTheme.dart';
import 'package:smarter_jxufe/features/qr_login/domain/entities/qr_code_status.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_state.dart';

/// QR码显示策略接口
abstract interface class QrCodeDisplayStrategy {
  Widget buildWidget(BuildContext context, QrLoginState state);
}

/// 加载中
final class LoadingDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrLoginState state) =>
      CircularProgressIndicator(color: JxufeTheme.primaryColor);
}

/// 待扫描
final class PendingDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrLoginState state) {
    final showHint = state.hintText.isNotEmpty;

    return Column(
      children: [
        const SizedBox(width: 200, height: 200),
        if (showHint) const SizedBox(height: 16),
        if (showHint)
          Text(
            state.hintText,
            style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
          ),
      ],
    );
  }
}

/// 已扫描
final class ScannedDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrLoginState state) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.check_circle, color: Colors.green, size: 64),
      const SizedBox(height: 16),
      Text('已扫描', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('请在手机上确认登录', style: TextStyle(color: Colors.grey)),
      if (state.verifyCode != null) const SizedBox(height: 8),
      if (state.verifyCode != null)
        Text(
          '确认码: ${state.verifyCode!}',
          style: TextStyle(color: Colors.grey),
        ),
    ],
  );
}

/// 已验证
final class AuthorizedDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrLoginState state) => Column(
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

/// 已取消
final class CancelledDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrLoginState state) => Column(
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

/// 已过期
final class ExpiredDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrLoginState state) => Column(
    children: [
      const Icon(Icons.refresh, color: JxufeTheme.secondaryColor, size: 64),
      const SizedBox(height: 16),
      Text('二维码已失效', style: Theme.of(context).textTheme.headlineSmall),
    ],
  );
}

/// 出错
final class ErrorDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrLoginState state) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.error_outline, color: Colors.red, size: 64),
      const SizedBox(height: 16),
      Text('二维码请求出错', style: Theme.of(context).textTheme.headlineSmall),
    ],
  );
}

/// 显示策略工厂
final class QrCodeDisplayStrategyFactory {
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
