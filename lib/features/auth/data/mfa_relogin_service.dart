import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';

/// MFA 处理回调：入参 [mfaState]，返回用户是否勾选「信任此设备」。
///
/// 返回值必须原样带回调用方（[AuthRepository._relogin]），否则
/// 「信任此设备」永远登记不到 CAS，每次自动重登都要重新扫码/短信验证。
typedef AuthMfaHandler = Future<bool> Function(String mfaState);

/// MFA 重登服务 — 独立于 AuthRepository 实例生命周期。
///
/// 当 AuthRepository 因 Riverpod 依赖变化被重建时，onMfaRequired 回调不会丢失。
class MfaReloginService {
  AuthMfaHandler? _handler;

  /// 设置 MFA 验证处理器（由登录入口调用）。
  void setHandler(AuthMfaHandler handler) {
    _handler = handler;
  }

  /// 调用 MFA 验证处理器，若未设置则尝试使用全局 navigatorKey 兜底。
  ///
  /// 返回用户是否勾选「信任此设备」（供调用方登记到 CAS）。
  Future<bool> execute(String mfaState, String account, String password) async {
    if (_handler != null) {
      return _handler!(mfaState);
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
    return result.trustDevice;
  }
}

/// 全局单例。
final mfaReloginService = MfaReloginService();
