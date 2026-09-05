import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/menu/presentation/ims_menu_screen.dart';
import 'package:smarter_jxufe/features/ims/menu/presentation/ims_tab_container.dart';

/// IMS 会话刷新闸门。
///
/// 进入任意 IMS 功能前先刷新 JSESSIONID；
/// [initialTab] 为空时进入 IMS 菜单页，否则直达对应功能容器。
class ImsSplashScreen extends ConsumerStatefulWidget {
  final ImsTab? initialTab;

  const ImsSplashScreen({super.key, this.initialTab});

  @override
  ConsumerState<ImsSplashScreen> createState() => _ImsSplashScreenState();
}

class _ImsSplashScreenState extends ConsumerState<ImsSplashScreen> {
  @override
  void initState() {
    super.initState();

    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // 等待一下，让启动页至少显示 500ms（可选）
    await Future.delayed(const Duration(milliseconds: 500));

    final imsAuthRepo = await ref.read(imsAuthRepositoryProvider.future);
    await imsAuthRepo.refreshJsessionId();

    if (!mounted) return;

    final initialTab = widget.initialTab;
    final target = initialTab == null
        ? const ImsMenuScreen()
        : ImsTabContainer(initialTab: initialTab);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            const Text('加载中...'),
          ],
        ),
      ),
    );
  }
}
