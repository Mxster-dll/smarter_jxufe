import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:smarter_jxufe/features/auth/presentation/login_state.dart';
import 'package:smarter_jxufe/old/login/MfaService.dart';
import 'package:smarter_jxufe/qrCode/QrCodeService.dart';

part 'login_viewmodel.g.dart';

@riverpod
class LoginViewModel extends _$LoginViewModel {
  late final MfaService _mfaService;
  late final ScanLogin _scanLoginService;
  late final WeChatLogin _wechatLoginService;
  final Dio _dio = Dio();

  @override
  LoginState build() {
    _mfaService = MfaService(_dio);
    _scanLoginService = ScanLogin(_dio);
    _wechatLoginService = WeChatLogin();
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
    // final account = state.account.trim();
    // final password = state.password.trim();

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

    _mfaService.set(account, password);
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      await _mfaService.process(context);

      state = state.copyWith(loginSuccess: true);
    } catch (e) {
      state = state.copyWith(errorMessage: '登录失败: $e');
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  void scanLogin(BuildContext context) {
    _scanLoginService.process(context);
  }

  void wechatLogin(BuildContext context) {
    _wechatLoginService.process(context);
  }

  void showWecomUnavailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('暂未开放企业微信登录'), backgroundColor: Colors.red),
    );
  }
}
