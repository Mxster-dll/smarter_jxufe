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
      state = state.copyWith(errorMessage: '请输入校园卡号');
      return;
    }
    if (password.isEmpty) {
      state = state.copyWith(errorMessage: '请输入密码');
      return;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final authRepo = await ref.read(authRepositoryProvider.future);
      final result = await authRepo.login(account, password);

      result.fold(
        (failure) {
          if (failure is InvalidCredentialsFailure) {
            state = state.copyWith(errorMessage: '账号或密码错误');
          } else {
            state = state.copyWith(errorMessage: '登录失败: ${failure.message}');
          }
        },
        (needMfa) async {
          if (needMfa) {
            final qrViewModel = ref.read(qrLoginViewModelProvider.notifier);
            await qrViewModel.mfaVerify(context, account, password);
          }
          state = state.copyWith(loginSuccess: true);
        },
      );
    } catch (e) {
      state = state.copyWith(errorMessage: '登录失败: $e');
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
