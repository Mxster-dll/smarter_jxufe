import 'package:flutter/widgets.dart';

import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/features/auth/data/auth_exception.dart';

/// MFA 处理回调：入参 [mfaState]，返回用户是否勾选「信任此设备」。
///
/// 返回值必须原样带回调用方（[AuthRepository._relogin]），否则
/// 「信任此设备」永远登记不到 CAS，每次自动重登都要重新扫码/短信验证。
typedef AuthMfaHandler = Future<bool> Function(String mfaState);

/// MFA **兜底**处理器：`_handler` 未设置时用（AuthRepository 被 Riverpod 重建后
/// 旧回调会丢，这是那之后仍能弹出验证的保险）。
///
/// ⚠ 刻意做成**注册位**（2026-09-20 · 架构审查 ⑦）：实现属于 `features/qr_login`
/// 的 UI（要弹 `unifiedMfaVerify` 对话框），而本文件在 **auth 的 data 层** ——
/// 直接 import 别家 presentation 是越界依赖（也正是 `auth ⇄ qr_login`/`ims` 环的一部分）。
/// 现在由 `features/qr_login` 提供 `installQrLoginMfaFallback()`，
/// 在 `lib/main.dart`（组装根）启动时注册。
typedef AuthMfaFallback = Future<bool> Function(
  BuildContext ctx,
  String account,
  String password,
  String mfaState,
);

/// MFA 重登服务 — 独立于 AuthRepository 实例生命周期。
///
/// 当 AuthRepository 因 Riverpod 依赖变化被重建时，onMfaRequired 回调不会丢失。
class MfaReloginService {
  AuthMfaHandler? _handler;
  AuthMfaFallback? _fallback;

  /// 设置 MFA 验证处理器（由登录入口调用）。
  void setHandler(AuthMfaHandler handler) {
    _handler = handler;
  }

  /// 注册兜底处理器（由 `features/qr_login` 在启动时调用）。
  void setFallback(AuthMfaFallback fallback) {
    _fallback = fallback;
  }

  /// 调用 MFA 验证处理器，若未设置则尝试使用全局 navigatorKey 兜底。
  ///
  /// 返回用户是否勾选「信任此设备」（供调用方登记到 CAS）。
  Future<bool> execute(String mfaState, String account, String password) async {
    if (_handler != null) {
      return _handler!(mfaState);
    }
    final fallback = _fallback;
    if (fallback == null) {
      throw AuthException('MFA 验证组件尚未就绪（未注册兜底处理器）');
    }
    final ctx = navigatorKey.currentContext;
    if (ctx == null) throw AuthException('无法获取当前页面上下文');
    return fallback(ctx, account, password, mfaState);
  }
}

/// 全局单例。
final mfaReloginService = MfaReloginService();
