import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/menu/presentation/ims_menu_screen.dart';

class ImsSplashScreen extends ConsumerStatefulWidget {
  const ImsSplashScreen({super.key});

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
    await Future.delayed(const Duration(milliseconds: 500));

    final imsAuthRepo = await ref.read(imsAuthRepositoryProvider.future);
    await imsAuthRepo.refreshJsessionId();

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ImsMenuScreen()),
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
