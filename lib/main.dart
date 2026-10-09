import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:smarter_jxufe/core/navigation/navigator_key.dart';
import 'package:smarter_jxufe/core/navigation/page_auto_refresh.dart';
import 'package:smarter_jxufe/core/navigation/route_history.dart';
import 'package:smarter_jxufe/core/navigation/service_nav.dart';
import 'package:smarter_jxufe/core/storage/hive_initializer.dart';
import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/window_title_bar.dart';
import 'package:smarter_jxufe/features/ai/presentation/ai_floating_ball.dart';
import 'package:smarter_jxufe/features/auth/data/auth_exception.dart';
import 'package:smarter_jxufe/features/auth/data/mfa_relogin_service.dart';
import 'package:smarter_jxufe/features/comprehensive_service/presentation/comprehensive_service_home_screen.dart';
import 'package:smarter_jxufe/features/data_center/presentation/data_center_screen.dart';
import 'package:smarter_jxufe/features/home/presentation/home_screen.dart';
import 'package:smarter_jxufe/features/home/presentation/overview_pane.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/ims/student_info/presentation/student_info_screen.dart';
import 'package:smarter_jxufe/features/home_widget/data/home_widget_background.dart';
import 'package:smarter_jxufe/features/home_widget/presentation/home_widget_launcher.dart';
import 'package:smarter_jxufe/features/materials/presentation/materials_screen.dart';
import 'package:smarter_jxufe/features/qr_login/presentation/qr_login_viewmodel.dart';
import 'package:smarter_jxufe/features/settings/data/theme_prefs.dart';
import 'package:smarter_jxufe/features/settings/data/window_bar_prefs.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';
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

/// MFA 兜底处理器注册（**组装根职责**，2026-09-20 · 架构审查 ⑦）。
///
/// `MfaReloginService` 的兜底从前直接写在 auth 的数据层里 —— 那段代码要弹
/// `features/qr_login` 的 MFA 对话框，等于让 data 层 import 别家 presentation。
/// 现在数据层只留一个注册位（`setFallback`），实现放在这里：
/// 组装根本来就该知道所有模块，feature 之间因此少一条 `qr_login → auth` 的环。
void _installMfaFallback() {
  mfaReloginService.setFallback((ctx, account, password, mfaState) async {
    final container = ProviderScope.containerOf(ctx);
    final qrVm = container.read(qrLoginViewModelProvider.notifier);
    final result = await qrVm.unifiedMfaVerify(
      ctx,
      account,
      password,
      mfaState,
    );
    if (!result.authorized) throw AuthException('用户取消 MFA 验证');
    return result.trustDevice;
  });
}

/// 页面之间的「跳转缝」注册（**组装根职责**，2026-09-20 · 架构审查 ⑦）。
///
/// 已收口的反向导航边：`zongce → 材料库`、`student_info → 主页`、`home / ai → 设置页`、
/// `platform 选择器 → IMS / 综合服务 / 数据中台`（各自反向都还有**数据**依赖，见
/// `docs/agents/33-…md` §33.6）。业务代码只喊 id，目标页在这里登记 ——
/// 与 [_installMfaFallback] 同一套路：**组装根本来就知道所有模块**。
void _installServiceScreens() {
  // ⚠ `label` = 顶部「路由历史」里的显示名（2026-10-09 七轮加的全局前进/后退）。
  registerServiceScreen(kServiceHome, () => const HomeScreen(), label: '主页');
  // 右栏默认那一格「数据一览」：**必须也注册**（用户 2026-10-09 二十四轮）——
  // 它要不是"注册过的页面"，`home_screen` 就只能裸渲染它，那样它里面的卡片上查不到
  // `PaneScope`，点开就会整页盖住窗口。注册之后概览成为面板首路由，一切都走内嵌通道。
  registerServiceScreen(
    kServiceOverview,
    () => const HomeOverviewPane(),
    label: '数据一览',
  );
  registerServiceScreen(kServiceMaterials, () => const MaterialsScreen(), label: '材料库');
  registerServiceScreen(kServiceSettings, () => const SettingsScreen(), label: '设置');
  registerServiceScreen(kServiceIms, () => const ImsSplashScreen(), label: '教学信息服务');
  registerServiceScreen(
    kServiceComprehensive,
    () => const ComprehensiveServiceHomeScreen(),
    label: '综合管理服务平台',
  );
  registerServiceScreen(kServiceDataCenter, () => const DataCenterScreen(), label: '数据中台');
  // 侧栏底部固定区的「我的」（2026-10-09 五轮）：它和设置页一样既会被 push（宫格
  // 视图的头像），也会被**内嵌**在右栏 —— 两种模式都不用特判：页面自己走
  // `paneAppBar`，内嵌首路由时整条导航栏自动不画（见 §19）。
  registerServiceScreen(kServiceStudentInfo, () => const StudentInfoScreen(), label: '我的');
}

/// 主题（浅色 / 深色 / 卡片语言 / 转场 / 字体）唯一出处 = `lib/design/app_theme.dart`。
/// 底色阶梯的取值与口径见 `lib/design/app_ladder.dart`。
void main() async {
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

  _installMfaFallback();
  _installServiceScreens();

  // ── 外观偏好预热（深色模式适配，2026-09-16）──────────────────────────────
  // 必须在 `runApp` **之前**把用户选定的 ThemeMode 读出来，否则首帧会先按
  // 「跟随系统」画一次再跳到用户选择，深色用户会看到一次白闪。
  // `HiveInitializer.init()` 已改成幂等（`_init ??= _run()`），SplashScreen 里那次
  // 历史调用不会二次注册 adapter；这里整体 try/catch，任何失败都退回「跟随系统」，
  // 绝不让存储问题挡住启动。
  //
  // 窗口标题栏的两项偏好（三键风格 / 左右互换）同样要预热：标题栏是第一帧就画的
  // chrome，异步读盘会让它先按 Windows 风格 + 右侧三键画一次再跳一下。
  final themeModeStore = ThemeModeStore();
  final windowBarStore = WindowBarPrefsStore();
  try {
    await HiveInitializer.init();
    await themeModeStore.ensureLoaded();
    await windowBarStore.ensureLoaded();
  } catch (_) {}

  runApp(
    ProviderScope(
      overrides: [
        themeModeStoreProvider.overrideWith((ref) => themeModeStore),
        windowBarPrefsProvider.overrideWith((ref) => windowBarStore),
      ],
      child: const SmarterJxUFE(),
    ),
  );
}

/// 顶部「路由历史」的接线（**组装根职责**，2026-10-09 · 用户要求「全局记录前进/后退」）。
///
/// 两件事：
/// 1. 把 `navigatorKey.currentState` 交给跳转缝 —— 历史回放（`restore()`）手里没有
///    `BuildContext`，只能靠它开页面；
/// 2. 把「记一笔」的动作注入缝：缝里三个跳转动作都会喊它，这里翻译成账本上的一条
///    （`restore` 走无 context 的 `openServiceScreenById`，没注册的记成不可回退）。
void _installRouteHistory(WidgetRef ref) {
  final history = ref.read(routeHistoryProvider);
  attachServiceNavigator(navigatorKey.currentState);
  serviceNavHistoryRecorder = (id, label, canRestore) {
    history.record(
      RouteHistoryEntry(
        label: label,
        key: 'service:$id',
        restore: canRestore ? () => openServiceScreenById(id) : null,
      ),
    );
  };
}

class SmarterJxUFE extends ConsumerWidget {
  const SmarterJxUFE({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 用户选定的外观模式（跟随系统 / 浅色 / 深色），存在 Hive，已在 main() 预热。
    final themeMode = ref.watch(themeModeStoreProvider).mode;
    // 顶部「路由历史」的两个动作（前进 / 后退）：组装根把缝和账本接起来 ——
    // 缝只喊钩子（core 里不互相 import），回放走无 context 的 `openServiceScreenById`。
    _installRouteHistory(ref);
    return MaterialApp(
      navigatorKey: navigatorKey,
      // 「从子页面返回即刷新」的路由观察者（见 lib/core/navigation/page_auto_refresh.dart）。
      navigatorObservers: [appRouteObserver],
      debugShowCheckedModeBanner: false,
      title: '智慧er江财',
      // 浅色 = 改动前逐值不变；深色 = A 中性深灰 + 亮红（用户 2026-09-16 拍板）。
      theme: appLightTheme,
      darkTheme: appDarkTheme,
      themeMode: themeMode,
      // AI 助手的全局悬浮球：必须挂在 builder 上（浮在 Navigator 之上，
      // 页面切换不会把它一起销毁）。开关在「设置 → AI 助手」。
      //
      // 自绘窗口标题栏（隐藏系统标题栏后由应用自己画三键 / 拖动 / 贴靠）也挂在这里：
      // 它必须在 Navigator **之上** —— 任何页面、任何弹层下都要能关窗口。
      // 非 Windows 平台 `AppWindowChrome` 原样透传 child（系统标题栏还在）。
      builder: (context, child) => AppWindowChrome(
        child: AiFloatingBallHost(child: child ?? const SizedBox.shrink()),
      ),
      home: const SplashScreen(),
    );
  }
}


