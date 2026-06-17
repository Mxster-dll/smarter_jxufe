import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';

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

      // 第二步：如果需要 MFA，显示二维码
      if (mfaState.needMfa) {
        final qrViewModel = ref.read(qrLoginViewModelProvider.notifier);
        final authorized = await qrViewModel.mfaVerify(
          context,
          account,
          password,
        );

        // 用户手动关闭对话框 → 不做任何事，等用户再次点击登录
        if (!authorized) return;
      }

      // 第三步：提交登录
      final loginResult = await authRepo.login(
        account,
        password,
        mfaState.mfaState,
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
