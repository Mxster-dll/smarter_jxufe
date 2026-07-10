import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smarter_jxufe/design/JxufeTheme.dart';

import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_screen.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';
import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/features/auth/data/mfa_relogin_service.dart';

/// 账户管理页面 —— 多账户卡片 + 添加账户。
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  /// 当前正在登录的账户卡号，非空时对应按钮显示加载状态。
  String? _loggingInCardNumber;

  @override
  void initState() {
    super.initState();
    // 每次进入页面强制刷新
    Future.microtask(() {
      ref.invalidate(_accountsProvider);
      ref.invalidate(_currentAccountProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(_accountsProvider);
    final currentCardNumber = ref.watch(_currentAccountProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('账户'),
        centerTitle: true,
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (accounts) {
          return Column(
            children: [
              Expanded(
                child: accounts.isEmpty
                    ? const Center(child: Text('暂无账户'))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: accounts.map((a) {
                          final isCurrent = currentCardNumber == a.cardNumber;
                          return _buildAccountCard(context, ref, a, isCurrent);
                        }).toList(),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const LoginScreen(showBackButton: true),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('添加账户'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _avatarContent(BuildContext context, WidgetRef ref, Account account) {
    if (account.displayName.isNotEmpty) {
      return Text(
        account.displayName[0],
        style: TextStyle(
          fontSize: 20,
          color: Theme.of(context).colorScheme.onError,
        ),
      );
    }
    return Icon(
      Icons.person,
      size: 24,
      color: Theme.of(context).colorScheme.onError,
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    WidgetRef ref,
    Account account,
    bool isCurrent,
  ) {
    final isLoading = _loggingInCardNumber == account.cardNumber;
    return Card(
      elevation: isCurrent ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrent
              ? Theme.of(context).colorScheme.error
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Theme.of(context).colorScheme.error,
              child: _avatarContent(context, ref, account),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.cardNumber,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (isCurrent)
                    Text(
                      '当前登录',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            if (!isCurrent)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: isLoading ? 1 : 0),
                duration: const Duration(milliseconds: 300),
                builder: (context, t, child) {
                  return ElevatedButton(
                    onPressed: () => _switchAccount(context, ref, account),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.lerp(
                        Theme.of(context).colorScheme.error,
                        JxufeTheme.primaryColor.withAlpha(160),
                        t,
                      ),
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    child: child,
                  );
                },
                child: SizedBox(
                  width: 32,
                  height: 18,
                  child: Center(
                    child: isLoading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('登录'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchAccount(
    BuildContext context,
    WidgetRef ref,
    Account account,
  ) async {
    if (_loggingInCardNumber != null) return; // 已有账户在登录中
    setState(() => _loggingInCardNumber = account.cardNumber);
    try {
      final authRepo = await ref.read(authRepositoryProvider.future);
      final accountRepo = await ref.read(accountRepositoryProvider.future);
      final studentInfoRepo = await ref.read(
        studentInfoRepositoryProvider.future,
      );
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
          barrierDismissible: true,
        );
        if (!result.authorized) throw Exception('用户取消 MFA 验证');
      };
      authRepo.onMfaRequired = mfaHandler;
      mfaReloginService.setHandler(mfaHandler);

      // 第〇步：预请求 CAS 登录页面
      final prepareResult = await authRepo.prepareLogin();
      if (prepareResult.isLeft()) {
        final msg = prepareResult.fold((f) => f.message ?? '未知错误', (_) => '');
        _showError(context, msg);
        return;
      }

      // 第一步：检测 MFA
      final mfaResult = await authRepo.detectMfa(
        account.cardNumber,
        account.password,
      );
      final mfaState = mfaResult.fold((failure) {
        _showError(context, 'MFA检测失败: ${failure.message}');
        return null;
      }, (r) => r);
      if (mfaState == null) return;

      // 第二步：MFA 验证（扫码/短信可切换）
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
          showSwitchAccount: false,
          displayName: account.displayName,
          barrierDismissible: true,
        );
        // 用户取消 → 留在账户页（切换用户由对话框内部处理）
        if (!result.authorized) return;
        trustAgent = result.trustDevice ? 'true' : '';
      }

      // 第三步：登录
      final loginResult = await authRepo.login(
        account.cardNumber,
        account.password,
        mfaState.mfaState,
        trustAgent: trustAgent ?? '',
      );

      loginResult.fold(
        (failure) => _showError(context, '登录失败: ${failure.message}'),
        (_) async {
          // 更新当前账户 Provider（驱动 Dio 切换）
          ref.read(currentAccountProvider.notifier).state = account.cardNumber;
          // 清除旧 JSESSIONID 缓存
          final imsAuthRepo = await ref.read(imsAuthRepositoryProvider.future);
          await imsAuthRepo.logout();
          // 清除旧学生信息缓存
          await studentInfoRepo.clearCache();
          // 刷新学生信息并更新账户显示名称
          final infoResult = await studentInfoRepo.getStudentInfo(
            forceRefresh: true,
          );
          infoResult.fold(
            (_) => null,
            (info) =>
                accountRepo.updateDisplayName(account.cardNumber, info.name),
          );
          // 设为当前账户
          final accountsResult = accountRepo.getAccounts();
          final idx = accountsResult.fold(
            (_) => -1,
            (list) =>
                list.indexWhere((a) => a.cardNumber == account.cardNumber),
          );
          if (idx >= 0) {
            await accountRepo.setCurrentAccount(idx);
          }
          // 刷新学生信息
          studentInfoRepo.getStudentInfo(forceRefresh: true).ignore();
          // 跳转 IMS
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ImsSplashScreen()),
              (_) => false,
            );
          }
        },
      );
    } catch (e) {
      _showError(context, '切换失败: $e');
    } finally {
      if (mounted) {
        setState(() => _loggingInCardNumber = null);
      }
    }
  }

  void _showError(BuildContext context, String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

final _accountsProvider = FutureProvider<List<Account>>((ref) async {
  final repo = await ref.watch(accountRepositoryProvider.future);
  final result = repo.getAccounts();
  return result.fold(
    (failure) => throw Exception(failure.message),
    (accounts) => accounts,
  );
});

final _currentAccountProvider = Provider<String?>((ref) {
  final cardNumber = ref.watch(currentAccountProvider);
  return cardNumber.isEmpty ? null : cardNumber;
});
