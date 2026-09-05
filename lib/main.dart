import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/features/splash/presentation/splash_screen.dart';
import 'package:smarter_jxufe/shared/services/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局捕获未处理异常，打印完整信息和堆栈
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('══╡ FlutterError ╞══════════════════════════════');
    debugPrint('Exception: ${details.exception}');
    debugPrint('Stack:\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('══╡ PlatformDispatcher Error ╞═════════════════');
    debugPrint('$error');
    debugPrint('$stack');
    return true;
  };

  NotificationService.instance.init().catchError((_) {});
  runApp(const ProviderScope(child: SmarterJxUFE()));
}

class SmarterJxUFE extends StatelessWidget {
  const SmarterJxUFE({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: '智慧尼采',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF008CFF)),
        fontFamily: 'Cascadia Code',
        fontFamilyFallback: const ['霞鹜文楷', '仓耳今楷01'],
      ),
      home: const SplashScreen(),
    );
  }
}
