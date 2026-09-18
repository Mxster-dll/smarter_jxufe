import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_for_account_provider.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';
import 'package:smarter_jxufe/features/auth/presentation/login_screen.dart';
import 'package:smarter_jxufe/features/home/presentation/home_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
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
          color: AppColors.onErrorFill(context),
        ),
      );
    }
    return Icon(
      Icons.person,
      size: 24,
      color: AppColors.onErrorFill(context),
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
              backgroundColor: AppColors.errorFill(context),
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
                        AppColors.errorFill(context),
                        Theme.of(context).colorScheme.primary.withAlpha(160),
                        t,
                      ),
                      foregroundColor: AppColors.onErrorFill(context),
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
                              color: AppColors.onErrorFill(context),
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
      // 取**该账号**的统一登录仓库（TGC / 凭据都按账号存放）
      final authRepo = await ref.read(
        authRepositoryForAccountProvider(account.cardNumber).future,
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
        // 把「信任此设备」带回 AuthRepository → 自动重登时继续登记到 CAS。
        return result.trustDevice;
      };
      authRepo.onMfaRequired = mfaHandler;
      mfaReloginService.setHandler(mfaHandler);

      // 免登录：该账号磁盘上的 TGC 仍有效 → 直接切过去，不再重登
      // （免密码、免 MFA）。这就是「切回来不用重新登录」。
      if (await authRepo.isTgcAlive()) {
        if (!mounted) return;
        await _completeSwitch(context, ref, account);
        return;
      }

      // TGC 已失效 → 走完整登录（必要时弹 MFA）。
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
        // 记住用户本次选择（勾选=长信任；取消勾选=清掉旧信任）。
        await authRepo.rememberTrustDevice(
          account.cardNumber,
          result.trustDevice,
        );
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
        (_) => _completeSwitch(context, ref, account),
      );
    } catch (e) {
      _showError(context, '切换失败: $e');
    } finally {
      if (mounted) {
        setState(() => _loggingInCardNumber = null);
      }
    }
  }

  /// 切换收尾：设为当前账号 → 刷新学籍与显示名 → 跳首页。
  ///
  /// 「TGC 免登录」与「完整登录」两条路径共用（差别只在前面怎么拿到会话）。
  ///
  /// 更新 `currentAccountProvider` → 全局 IMS 会话（`imsSessionProvider`）
  /// **销毁重建**为新账号的会话，`currentImsDioProvider` 随之切换。
  /// 这里**不再**调 `imsAuthRepo.logout()` / `studentInfoRepo.clearCache()`：
  /// 会话与个人缓存（成绩/学籍/课表/调课）都已按账号隔离存放，清掉反而会
  /// 把刚登录的新账号数据删了、也丢了切回来能直接复用的缓存。
  Future<void> _completeSwitch(
    BuildContext context,
    WidgetRef ref,
    Account account,
  ) async {
    ref.read(currentAccountProvider.notifier).state = account.cardNumber;

    // ⚠️ 必须在设置账号**之后**重新取仓库：切号前拿到的实例绑的是旧账号的 box。
    final freshStudentInfoRepo = await ref.read(
      studentInfoRepositoryProvider.future,
    );
    final accountRepo = await ref.read(accountRepositoryProvider.future);
    final infoResult = await freshStudentInfoRepo.getStudentInfo(
      forceRefresh: true,
    );
    infoResult.fold(
      (_) => null,
      (info) => accountRepo.updateDisplayName(account.cardNumber, info.name),
    );
    // 设为当前账户（持久化：下次启动据此免登录进入）
    final accountsResult = accountRepo.getAccounts();
    final idx = accountsResult.fold(
      (_) => -1,
      (list) => list.indexWhere((a) => a.cardNumber == account.cardNumber),
    );
    if (idx >= 0) {
      await accountRepo.setCurrentAccount(idx);
    }
    // 跳转到主页宫格
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
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
