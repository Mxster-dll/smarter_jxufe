import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/core/storage/hive_initializer.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_screen.dart';
import 'package:smarter_jxufe/features/home/presentation/home_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/account_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';
import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/features/auth/data/mfa_relogin_service.dart';

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

      // 有本地账号 → 尝试自动登录
      final authRepo = await ref.read(authRepositoryProvider.future);
      authRepo.cacheCredentials(account.cardNumber, account.password);

      // 注入 MFA 回调，供后续自动重登时使用。
      // 使用全局 navigatorKey 获取当前 context，避免原 widget 销毁后 context 失效。
      final qrVm = ref.read(qrLoginViewModelProvider.notifier);
      final isDesktop =
          defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.android;
      final mfaHandler = (String mfaState) async {
        final ctx = navigatorKey.currentContext;
        if (ctx == null) throw Exception('无法获取当前页面上下文');
        final result = await qrVm.unifiedMfaVerify(
          ctx,
          account.cardNumber,
          account.password,
          mfaState,
          startInQrMode: isDesktop,
          displayName: account.displayName,
        );
        if (!result.authorized) throw Exception('用户取消 MFA 验证');
      };
      authRepo.onMfaRequired = mfaHandler;
      mfaReloginService.setHandler(mfaHandler);

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

      // 需要 MFA → 扫码/短信可切换
      String? trustAgent;
      if (mfaState.needMfa) {
        if (!mounted) return;
        final qrViewModel = ref.read(qrLoginViewModelProvider.notifier);
        final isDesktop =
            Theme.of(context).platform != TargetPlatform.iOS &&
            Theme.of(context).platform != TargetPlatform.android;
        final result = await qrViewModel.unifiedMfaVerify(
          context,
          account.cardNumber,
          account.password,
          mfaState.mfaState,
          startInQrMode: isDesktop,
          displayName: account.displayName,
        );
        // 用户取消 → 回退到账户管理页（此时尚无账户登录，无需清状态）
        if (!result.authorized) {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AccountScreen()),
              (_) => false,
            );
          }
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
        // 登录成功 → 标记为已登录账户
        ref.read(currentAccountProvider.notifier).state = account.cardNumber;
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
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
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
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
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
