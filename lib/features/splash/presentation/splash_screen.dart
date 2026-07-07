import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/core/storage/hive_initializer.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/platform/presentation/platform_selection_screen.dart';
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
      final accountResult = accountRepo.getCurrentAccount();
      final account = accountResult.fold((_) => null, (a) => a);

      if (account == null) {
        _goToLogin();
        return;
      }

      // 初始化当前账户 Provider
      ref.read(currentAccountProvider.notifier).state = account.cardNumber;

      // 有本地账号 → 尝试自动登录
      final authRepo = await ref.read(authRepositoryProvider.future);

      // 第〇步：预请求 CAS 登录页面
      final prepareResult = await authRepo.prepareLogin();
      if (prepareResult.isLeft()) {
        final msg = prepareResult.fold((f) => f.message ?? '未知错误', (_) => '');
        _showErrorThenLogin(msg);
        return;
      }

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

      // 需要 MFA → 手机验证码模式
      String? trustAgent;
      if (mfaState.needMfa) {
        if (!mounted) return;
        final qrViewModel = ref.read(qrLoginViewModelProvider.notifier);
        final result = await qrViewModel.mobileMfaVerify(
          context,
          account.cardNumber,
          account.password,
          mfaState.mfaState,
        );
        if (!result.authorized) {
          _goToLogin();
          return;
        }
        trustAgent = result.trustDevice ? 'true' : '';
      }

      // 第二步：直接登录（无需 MFA）
      final loginResult = await authRepo.login(
        account.cardNumber,
        account.password,
        mfaState.mfaState,
        trustAgent: trustAgent ?? '',
      );

      loginResult.fold((failure) => _goToLogin(), (_) async {
        // 刷新学生信息并更新账户显示名称
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
            MaterialPageRoute(builder: (_) => const PlatformSelectionScreen()),
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
