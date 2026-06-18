import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/auth/data/providers/account_repository_provider.dart';
import 'package:smarter_jxufe/features/auth/domain/entities/account.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';

/// 账户选择页面 —— 显示已保存的账户，支持切换。
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(_accountProvider);
    final studentInfoAsync = ref.watch(_cachedStudentInfoProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('账户'),
        centerTitle: true,
      ),
      body: accountAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败: $error')),
        data: (account) => account == null
            ? const Center(child: Text('未保存账户'))
            : _buildAccountCard(context, ref, account, studentInfoAsync),
      ),
    );
  }

  Widget _buildAccountCard(
    BuildContext context,
    WidgetRef ref,
    Account account,
    AsyncValue<StudentInfo?> studentInfoAsync,
  ) {
    final studentInfo = studentInfoAsync.valueOrNull;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 头像：已关联学生信息则用姓名首位，否则用图标
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Theme.of(context).colorScheme.error,
                  child: studentInfo != null && studentInfo.name.isNotEmpty
                      ? Text(
                          studentInfo.name[0],
                          style: TextStyle(
                            fontSize: 36,
                            color: Theme.of(context).colorScheme.onError,
                          ),
                        )
                      : Icon(
                          Icons.person,
                          size: 36,
                          color: Theme.of(context).colorScheme.onError,
                        ),
                ),
                const SizedBox(height: 16),
                if (studentInfo != null)
                  Text(
                    studentInfo.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                const SizedBox(height: 4),
                Text(
                  account.cardNumber,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () {
                    // TODO: 切换到其他账户
                  },
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('切换账户'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final _accountProvider = FutureProvider<Account?>((ref) async {
  final repo = await ref.watch(accountRepositoryProvider.future);
  final result = await repo.getAccount();
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
