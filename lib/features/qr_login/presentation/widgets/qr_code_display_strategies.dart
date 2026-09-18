import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
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
        color: Theme.of(context).colorScheme.primary,
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
          color: AppColors.successFill(context),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.check_circle_rounded,
          color: AppColors.success(context),
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
      Text(
        '请在手机上确认登录',
        style: TextStyle(color: AppColors.textMuted(context), fontSize: 13),
      ),
      if (state.verifyCode != null) const SizedBox(height: 6),
      if (state.verifyCode != null)
        Text(
          '确认码: ${state.verifyCode!}',
          style: TextStyle(color: AppColors.textMuted(context), fontSize: 12),
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
          color: AppColors.infoFill(context),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.done_all_rounded,
          color: AppColors.info(context),
          size: 36,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '验证成功',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(
        '欢迎回来',
        style: TextStyle(color: AppColors.textMuted(context), fontSize: 13),
      ),
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
          color: AppColors.cautionFill(context),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.cancel_outlined,
          color: AppColors.caution(context),
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
      Text(
        '请在手机上重新扫码',
        style: TextStyle(color: AppColors.textMuted(context), fontSize: 13),
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
          color: AppColors.tint(
            context,
            Theme.of(context).colorScheme.primary,
            20 / 255,
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.refresh_rounded,
          color: Theme.of(context).colorScheme.primary,
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
          color: AppColors.criticalFill(context),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.error_outline_rounded,
          color: AppColors.critical(context),
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
