import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/storage/hive_initializer.dart';
import 'package:smarter_jxufe/features/auth/data/providers/auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/auth/data/providers/ims_auth_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/menu/presentation/ims_menu_screen.dart';

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

    // 等待一下，让启动页至少显示 500ms（可选）
    await Future.delayed(const Duration(milliseconds: 500));

    final authRepo = ref.read(authRepositoryProvider);
    try {
      final file = File('tmp.txt');
      final lines = file.readAsLinesSync();

      // TODO 这个地方逻辑要大改，如何从后端验证，什么时候进登录页，什么时候尝试重新获取tgc
      final result = await authRepo.login(lines[0], lines[1]);
      // TODO 此行验证登录状态（修改密码的情况）并隔一阵子就验证密码（可选）

      result.fold(Left.new, (user) async {
        final imsAuthRepo = await ref.read(imsAuthRepositoryProvider.future);
        await imsAuthRepo.login();

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ImsMenuScreen()),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const Text("待实现登录页")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
