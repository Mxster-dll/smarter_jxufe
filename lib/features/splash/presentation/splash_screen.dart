import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/core/storage/hive_initializer.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_screen.dart';
      // TODO 此行验证登录状态（修改密码的情况）并隔一阵子就验证密码（可选）
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';

      // TODO 这个地方逻辑要大改，如何从后端验证，什么时候进登录页，什么时候尝试重新获取tgc
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
      final accountRepo = await ref.read(accountRepositoryProvider.future);
      final accountResult = accountRepo.getCurrentAccount();
      final account = accountResult.fold((_) => null, (a) => a);

      if (account == null) {
        _goToLogin();
        return;
      }

      ref.read(currentAccountProvider.notifier).state = account.cardNumber;

      final authRepo = await ref.read(authRepositoryProvider.future);

      final mfaResult = await authRepo.detectMfa(
        account.cardNumber,
        account.password,
      );

      final mfaState = mfaResult.fold((failure) {
        _showErrorThenLogin('${failure.message}');
        return null;
      }, (result) => result);
      if (mfaState == null) {
        return;
      }

      String? trustAgent;
      if (mfaState.needMfa) {
        if (!mounted) return;
        final qrViewModel = ref.read(qrLoginViewModelProvider.notifier);
        final result = await qrViewModel.mfaVerify(
          context,
          account.cardNumber,
          account.password,
        );
        if (!result.authorized) {
          _goToLogin();
          return;
        }
        trustAgent = result.trustDevice ? 'true' : '';
      }

      final loginResult = await authRepo.login(
        account.cardNumber,
        account.password,
        mfaState.mfaState,
        trustAgent: trustAgent ?? '',
      );

      loginResult.fold((failure) => _goToLogin(), (_) async {
        final studentInfoRepo = await ref.read(
          studentInfoRepositoryProvider.future,
        );
        final accountRepo = await ref.read(accountRepositoryProvider.future);
        final infoResult = await studentInfoRepo.getStudentInfo(
          forceRefresh: true,
        );
        infoResult.fold(
          (_) => null,
          (info) =>
              accountRepo.updateDisplayName(account.cardNumber, info.name),
        );
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
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: theme.colorScheme.error),
            const SizedBox(height: 16),
            const Text('加载中...'),
          ],
        ),
      ),
    );
  }
}
