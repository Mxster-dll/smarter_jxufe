import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';

/// MFA 重登服务 — 独立于 AuthRepository 实例生命周期。
///
/// 当 AuthRepository 因 Riverpod 依赖变化被重建时，onMfaRequired 回调不会丢失。
class MfaReloginService {
  Future<void> Function(String mfaState)? _handler;

  /// 设置 MFA 验证处理器（由登录入口调用）。
  void setHandler(Future<void> Function(String mfaState) handler) {
    _handler = handler;
  }

  /// 调用 MFA 验证处理器，若未设置则尝试使用全局 navigatorKey 兜底。
  Future<void> execute(String mfaState, String account, String password) async {
    if (_handler != null) {
      await _handler!(mfaState);
      return;
    }
    // 兜底：使用全局 navigator key 和 Riverpod
    final ctx = navigatorKey.currentContext;
    if (ctx == null) throw Exception('无法获取当前页面上下文');
    // 从 ProviderScope 获取 QrLoginViewModel
    final container = ProviderScope.containerOf(ctx);
    final qrVm = container.read(qrLoginViewModelProvider.notifier);
    final result = await qrVm.unifiedMfaVerify(
      ctx,
      account,
      password,
      mfaState,
    );
    if (!result.authorized) throw Exception('用户取消 MFA 验证');
  }
}

/// 全局单例。
final mfaReloginService = MfaReloginService();
