import 'package:flutter/material.dart';

/// 课表正文区：**让开底部系统导航栏**（Android 三键导航 / 手势条）。
///
/// 用户 2026-09-17：「我希望课表适应高度不要包括底部三键导航的部分」——
/// 课表是**恒适应高度**的（竖版 12 节铺满内容区、横版可见天平分剩余高度），
/// 内容区里若含导航栏那一截，最后一节 / 最后一天就正好被导航栏盖住。
///
/// 为什么必须在这里自己避（别指望 `Scaffold`）：
/// - `Scaffold` **不会**替 `body` 让出导航栏：`flutter/lib/src/material/scaffold.dart:3187-3190`
///   把 `minInsets.bottom` 覆写成键盘高度（`viewInsets.bottom`）或 `0.0`，
///   系统栏只进 `minViewPadding`（那段注释写明它只用于 FAB / SnackBar 定位）。
/// - 本应用是 edge-to-edge（`home_screen.dart` 的口径：Android 已铺满整屏），
///   导航栏**盖在内容之上**，各页自己决定避不避：主页宫格是**滚动**内容，靠列表
///   底部 48 内边距把最后一行留在导航栏之上（特意不整块避，否则导航栏那一条
///   只露出 Scaffold 的白底）；课表是**撑满一屏且不滚动**的，必须整条让开。
///
/// 顶部**不避**（`top: false`）：状态栏高度由 `AppBar` 自己吃掉（`paneAppBar`
/// 就是 AppBar）。左右保持 `SafeArea` 默认（横屏刘海 / 侧边导航栏），与
/// `home_screen.dart` 同口径。
///
/// 抽成独立组件是为了**可测**：守卫 `test/schedule_body_area_test.dart` 用假的
/// 底部内边距断言「正文底边 ≤ 屏幕高 − 导航栏高」，不必伪造学籍 / 课表三套 provider。
class ScheduleBodyArea extends StatelessWidget {
  const ScheduleBodyArea({super.key, required this.child});

  /// 课表正文（竖版网格 / 横版网格 / 加载与错误态）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(top: false, child: child);
  }
}
