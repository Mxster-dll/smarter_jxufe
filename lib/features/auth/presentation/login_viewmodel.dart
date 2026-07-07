import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';

import 'package:smarter_jxufe/features/auth/presentation/login_state.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';

part 'login_viewmodel.g.dart';

@riverpod
class LoginViewModel extends _$LoginViewModel {
  @override
  LoginState build() {
    return const LoginState();
  }

  void updateAccount(String value) {
    state = state.copyWith(account: value);
  }

  void updatePassword(String value) {
    state = state.copyWith(password: value);
  }

  void togglePasswordVisibility() {
    state = state.copyWith(passwordVisible: !state.passwordVisible);
  }

  Future<void> login(BuildContext context) async {
    final account = state.account.trim();
    final password = state.password.trim();

    if (account.isEmpty) {
      state = state.copyWith(
        errorMessage: '请输入校园卡号',
        errorVersion: state.errorVersion + 1,
      );
      return;
    }
    if (password.isEmpty) {
      state = state.copyWith(
        errorMessage: '请输入密码',
        errorVersion: state.errorVersion + 1,
      );
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final authRepo = await ref.read(authRepositoryProvider.future);

      // 第〇步：获取 CAS 登录页面，提取 execution 和 loginUrl
      final prepareResult = await authRepo.prepareLogin();
      if (prepareResult.isLeft()) {
        final failure = prepareResult.swap().getOrElse(
          () => UnknownFailure('??'),
        );
        state = state.copyWith(
          errorMessage: '${failure.message}',
          errorVersion: state.errorVersion + 1,
        );
        return;
      }

      // 第一步：检测是否需要 MFA
      final mfaResult = await authRepo.detectMfa(account, password);

      final mfaState = mfaResult.fold((failure) {
        state = state.copyWith(
          errorMessage: '${failure.message}',
          errorVersion: state.errorVersion + 1,
        );
        return null;
      }, (result) => result);
      if (mfaState == null) return; // detectMfa 失败

      // 第二步：如果需要 MFA（扫码/短信可切换）
      String? trustAgent;
      if (mfaState.needMfa) {
        final qrViewModel = ref.read(qrLoginViewModelProvider.notifier);
        final isDesktop =
            defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android;
        final result = await qrViewModel.unifiedMfaVerify(
          context,
          account,
          password,
          mfaState.mfaState,
          startInQrMode: isDesktop,
        );

        // 用户手动关闭对话框 → 不做任何事，等用户再次点击登录
        if (!result.authorized) return;
        trustAgent = result.trustDevice ? 'true' : '';
      }

      // 第三步：提交登录
      final loginResult = await authRepo.login(
        account,
        password,
        mfaState.mfaState,
        trustAgent: trustAgent ?? '',
      );

      final loginSuccess = loginResult.fold((failure) {
        if (failure is InvalidCredentialsFailure) {
          state = state.copyWith(
            errorMessage: '账号或密码错误',
            errorVersion: state.errorVersion + 1,
          );
        } else {
          state = state.copyWith(
            errorMessage: '登录失败: ${failure.message}',
            errorVersion: state.errorVersion + 1,
          );
        }
        return false;
      }, (_) => true);

      if (loginSuccess) {
        // 登录成功 → 加密保存账号（先存再跳转）
        final accountRepo = await ref.read(accountRepositoryProvider.future);
        await accountRepo.saveAccount(
          Account(cardNumber: account, password: password),
        );
        // 更新当前账户 Provider（驱动 Dio 切换）
        ref.read(currentAccountProvider.notifier).state = account;
        // 刷新学生信息并更新账户显示名称
        final studentInfoRepo = await ref.read(
          studentInfoRepositoryProvider.future,
        );
        final infoResult = await studentInfoRepo.getStudentInfo(
          forceRefresh: true,
        );
        infoResult.fold(
          (_) => null,
          (info) => accountRepo.updateDisplayName(account, info.name),
        );
        state = state.copyWith(loginSuccess: true);
      }
    } catch (e) {
      state = state.copyWith(
        errorMessage: '登录失败: $e',
        errorVersion: state.errorVersion + 1,
      );
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  void scanLogin(BuildContext context) {
    ref.read(qrLoginViewModelProvider.notifier).scanLogin(context);
  }

  void wechatLogin(BuildContext context) {
    ref.read(qrLoginViewModelProvider.notifier).wechatLogin(context);
  }

  void showWecomUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暂未开放企业微信登录'), backgroundColor: Colors.red),
    );
  }
}

/// 调试开关：电脑端强制使用手机验证码 MFA。
/// 改为 [true] 后在 Windows/macOS 上也会走手机验证码流程。
const _debugForceMobileMfa = false;

/// 判断当前是否为手机平台。
/// 电脑端可通过窗口宽度 < 600 模拟手机模式。
bool _isMobilePlatform(BuildContext context) {
  if (_debugForceMobileMfa) return true;
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android) {
    return true;
  }
  // 桌面端窗口较窄时也走手机模式（方便调试）
  final size = MediaQuery.of(context).size;
  return size.width < 600;
}
