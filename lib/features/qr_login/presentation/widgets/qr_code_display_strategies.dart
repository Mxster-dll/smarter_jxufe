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
  Widget buildWidget(BuildContext context, QrLoginState state) => Center(
    child: SizedBox(
      width: 32,
      height: 32,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: JxufeTheme.primaryColor,
      ),
    ),
  );
}

/// 待扫描
final class PendingDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrLoginState state) {
    final showHint = state.hintText.isNotEmpty;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (showHint)
          Text(
            state.hintText,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).hintColor,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
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
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.green.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.check_circle_rounded,
          color: Colors.green,
          size: 40,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '已扫描',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      const Text(
        '请在手机上确认登录',
        style: TextStyle(color: JxufeTheme.hintColor, fontSize: 13),
      ),
      if (state.verifyCode != null) const SizedBox(height: 6),
      if (state.verifyCode != null)
        Text(
          '确认码: ${state.verifyCode!}',
          style: const TextStyle(color: JxufeTheme.hintColor, fontSize: 12),
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
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.blue.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.done_all_rounded, color: Colors.blue, size: 36),
      ),
      const SizedBox(height: 16),
      Text(
        '验证成功',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text('欢迎回来', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
    ],
  );
}

/// 已取消
final class CancelledDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrLoginState state) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.orange.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.cancel_outlined,
          color: Colors.orange,
          size: 40,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '已取消',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      const Text(
        '请在手机上重新扫码',
        style: TextStyle(color: JxufeTheme.hintColor, fontSize: 13),
      ),
    ],
  );
}

/// 已过期
final class ExpiredDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrLoginState state) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: JxufeTheme.secondaryColor.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.refresh_rounded,
          color: JxufeTheme.secondaryColor,
          size: 40,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '二维码已失效',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

/// 出错
final class ErrorDisplayStrategy implements QrCodeDisplayStrategy {
  @override
  Widget buildWidget(BuildContext context, QrLoginState state) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.error_outline_rounded,
          color: Colors.red,
          size: 40,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '二维码请求出错',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
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
