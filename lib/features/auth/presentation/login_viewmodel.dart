import 'dart:io';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:smarter_jxufe/core/errors/failures.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';

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
    var account = state.account.trim();
    var password = state.password.trim();

    // 从临时文件读取测试账号（仅开发调试）
    try {
      final file = File('tmp.txt');
      final lines = file.readAsLinesSync();
      if (lines.length >= 2) {
        if (account.isEmpty) account = lines[0];
        if (password.isEmpty) password = lines[1];
      }
    } catch (_) {}

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

      while (true) {
        final result = await authRepo.login(account, password);

        final shouldExit = result.fold(
          (failure) {
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
            return true; // 失败，退出循环
          },
          (needMfa) {
            if (!needMfa) {
              // 302 登录成功，无需 MFA
              state = state.copyWith(loginSuccess: true);
              return true; // 成功，退出循环
            }
            return false; // needMfa，继续循环
          },
        );

        if (shouldExit) return;

        // 需要 MFA 验证：显示二维码，等待完成后重试登录
        final qrViewModel = ref.read(qrLoginViewModelProvider.notifier);
        await qrViewModel.mfaVerify(context, account, password);
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
