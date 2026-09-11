import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/features/home_widget/data/home_widget_background.dart';
import 'package:smarter_jxufe/features/home_widget/presentation/home_widget_launcher.dart';
import 'package:smarter_jxufe/features/splash/presentation/splash_screen.dart';
import 'package:smarter_jxufe/shared/services/notification_service.dart';

/// 桌面小组件后台刷新入口（原生 headless FlutterEngine 用命名入口点调用）。
///
/// ⚠️ 必须定义在 **root library（本文件）**：原生侧用
/// `DartEntrypoint(bundlePath, "homeWidgetBackgroundMain")` 调用，而 DartEntrypoint
/// 不指定 libraryUri 时，Flutter 只在根库里查找该函数。曾把它定义在子库
/// （`features/home_widget/data/home_widget_background.dart`）→ 引擎日志
/// `Could not resolve main entrypoint function.` / `Could not create root isolate.`
/// → 后台刷新静默失败（快照永远不更新）。这里只做转发，实现仍在子库。
@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundMain() => runHomeWidgetBackground();

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

  // 桌面小组件：注册「点小组件唤起 App」的回调（冷启动的待处理路由由首页消费）。
  HomeWidgetLauncher.install();
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
        // 直接 seed 会被 Material3 色调压缩成暗棕红 #904A46；
        // 这里在派生色基础上固定 primary 为校徽红 #C3282E（与 JxufeTheme.primaryColor 一致）。
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC3282E),
        ).copyWith(primary: const Color(0xFFC3282E)),
        fontFamily: 'Cascadia Code',
        fontFamilyFallback: const ['霞鹜文楷', '仓耳今楷01'],
      ),
      home: const SplashScreen(),
    );
  }
}
