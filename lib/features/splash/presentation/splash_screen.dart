import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/storage/hive_initializer.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_screen.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();

    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await HiveInitializer.init();

    await Future.delayed(const Duration(milliseconds: 500));

    try {
      // 读取本地存储的账号
      final accountRepo = await ref.read(accountRepositoryProvider.future);
      final accountResult = await accountRepo.getAccount();
      final account = accountResult.fold((_) => null, (a) => a);

      if (account == null) {
        _goToLogin();
        return;
      }

      // 有本地账号 → 尝试自动登录
      final authRepo = await ref.read(authRepositoryProvider.future);

      // 第一步：检测 MFA
      final mfaResult = await authRepo.detectMfa(
        account.cardNumber,
        account.password,
      );

      final mfaState = mfaResult.fold((failure) {
        _showErrorThenLogin('${failure.message}');
        return null;
      }, (result) => result);
      if (mfaState == null) {
        // detectMfa 失败 → 显示错误后跳转登录页
        return;
      }

      // 需要 MFA → 显示二维码（复用 login_viewmodel 的逻辑）
      if (mfaState.needMfa) {
        if (!mounted) return;
        final qrViewModel = ref.read(qrLoginViewModelProvider.notifier);
        final authorized = await qrViewModel.mfaVerify(
          context,
          account.cardNumber,
          account.password,
        );
        if (!authorized) {
          // 用户手动关闭 → 跳转登录页
          _goToLogin();
          return;
        }
      }

      // 第二步：直接登录（无需 MFA）
      final loginResult = await authRepo.login(
        account.cardNumber,
        account.password,
        mfaState.mfaState,
      );

      loginResult.fold((failure) => _goToLogin(), (_) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ImsSplashScreen()),
          );
        }
      });
    } catch (e) {
      _goToLogin();
    }
  }

  void _showErrorThenLogin(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('自动登录失败'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _goToLogin();
            },
            child: const Text('前往登录'),
          ),
        ],
      ),
    );
  }

  void _goToLogin() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: .center,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('加载中...'),
          ],
        ),
      ),
    );
  }
}
