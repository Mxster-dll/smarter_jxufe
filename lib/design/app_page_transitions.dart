/// 全应用页面转场（**唯一口径**，2026-09-16 立）。
///
/// ## 为什么需要它
///
/// Flutter 的默认转场在这台项目的两个目标平台上**都是「从屏幕中心放大」**：
/// `material/page_transitions_theme.dart` 的 `_defaultBuilders` 里
/// `windows` / `linux` → `ZoomPageTransitionsBuilder`，
/// `android` → `PredictiveBackPageTransitionsBuilder`（没有系统预测返回手势时同样回落 zoom）。
/// 用户看到的就是这个：点开培养方案 / 课表 / 成绩 / 毕业学分时，新页面从中心向外扩张。
///
/// 本项目全量换成**横向共享轴**（Fluent DrillIn / M3 `SharedAxisTransition.X` 的合并版）：
///
/// - **进入页**：从右侧 [appPageEnterOffsetX]（屏宽比例）滑到位，同时淡入；
/// - **被压在下面的页**：向左让位 [appPageExitOffsetX]；
/// - 返回时曲线自动反向（`Curves.easeOutCubic` 的正 / 反曲线）。
///
/// ## 三条刻意的选择（别顺手改回去）
///
/// 1. **不做缩放**：缩放正是被去掉的那个效果。前进 / 后退的主次关系用「位移 + 淡入」表达。
/// 2. **让位页不淡出**：两层若都做透明度过渡，同一时刻两层文字都半透明 → 看起来发糊。
///    让位页只位移、不改透明度（真位移），进入页独占淡入。
/// 3. **iOS / macOS 保留 `CupertinoPageTransitionsBuilder`**：它附带**回滑返回手势**
///    （`CupertinoRouteTransitionMixin`），换掉它等于把 iOS 的交互删了。
///
/// 位移用**屏宽比例**而不是像素：手机 360dp 与桌面 1600dp 的观感一致。
library;

import 'package:flutter/material.dart';

/// 转场时长。`MaterialPageRoute` 会读取它的
/// （`material/page.dart:91`：`_getPageTransitionBuilder(navigator!.context)?.transitionDuration`），
/// 所以这里改的是真时长，不是「在 300ms 里插空档」。
const Duration appPageTransitionDuration = Duration(milliseconds: 300);

/// 进入页的起始横向位移（占屏宽比例）。
const double appPageEnterOffsetX = 0.04;

/// 被新页面覆盖时，下层页向左让位的比例。
const double appPageExitOffsetX = 0.025;

/// 淡入在转场进度 [appPageFadeEnd] 处就完成 —— 剩下的行程里文字已经实心，
/// 避免「一边滑动一边闪字」。
const double appPageFadeEnd = 0.55;

/// 首页侧栏（master-detail）**右栏换内容**时的时长与位移。
///
/// 与页面转场同一套语言（横向 + 淡入），但更短、位移更小：换的是同一块画布里的
/// 内容，不是翻到新的一页；用 300ms / 4% 会显得整屏在晃。
const Duration appPaneSwitchDuration = Duration(milliseconds: 220);

/// 右栏新内容滑入的起始位移（占右栏宽度比例）。
const double appPaneSwitchOffsetX = 0.02;

/// 横向共享轴转场本体（抽成公开组件是为了能被 widget 测试直接 pump，
/// 不必先搭一个真实 `Navigator`）。
class AppPageTransition extends StatelessWidget {
  const AppPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  /// 本页自己的进出场进度（0 → 1 进入，1 → 0 退出）。
  final Animation<double> animation;

  /// 「有页面压到我上面」的进度（0 → 1 = 被覆盖）。
  final Animation<double> secondaryAnimation;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final yield_ = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      // 让位：静止时 0，被覆盖时向左。
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-appPageExitOffsetX, 0),
      ).animate(yield_),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(appPageEnterOffsetX, 0),
          end: Offset.zero,
        ).animate(enter),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Interval(0, appPageFadeEnd, curve: Curves.easeOut),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 挂到 `ThemeData.pageTransitionsTheme` 上的转场构建器。
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => appPageTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AppPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// 全应用转场表。**所有 `MaterialPageRoute` 都吃它**（含主页侧栏右侧内嵌面板里
/// 那个嵌套 `Navigator` —— 主题经 context 继承，嵌套栈同样生效）。
///
/// ⚠️ 表里**不含**任何 `ZoomPageTransitionsBuilder`；`test/app_page_transitions_test.dart`
/// 对此有守卫（这正是用户报的那个「由中心向外扩张」）。
const PageTransitionsTheme appPageTransitionsTheme = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: AppPageTransitionsBuilder(),
    TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
    TargetPlatform.linux: AppPageTransitionsBuilder(),
    TargetPlatform.windows: AppPageTransitionsBuilder(),
    // iOS / macOS 不回退到自定义转场：Cupertino 那条带系统回滑返回手势。
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
  },
);
