// 本文件是 `lib/design/window_chrome/` 拆分件之一 —— 文件地图见 docs/agents/43 的 §43.5。
// 公开入口仍是 `package:smarter_jxufe/design/window_title_bar.dart`（桶文件，对外零改动）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/window/window_chrome.dart';
import 'package:smarter_jxufe/design/window_title_bar.dart';

/// 标题栏高度（逻辑像素）。原生侧的「标题栏带」厚度 = 这个值 × 窗口 DPI。
///
/// 40 是权衡后的取值：装得下 24 的 logo、15 的应用名、26 的头像，又比原生 caption
/// 常用的 32 只高一档 —— 再矮三键的点击区就不够「Windows 手感」了。
const double kWindowTitleBarHeight = 40;

/// Windows 风格三键的按钮宽（Win11 原生是 46×32，这里高度取满栏）。
const double kWindowTitleBarButtonWidth = 46;

/// macOS 风格每个圆点占的槽宽（点击区 = 槽，圆点居中画 12）。
const double kWindowTitleBarMacSlot = 20;

/// macOS 风格圆点直径。
const double kWindowTitleBarMacDot = 12;

/// mac 三键**整组**的四周留白（用户 2026-10-09 四轮：「三键距离窗口左右边缘太近，
/// 希望 mac 三键作为一个整体，其距离标题栏上下边距与侧边边距要一致」）。
///
/// 判据取**圆点墨迹**、按**栏内实际可画高度**算。⚠ 那个高度**不再减 1**：分隔线
/// （`Border(bottom)`）已于 2026-10-09 六轮按用户要求撤掉（「标题栏底部不要显示那根
/// 框线，从而让标题栏可以和侧边栏视觉上连续」）→ 子件拿到的就是整 40，圆点竖直居中后
/// 距上边 `(40 − 12) / 2 = **14**`；侧边对齐这个数，整组外侧再补
/// [kWindowTitleBarMacClusterInset] = 14 − (20 − 12)/2 = **10**。
/// 守卫 = `test/window_title_bar_test.dart`「整组留白：圆点距侧边 = 距栏上下边」。
///
/// ⚠ `AppLadder` 的顶栏色（深色 `#1A1A1A`）与侧栏底色（`surfaceContainerLow`，深色
/// 同为 `#1A1A1A`）本来就一致 —— 撤掉那根线之后两条区域才真的连成一片；浅色下顶栏是
/// `#FFFFFF`、侧栏 `#FAFAFA`（差 5/255，肉眼近乎看不出）。
const double kWindowTitleBarContentHeight = kWindowTitleBarHeight;
const double kWindowTitleBarEdgeInset =
    (kWindowTitleBarContentHeight - kWindowTitleBarMacDot) / 2;
const double kWindowTitleBarMacClusterInset =
    kWindowTitleBarEdgeInset -
    (kWindowTitleBarMacSlot - kWindowTitleBarMacDot) / 2;

/// Windows 风格三键图标的字号（codicon 的原生网格 16 → 墨迹约 10px，
/// 与原生 Windows caption 图标 / VS Code Windows 标题栏同尺寸）。
const double kWindowTitleBarGlyphSize = 16;

/// 两项设置在标题栏上变化时的动画时长（2026-10-09 用户要求「切换时加动画」）。
///
/// 覆盖三种变化：① 换位置（品牌与三键两组**反向对滑**）；② 换风格
/// （46 的方键「收成」20 的圆点：高亮底 + codicon 字形淡出、圆点淡入并放大）；
/// ③ mac 在左侧时的重排（关闭挪到最前，三枚各自让位）。
/// 280ms / easeOutCubic：比 Fluent 的 250ms 略慢一点，让「对滑」看得清是谁换到哪边。
const Duration kWindowTitleBarSwitchDuration = Duration(milliseconds: 280);
const Curve kWindowTitleBarSwitchCurve = Curves.easeOutCubic;

/// 窗口窄于这个宽度（逻辑像素）时品牌只留 logo —— 三键是固定 46 宽、不能让的，
/// 窄窗口里再挤应用名就会让整条 Row 溢出（窗口没有最小宽度，能拖得很窄）。
/// 守卫 = `test/window_title_bar_test.dart`「窄窗口：品牌只留 logo，整条栏不溢出」。
const double kWindowTitleBarCompactWidth = 460;

/// 标题栏里**图标按钮的统一样式**：悬停 / 按下的高亮是**圆角矩形**而不是圆形
/// （用户 2026-10-10：「我希望图标按钮悬停时不要显示一个圆形高亮，而是一个圆角矩形高亮」）。
///
/// Material 的 `IconButton` 默认把 ink 画成**圆**（`StadiumBorder` / 圆形 ✓），在方方正正的
/// 标题栏里显得突兀；这里统一切成 6 圆角的矩形，圆角与卡片口径相近。
/// ⚠ 用例：`title_bar_history.dart` 的三枚（← → 🕘）、`home_screen.dart` 的侧栏开关、
/// 历史面板里的 📌 —— 新加图标按钮时也用它，别各写各的。
final ButtonStyle kTitleBarIconButtonStyle = IconButton.styleFrom(
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
);

/// 本平台是否画自绘标题栏（目前只有 Windows 桌面有原生实现）。
///
/// 判据取 `Theme.platform` 而不是 `defaultTargetPlatform`：与 `homeDesktopPlatform`
/// 同口径，widget 测试里换个主题就能按平台跑（不必改全局状态）。
/// 非 Windows（Android / iOS / Linux / macOS）一律**不画**：那边系统标题栏还在，
/// 再画一条只会凭空多出一条空栏。
bool windowTitleBarSupported(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.windows;

/// 标题栏底色 = AppBar 同色（浅色白 / 深色 `darkTopBar`），与下面的 AppBar 连成一条带。
Color windowTitleBarColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
}

/// `MaterialApp.builder` 上挂的全局 chrome：Windows 上「标题栏 + 应用内容」竖排。
///
/// 挂在 builder（而不是某个页面里）：标题栏必须在 Navigator **之上** —— 任何页面、
/// 任何弹层下都要能拖动 / 最大化 / 关闭窗口。
///
/// ⚠ **标题栏必须裹在自己的 `Overlay` 里**（2026-10-09 实测踩过，整个应用起不来）：
/// 页面动作区挂的「设置齿轮 / 头像」是 `IconButton`，`Tooltip` 在 **build 期间**
/// 就要求有 `Overlay` 祖先；而标题栏是 Navigator 的**兄弟**（在它之上），
/// navigator 那个 Overlay 不在它的祖先链上 → 首帧抛
/// `No Overlay widget found. Tooltip widgets require an Overlay widget ancestor`。
///
/// 后果比普通异常严重得多：Windows runner 是**首帧之后**才 `ShowWindow`，
/// 首帧抛异常就永远没有窗口（进程活着、`MainWindowHandle = 0`，看着像卡死）。
/// 所以这一层 `Overlay` 不是装饰，是启动的硬依赖。
///
/// ⚠ 另要求**原生侧应答过**（`nativeReady`）：旧 exe + 新 Dart 包这种版本错配下通道
/// 根本不存在，照画就会画出一条三键点不动的假标题栏（而系统标题栏也还在，屏幕上两条）。
/// 没应答 = 整条 chrome 不画，退回「只有系统标题栏」的旧观感。
class AppWindowChrome extends ConsumerWidget {
  const AppWindowChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!windowTitleBarSupported(context)) return child;
    if (!ref.watch(windowChromeProvider).nativeReady) return child;
    // ⚠ `Overlay` 必须**罩住整块 chrome**（标题栏 + 页面内容），不能只罩那 40 高的
    // 带子 —— 只罩带子时 `Tooltip`（它是以 overlay entry 的形式画出来的）会被
    // **Overlay 的边界裁掉**：用户 2026-10-09 报的「这几个按钮的悬浮显示都被标题栏
    // 边界裁切了」就是这个。罩住整块之后气泡画在内容区上方，完整可见（守卫见
    // `test/window_title_bar_test.dart` 的「Overlay 罩的是整块 chrome」）。
    //
    // 两层仍然都不能省（2026-10-09 实测，都是「整个应用起不来」级别）：
    // ① `Overlay`：页面动作区挂的「设置齿轮 / 头像」是 `IconButton`，`Tooltip` 在
    //    **build 期间**就要 `Overlay` 祖先；而标题栏是 Navigator 的**兄弟**（在它之上），
    //    navigator 那个 Overlay 不在它的祖先链上 → 首帧抛 `No Overlay widget found`。
    // ② `Material`：`AccountAvatar` 里是 `InkWell`，它要 `Material` 祖先画水波 →
    //    少了就抛 `No Material widget found`。
    //
    // ⚠ 带子高度必须**显式钉死**（`SizedBox`），不能用 `IntrinsicHeight` 去问：
    //    内联 `Overlay` 在高度方向没有上界，`IntrinsicHeight` 穿过 `_RenderTheatre`
    //    会算出天文数字（实测 `RenderFlex overflowed by 99044 pixels on the right`），
    //    整窗首帧崩 → runner 永远不 `ShowWindow`（进程活着、没有窗口，像卡死）。
    return Overlay(
      initialEntries: <OverlayEntry>[
        OverlayEntry(
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: kWindowTitleBarHeight,
                child: Material(
                  type: MaterialType.transparency,
                  child: const WindowTitleBar(),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ],
    );
  }
}
