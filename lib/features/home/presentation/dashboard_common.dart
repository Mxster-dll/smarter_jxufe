/// 首页仪表盘的共用小件（2026-09-20 从 `dashboard_panel.dart` 外提 · 架构审查 ⑥）。
///
/// 两个渲染簇（`dashboard_metrics.dart` / `dashboard_today_courses.dart`）都要用它们，
/// 故单独一份并公开命名（原来是类内私有方法 `_push` / `_inlineStatus`）。
library;

import 'package:flutter/material.dart';

import 'package:smarter_jxufe/design/pane_chrome.dart';
import 'package:smarter_jxufe/features/electricity/presentation/electricity_screen.dart';
import 'package:smarter_jxufe/features/ims/menu/domain/ims_tab.dart';
import 'package:smarter_jxufe/features/ims/splash/presentation/ims_splash_screen.dart';
import 'package:smarter_jxufe/features/net_fee/presentation/net_fee_screen.dart';

/// 仪表盘卡片点开后，目标页在**侧栏目录**里的条目名（= 内嵌面板的 id / 高亮项）。
///
/// - 这几个页面都是**目录里已有的服务**，所以名字一律**引用既有口径、不写字面量**：
///   IMS 四页取 `ImsTab.*.title`（目录里的标题也是它）。
/// - `null` = 「这一页在侧栏里没有独立条目」→ 调用方退回整页 push（宫格视图的老行为）。
String? dashboardPaneKeyOf(Widget screen) {
  if (screen is ImsSplashScreen) {
    // 仪表盘的「成绩」/「课表」卡推的是 IMS 那条溅屏入口（按 initialTab 决定落到哪一页）。
    // `studentInfo` 的标题是「我的」，而侧栏里另有底部固定区的「我的」——
    // 内嵌推它时面板 id 取 **`ImsTab.title`**（'我的'）而不是底部那个枚举名，
    // 两者天然不撞（底部固定区的 id 是 `HomeSidebarFooter.name`）。
    return screen.initialTab?.title ?? ImsTab.curriculum.title;
  }
  if (screen is ElectricityScreen) return '宿舍电费';
  if (screen is NetFeeScreen) return '校园网';
  // 志愿时长等其余卡片目前不从这里推（它们走目录条目自己的 onTap），
  // 认不出来就老实整页 push。
  return null;
}

/// 打开仪表盘卡片对应的页面。
///
/// ⚠ **必须看"在不在面板里"**（用户 2026-10-09 二十四轮：「点击主页卡片后，页面会占满
/// 整个窗口，而不是显示在右侧内容区」）：概览面板（`DashboardPanel`）本身就被内嵌在
/// 侧栏右栏里，它的指标卡从前一律 `Navigator.push` —— 那会盖住整个窗口。
///
/// **内嵌时**：把这页塞进**面板自己的** `Navigator`（与 `HomeDetailPane` 完全同一套
/// 包法：`PaneScope(embedded: true)` + `Navigator`）→ 页面显示在右栏、顶部自动有返回
/// （`paneAppBar` 见 `paneIsRoot == false`）；IMS 那条溅屏入口是**替换**首路由
/// （`ImsSplashScreen` 自己会在会话就绪后 `pushReplacement`，压成两层会叠出两个返回）。
///
/// **宫格视图**（没有面板）仍旧整页 push，那里的老行为一个字没变。
///
/// ⚠⚠ **不要退回 `openServiceScreen(context, paneKey)`**（二十四轮第一版就是这么写的，
/// **没生效**）：跳转缝里只注册了 7 个 id（`kServiceHome/Materials/Settings/Ims/
/// Comprehensive/DataCenter/StudentInfo`），**`宿舍电费`/`校园网`/`成绩`/`课表`/`志愿时长`
/// 一个都不在里面** → `openServiceScreen` 恒返回 false → 每次都走整页 push。
/// 当时那条用例之所以是绿的，是因为**它自己把那些 id 注册进了缝**（典型的"测试把
/// 被测系统喂饱了"）。现在这里**只用传进来的 [screen] 本体**，不看缝里有没有。
void dashboardPush(BuildContext context, Widget screen) {
  final paneKey = dashboardPaneKeyOf(screen);
  // ⚠ 判据 = `paneEmbedded`（本页在不在面板里）。
  // 右栏那一格「数据一览」概览**已经是面板的一条路由**（`home_screen._overviewPane()`
  // 把它交给 `HomeDetailPane`，见 §44.1.18），所以从概览点卡片时这里为 **true**。
  if (paneEmbedded(context) && paneKey != null) {
    // ⚠⚠ **优先走"侧栏右栏宿主"的回调**（用户 2026-10-10 二十七轮：
    // 「点击数据一览的卡片后，顶部路由不记录」）。
    //
    // 直接 `Navigator.of(context).push(...)` 只是往面板内部那个 Navigator 压一层，
    // **绕过了宿主的记账** —— 顶部的全局路由历史是在 `home_screen._select` /
    // `_recordPaneHistory` 里记的，于是这一段在历史里什么都不留（前进/后退对它全瞎）。
    // 交给宿主之后，走的是**和点侧栏条目同一套**通道：记账 + 侧栏高亮 + 换页动画
    // 一次性对齐。
    final host = PaneScope.sidebarHostOf(context);
    if (host != null) {
      host(paneKey);
      return;
    }
    // 兜底（独立面板 / 单测没给宿主）：保持原样，就地压一层。
    // 面板首路由 = 目录里那一页；这里再推就是**二级页**（有返回键，正确）。
    // 溅屏入口不同：它会把首路由替换掉，所以这里也替换，别叠两层。
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<void>(builder: (_) => screen);
    if (screen is ImsSplashScreen) {
      navigator.pushReplacement(route);
    } else {
      navigator.push(route);
    }
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

  Widget dashboardInlineStatus(ColorScheme scheme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
