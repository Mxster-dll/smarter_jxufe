import 'package:flutter/material.dart';

import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/features/electricity/presentation/electricity_screen.dart';
import 'package:smarter_jxufe/features/home_widget/data/home_widget_bridge.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';

/// 「点桌面小组件 → 打开 App 对应页面」的路由处理。
///
/// 冷启动：原生把目标路由写进本地存储，[consumePendingRoute] 取一次并清空；
/// 热启动（App 已在后台）：原生通过通道回调 `routeChanged`，[install] 注册的
/// 处理器直接跳转（MainActivity 为 singleTop，走 onNewIntent）。
class HomeWidgetLauncher {
  HomeWidgetLauncher._();

  /// 打开路由对应的页面；未知路由不做任何事。
  static Future<void> openRoute(String route) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    final Widget? screen = switch (route) {
      'electricity' => const ElectricityScreen(),
      'grades' => ImsSplashScreen(initialTab: ImsTab.grade),
      // 仪表盘小组件点开就是首页（冷启动本来就落在首页，热启动只需把 App 唤到前台）。
      'dashboard' => null,
      _ => null,
    };
    if (screen == null) return;
    await navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// 冷启动时消费一次待处理路由（无则什么都不做）。
  static Future<void> consumePendingRoute() async {
    final route = await HomeWidgetBridge.consumeLaunchRoute();
    if (route == null || route.isEmpty) return;
    await openRoute(route);
  }

  /// 注册原生回调：App 已在运行时被小组件唤起 → 立即跳转。
  static void install() => HomeWidgetBridge.installRouteHandler(openRoute);
}
