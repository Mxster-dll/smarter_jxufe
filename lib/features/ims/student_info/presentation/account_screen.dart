import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// 账户管理页面 —— 多账户卡片 + 添加账户。
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
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
    final currentAsync = ref.watch(_currentAccountProvider);

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
          final current = currentAsync.valueOrNull;
          return Column(
            children: [
              Expanded(
                child: accounts.isEmpty
                    ? const Center(child: Text('暂无账户'))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: accounts.map((a) {
                          final isCurrent = current?.cardNumber == a.cardNumber;
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
              ElevatedButton(
                onPressed: () => _switchAccount(context, ref, account),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('登录'),
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
    try {
      final authRepo = await ref.read(authRepositoryProvider.future);
      final accountRepo = await ref.read(accountRepositoryProvider.future);
      final studentInfoRepo = await ref.read(
        studentInfoRepositoryProvider.future,
      );

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

      // 第二步：MFA 验证（手机验证码模式）
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

final _currentAccountProvider = FutureProvider<Account?>((ref) async {
  final repo = await ref.watch(accountRepositoryProvider.future);
  final result = repo.getCurrentAccount();
  return result.fold(
    (failure) => throw Exception(failure.message),
    (account) => account,
  );
});

/// 从本地缓存读取学生信息（不触发网络请求）。
final _cachedStudentInfoProvider = FutureProvider<StudentInfo?>((ref) async {
  final repo = await ref.watch(studentInfoRepositoryProvider.future);
  final result = repo.getCachedStudentInfo();
  return result.fold((failure) => null, (info) => info);
});
