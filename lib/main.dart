import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/design/app_card.dart';
import 'package:smarter_jxufe/design/app_page_transitions.dart';
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

/// 全局色板（唯一来源）。卡片主题也从它派生，保证「卡片强调色 = primary = 校红」。
///
/// ⚠ M3 的 fromSeed 还会按种子色相派生**整个中性色系**：白色不是纯白而是 #FFF8F7
/// （R−B = +8，1920×1080 截图像素实测），整页看起来「白里透红」。
/// 故把白色系逐档覆写为真正的中性灰白（R = G = B），红色只留在 primary 等强调色上。
final ColorScheme _appScheme =
    ColorScheme.fromSeed(
      // 直接 seed 会被 Material3 色调压缩成暗棕红 #904A46；
      // 这里在派生色基础上固定 primary 为校徽红 #C3282E（与 JxufeTheme.primaryColor 一致）。
      seedColor: const Color(0xFFC3282E),
    ).copyWith(
      primary: const Color(0xFFC3282E),
      surface: const Color(0xFFFFFFFF),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFFAFAFA),
      surfaceContainer: const Color(0xFFF5F5F5),
      surfaceContainerHigh: const Color(0xFFF0F0F0),
      surfaceContainerHighest: const Color(0xFFEBEBEB),
      // 高度叠加色：M3 默认取 primary 系 → AppBar / Card 抬起时再染一层红；
      // 设为白 = 只提亮不着色（M3 浅色主题的高度语义本就是「越高越亮」）。
      surfaceTint: const Color(0xFFFFFFFF),
    );

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // pdfrx（pdfium）初始化:必须显式调用，否则首次打开文档会抛
  // `Bad state: Pdfrx getCacheDirectory is not set.`（它负责设置
  // Pdfrx.loadAsset 与 Pdfrx.getCacheDirectory，见 pdfrx_flutter.dart）。
  // 幂等，阅读器内部也会再兜一次。
  unawaited(pdfrxFlutterInitialize());

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
      // 「从子页面返回即刷新」的路由观察者（见 lib/core/navigation/page_auto_refresh.dart）。
      navigatorObservers: [appRouteObserver],
      debugShowCheckedModeBanner: false,
      title: '智慧er江财',
      theme: ThemeData(
        colorScheme: _appScheme,
        // 全应用统一卡片语言：圆角 12 + 淡边框 + 纯白 + 无阴影（见 lib/design/app_card.dart）。
        cardTheme: appCardTheme(_appScheme),
        // 页面转场唯一口径：横向共享轴（Fluent DrillIn）——取代 Flutter 默认那个
        // 「从屏幕中心放大」的 zoom 转场（见 lib/design/app_page_transitions.dart）。
        pageTransitionsTheme: appPageTransitionsTheme,
        fontFamily: 'Cascadia Code',
        fontFamilyFallback: const ['霞鹜文楷', '仓耳今楷01'],
      ),
      home: const SplashScreen(),
    );
  }
}
