/// **窗口标题栏（自绘）** —— 隐藏系统标题栏之后的应用级 chrome。
///
/// 用户 2026-10-09 立项（原话：「把系统标题栏隐藏，然后让我们的顶部标题栏支持三键
/// （最小化/最大化/关闭）。然后让我们的顶部标题栏支持系统标题栏的各种特性」）。
///
/// 分工：**画与量在这里**，**命中测试在原生**（`windows/runner/window_chrome.cpp`）。
/// 本组件每帧把「标题栏高度 + 三键矩形 + 页面动作矩形」上报给原生，原生据此在
/// `WM_NCHITTEST` 里把标题栏带判成 `HTCAPTION`、三键判成
/// `HTMINBUTTON`/`HTMAXBUTTON`/`HTCLOSE` —— 于是拖动、双击最大化/还原、右键系统菜单、
/// Aero 贴靠、Win11 贴靠布局、边缘缩放全部由系统提供，Dart 侧一个手势都不用写。
/// 完整口径与实测台账见 `docs/agents/43-桌面窗口标题栏（隐藏系统标题栏·自绘三键·贴靠）.md`。
///
/// 两条硬约束（改之前先读）：
/// ① **三键的点击不由 Flutter 接**：原生把它们判成非客户区（`HTMAXBUTTON` 是 Win11
///    贴靠布局的官方契约），鼠标消息根本不进 Flutter —— 按钮的悬停 / 按下态是原生
///    用 `WM_NCMOUSEMOVE` / `WM_NCLBUTTONDOWN` 回推过来的（见 `WindowChromeSnapshot`）。
/// ② **标题栏里只有「页面动作」（首页的设置 / 头像）走客户区**：它们被上报成
///    `interactive` 矩形，原生不接管，Flutter 照常收鼠标事件（能点、能出 tooltip）。
library;

import 'dart:async';

import 'package:smarter_jxufe/core/navigation/route_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/window/window_chrome.dart';
import 'package:smarter_jxufe/core/window/window_title_bar_actions.dart';
import 'package:smarter_jxufe/features/settings/data/window_bar_prefs.dart';

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

/// 全局标题栏。
class WindowTitleBar extends ConsumerStatefulWidget {
  const WindowTitleBar({super.key});

  @override
  ConsumerState<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends ConsumerState<WindowTitleBar> {
  /// 本帧量到的矩形（逻辑像素，原点 = 客户区左上角），key 见下面四个常量。
  final Map<Object, Rect> _regions = <Object, Rect>{};
  bool _syncQueued = false;

  static const Object _minimizeToken = 'minimize';
  static const Object _maximizeToken = 'maximize';
  static const Object _closeToken = 'close';
  static const Object _actionsToken = 'actions';
  // 2026-10-09：新加的两簇也**必须**登记成 interactive 区域 —— 顶栏其余部分是系统
  // caption（原生回 HTCAPTION），没登记的控件点下去会被当成「拖窗口」吃掉
  // （用户实测：「顶部标题栏加的三个按钮都按不动」）。
  static const Object _leadingToken = 'leading';
  static const Object _historyToken = 'history';

  @override
  // ===== 以下到 `_WindowTitleBarState` 结束：整条栏的 build 与它的助手 =====
  // （2026-10-09 六轮事故后重建：原实现被一次错误的按行替换删掉，这里按
  //   `test/window_title_bar_test.dart` 的规格 + AGENTS §43 的口径写回。）

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(windowBarPrefsProvider);
    final snapshot = ref.watch(windowChromeProvider);
    final actions = ref.watch(windowTitleBarActionsProvider);
    final buttonsOnLeft = store.buttonsOnLeft;

    final buttons = _buildButtons(
      snapshot: snapshot,
      style: store.style,
      buttonsOnLeft: buttonsOnLeft,
    );
    final actionsRow = actions.visible
        ? _region(
            _actionsToken,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Builder(builder: actions.builder!),
            ),
            enabled: true,
          )
        : null;

    // 窄窗口：品牌只留 logo（应用名舍掉）—— 三键永远画满 46 宽，不跟它们抢地方，
    // 否则整条 Row 会溢出（窗口没有最小宽度限制，能拖得很窄）。
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < kWindowTitleBarCompactWidth;
        final brand = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 侧栏开关（页面经插槽发布，画在 logo 左边）。
              if (actions.leadingVisible) ...[
                _region(
                  _leadingToken,
                  Builder(builder: actions.leadingBuilder!),
                  enabled: true,
                ),
                const SizedBox(width: 2),
              ],
              _brand(context, compact: compact),
              const SizedBox(width: 6),
              // 全局路由历史（← → 🕘）。
              _region(_historyToken, const WindowTitleBarHistory(), enabled: true),
            ],
          ),
        );

        // ⚠ 两组各自 `AnimatedAlign` 在两端之间滑动（不是 Row + Spacer）—— 换位置
        // 那一帧若直接改 Row 的顺序就是**瞬移**；这里两组反向对滑，看着才是「交换」。
        // 动作区永远跟着三键那一组（同一头的窗口级操作）。
        final controlsChildren = <Widget>[
          if (buttonsOnLeft) buttons,
          if (buttonsOnLeft && actionsRow != null) actionsRow,
          if (!buttonsOnLeft && actionsRow != null) actionsRow,
          if (!buttonsOnLeft) buttons,
        ];

        _queueLayoutSync();

        return Container(
          height: kWindowTitleBarHeight,
          // ⚠ **不画底部分隔线**（用户 2026-10-09 六轮：「标题栏底部不要显示那根框线，
          // 从而让标题栏可以和侧边栏视觉上连续」）。
          decoration: BoxDecoration(color: windowTitleBarColor(context)),
          child: Stack(
            children: <Widget>[
              AnimatedAlign(
                alignment: buttonsOnLeft
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                duration: kWindowTitleBarSwitchDuration,
                curve: kWindowTitleBarSwitchCurve,
                child: SizedBox(
                  height: kWindowTitleBarHeight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: controlsChildren,
                  ),
                ),
              ),
              AnimatedAlign(
                alignment: buttonsOnLeft
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                duration: kWindowTitleBarSwitchDuration,
                curve: kWindowTitleBarSwitchCurve,
                child: brand,
              ),
            ],
          ),
        );
      },
    );
  }

  /// 把一个子件登记成**交互区**（原生不接管，点击照常进 Flutter）。
  ///
  /// ⚠ 凡是栏里要响应点击的簇，都必须走这里 —— 顶栏其余部分是系统 caption
  /// （原生回 `HTCAPTION`），没登记就点不动（用户实测过「三个按钮都按不动」）。
  Widget _region(Object token, Widget child, {required bool enabled}) =>
      _TitleBarRegion(
        key: ValueKey<Object>(token),
        token: token,
        sink: _regions,
        enabled: enabled,
        onMeasured: _queueLayoutSync,
        child: child,
      );

  /// 每帧结束后把几何推给原生（值没变时控制器自己跳过，不会刷通道）。
  void _queueLayoutSync() {
    if (_syncQueued) return;
    _syncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncQueued = false;
      if (!mounted) return;
      _syncLayout();
    });
  }

  void _syncLayout() {
    final controller = ref.read(windowChromeProvider.notifier);
    final minimize = _regions[_minimizeToken];
    final maximize = _regions[_maximizeToken];
    final close = _regions[_closeToken];
    if (minimize == null || maximize == null || close == null) {
      // 还没量到（首帧之前 / 本组件被折叠）→ 上报「没有标题栏」：宁可少一个拖动区，
      // 也不要让一条看不见的带子把点击吃掉（原生侧 enabled=false = 整窗都是客户区）。
      unawaited(controller.syncLayout(null));
      return;
    }
    unawaited(
      controller.syncLayout(
        WindowTitleBarLayout(
          height: kWindowTitleBarHeight,
          minimize: minimize,
          maximize: maximize,
          close: close,
          // ⚠ 这里**必须逐个列出**：原生只把上报名单里的矩形当客户区，其余一律
          // `HTCAPTION`（拖窗口）。漏一个 = 那一簇按钮点不动。
          interactive: <Rect>[
            ?_regions[_actionsToken],
            ?_regions[_leadingToken],
            ?_regions[_historyToken],
          ],
        ),
      ),
    );
  }

  /// 品牌位：logo + 应用名。
  ///
  /// [compact] = 窗口太窄（< [kWindowTitleBarCompactWidth]）→ 只留 logo：三键是固定
  /// 46 宽、不能让的，窄窗口里再挤应用名就会让整条 Row 溢出。
  Widget _brand(BuildContext context, {required bool compact}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/images/brand/logo.png',
              width: 24,
              height: 24,
              filterQuality: FilterQuality.medium,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                '智慧er江财',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      );

  /// 三键簇：Win 风格 = 46 宽的方键（codicon 字形）；mac 风格 = 20 宽的槽 + 12 的圆点。
  ///
  /// 两项设置的切换都是动画的（同一份 t 驱动两层交叉淡入淡出）：
  /// t=0 → Win 方键，t=1 → mac 圆点；mac 在左侧时三枚用 `AnimatedPositioned` 让位。
  Widget _buildButtons({
    required WindowChromeSnapshot snapshot,
    required WindowButtonsStyle style,
    required bool buttonsOnLeft,
  }) {
    final isMac = style == WindowButtonsStyle.mac;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: isMac ? 1 : 0, end: isMac ? 1 : 0),
      duration: kWindowTitleBarSwitchDuration,
      curve: kWindowTitleBarSwitchCurve,
      builder: (context, t, _) {
        // mac 且贴边的那一侧要留出「整组留白」（与圆点距上下边的留白一致）。
        final clusterInset = kWindowTitleBarMacClusterInset * t;
        final children = <Widget>[
          // mac 惯例：左侧时顺序是「关闭 / 最小化 / 最大化」。
          if (isMac && buttonsOnLeft) ...[
            _macDot(snapshot, WindowTitleBarButton.close),
            _macDot(snapshot, WindowTitleBarButton.minimize),
            _macDot(snapshot, WindowTitleBarButton.maximize),
          ] else ...[
            _winKey(snapshot, WindowTitleBarButton.minimize, t),
            _winKey(snapshot, WindowTitleBarButton.maximize, t),
            _winKey(snapshot, WindowTitleBarButton.close, t),
          ],
        ];
        return AnimatedPadding(
          duration: kWindowTitleBarSwitchDuration,
          curve: kWindowTitleBarSwitchCurve,
          padding: buttonsOnLeft
              ? EdgeInsets.only(left: clusterInset)
              : EdgeInsets.only(right: clusterInset),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        );
      },
    );
  }

  /// Win 风格的一枚方键（46 宽，高度撑满栏）。[t] = 1 时「收成」圆点（交叉淡出）。
  Widget _winKey(WindowChromeSnapshot snapshot, WindowTitleBarButton button, double t) {
    final token = switch (button) {
      WindowTitleBarButton.minimize => _minimizeToken,
      WindowTitleBarButton.maximize => _maximizeToken,
      WindowTitleBarButton.close => _closeToken,
    };
    return _region(
      token,
      _WindowButton(
        snapshot: snapshot,
        button: button,
        style: WindowButtonsStyle.windows,
        macReveal: t,
      ),
      enabled: true,
    );
  }

  /// mac 风格的一枚圆点（槽 20 宽、圆点 12，居中）。
  Widget _macDot(WindowChromeSnapshot snapshot, WindowTitleBarButton button) {
    final token = switch (button) {
      WindowTitleBarButton.minimize => _minimizeToken,
      WindowTitleBarButton.maximize => _maximizeToken,
      WindowTitleBarButton.close => _closeToken,
    };
    return _region(
      token,
      _WindowButton(
        snapshot: snapshot,
        button: button,
        style: WindowButtonsStyle.mac,
        macReveal: 1,
      ),
      enabled: true,
    );
  }
}

/// 标题栏里的一个「交互区」：量到自己的矩形就交给原生（客户区，原生不接管）。
///
/// ⚠ 上报放在 `paint` 里：`AnimatedAlign` / `AnimatedContainer` 只驱动 RenderObject、
/// **不重建 State** —— 若只在 `build` 里量，动画期间原生拿的还是旧矩形（按钮滑走了、
/// 点到旧位置才响应；实测踩过）。这里发现矩形变了就回调一次 `onMeasured` 补上报。
class _TitleBarRegion extends SingleChildRenderObjectWidget {
  const _TitleBarRegion({
    super.key,
    required this.token,
    required this.sink,
    required this.enabled,
    required this.onMeasured,
    super.child,
  });

  final Object token;
  final Map<Object, Rect> sink;
  final bool enabled;
  final VoidCallback onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTitleBarRegion(
        token: token,
        sink: sink,
        enabled: enabled,
        onMeasured: onMeasured,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderTitleBarRegion renderObject) {
    renderObject
      ..token = token
      ..sink = sink
      ..enabled = enabled
      ..onMeasured = onMeasured;
  }
}

class _RenderTitleBarRegion extends RenderProxyBox {
  _RenderTitleBarRegion({
    required this.token,
    required this.sink,
    required this.enabled,
    required this.onMeasured,
  });

  Object token;
  Map<Object, Rect> sink;
  bool enabled;
  VoidCallback onMeasured;
  Rect? _last;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (enabled) {
      final rect = offset & size;
      if (rect != _last) {
        _last = rect;
        sink[token] = rect;
        onMeasured();
      }
    } else if (_last != null) {
      _last = null;
      sink.remove(token);
      onMeasured();
    }
    super.paint(context, offset);
  }

  @override
  void detach() {
    sink.remove(token);
    super.detach();
  }
}

/// 三键之一（**纯视觉**：点击由原生处理，悬停 / 按下态由原生推回）。
class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.snapshot,
    required this.button,
    required this.style,
    required this.macReveal,
  });

  final WindowChromeSnapshot snapshot;
  final WindowTitleBarButton button;
  final WindowButtonsStyle style;
  /// Win 方键「收成」圆点的进度（0 = 方键，1 = 圆点）。
  final double macReveal;

  String get _id => switch (button) {
        WindowTitleBarButton.minimize => 'minimize',
        WindowTitleBarButton.maximize => 'maximize',
        WindowTitleBarButton.close => 'close',
      };

  @override
  Widget build(BuildContext context) {
    final hovered = snapshot.hovered == button;
    final pressed = snapshot.pressed == button;
    final active = hovered || pressed;
    final scheme = Theme.of(context).colorScheme;

    if (style == WindowButtonsStyle.mac) {
      final fill = switch (button) {
        WindowTitleBarButton.close => const Color(0xFFFF5F57),
        WindowTitleBarButton.minimize => const Color(0xFFFEBC2E),
        WindowTitleBarButton.maximize => const Color(0xFF28C840),
      };
      return SizedBox(
        width: kWindowTitleBarMacSlot,
        height: kWindowTitleBarHeight,
        child: Center(
          child: Container(
            width: kWindowTitleBarMacDot,
            height: kWindowTitleBarMacDot,
            decoration: BoxDecoration(
              color: snapshot.active ? fill : fill.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    // Win：46 宽的方键；悬停给淡底、关闭键悬停变红（原生 Windows 的口径）。
    final isClose = button == WindowTitleBarButton.close;
    final background = active
        ? (isClose ? const Color(0xFFC42B1C) : scheme.onSurface.withValues(alpha: 0.09))
        : Colors.transparent;
    final glyph = switch (button) {
      WindowTitleBarButton.minimize => Codicons.chromeMinimize,
      WindowTitleBarButton.maximize => snapshot.maximized
          ? Codicons.chromeRestore
          : Codicons.chromeMaximize,
      WindowTitleBarButton.close => Codicons.chromeClose,
    };
    return Container(
      width: kWindowTitleBarButtonWidth,
      height: kWindowTitleBarHeight,
      color: background,
      child: Center(
        child: Opacity(
          opacity: 1 - macReveal,
          child: Icon(
            glyph,
            size: kWindowTitleBarGlyphSize,
            color: isClose && active ? Colors.white : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
/// Windows 三键的 **codicon** 字形（用户 2026-10-09 指定「照 vshell」）。
///
/// ⚠ **跨语言契约**：`assets/fonts/codicon-titlebar.ttf` 只裁了这四个字形，`pubspec.yaml`
/// 以 `codicon` 注册（子集命令与来源留在 pubspec 注释里）。守卫 =
/// `test/window_title_bar_test.dart` 的「codicon 子集字体」+「跨语言契约」两组。
class Codicons {
  const Codicons._();

  static const IconData chromeMinimize =
      IconData(0xeaba, fontFamily: 'codicon');
  static const IconData chromeMaximize =
      IconData(0xeab9, fontFamily: 'codicon');
  static const IconData chromeRestore =
      IconData(0xeabb, fontFamily: 'codicon');
  static const IconData chromeClose = IconData(0xeab8, fontFamily: 'codicon');
}
/// 顶部那条栏里的**全局路由历史**控件（`←` `→` `🕘`）。
///
/// - `←` / `→`：不可用时 `onPressed: null`（**禁用而不是藏起来** —— 藏起来会让按钮左右
///   横跳，禁用还能当「这里能回退」的提示）。
/// - `🕘`：历史面板（git 图），鼠标停上去 260ms 自动展开，点一下也能开关；面板里有 📌
///   可固定（固定后移开鼠标、点外面都不收）。
/// - ⚠ **不能用 `PopupMenuButton`**（用户实测「点击路由历史按钮无反应」）：它靠
///   `Navigator.push` 弹菜单，而标题栏挂在 `MaterialApp.builder` 上、是 Navigator 的
///   **兄弟** → 找不到 Navigator，菜单永远弹不出来。这里用 `OverlayPortal`（插进最近的
///   Overlay = `AppWindowChrome` 那个罩住整块 chrome 的 Overlay），既不需要 Navigator，
///   又能画到栏外、还能被点到。
/// - ⚠ 悬浮展开后**关闭要延迟**（用户实测「从历史按钮上移开就会让面板消失，不能移动到
///   面板上」）：按钮与面板是两棵子树（面板在 Overlay 里、中间还隔着一道缝），移出按钮
///   的那一瞬间就 `hide()` 的话鼠标根本来不及挪进面板。给 [_hoverCloseDelay] 宽限，
///   鼠标一进面板就取消它。
class WindowTitleBarHistory extends ConsumerStatefulWidget {
  const WindowTitleBarHistory({super.key});

  @override
  ConsumerState<WindowTitleBarHistory> createState() =>
      _WindowTitleBarHistoryState();
}

class _WindowTitleBarHistoryState extends ConsumerState<WindowTitleBarHistory> {
  final OverlayPortalController _panel = OverlayPortalController();

  /// 面板挂在按钮下方（`CompositedTransformFollower`）。
  final LayerLink _link = LayerLink();

  /// 钉住（用户 2026-10-09：「点击固定按钮固定不再消失」）。
  ///
  /// ⚠ 用 `ValueNotifier` 而不是 `setState`（用户同日三轮：「点击固定按钮后页面闪动」）：
  /// `setState` 会重建整条标题栏 → `OverlayPortal` 的 overlay 子件被拆挂一次 → 遮罩与
  /// 面板肉眼可见地闪一下。`ValueListenableBuilder` 只重建它自己那几行。
  final ValueNotifier<bool> _pinned = ValueNotifier<bool>(false);

  Timer? _hoverOpenTimer;
  Timer? _hoverCloseTimer;

  /// 悬浮 260ms 才展开 —— 鼠标只是扫过标题栏时不弹（不然很吵）。
  static const Duration _hoverOpenDelay = Duration(milliseconds: 260);

  /// 移出后的宽限：够鼠标从按钮挪到面板上。
  static const Duration _hoverCloseDelay = Duration(milliseconds: 320);

  @override
  void dispose() {
    _hoverOpenTimer?.cancel();
    _hoverCloseTimer?.cancel();
    _pinned.dispose();
    super.dispose();
  }

  void _onEnter() {
    _hoverCloseTimer?.cancel();
    _hoverCloseTimer = null;
    if (_panel.isShowing) return;
    _hoverOpenTimer?.cancel();
    _hoverOpenTimer = Timer(_hoverOpenDelay, () {
      if (!mounted) return;
      if (ref.read(routeHistoryProvider).isEmpty) return;
      _panel.show();
    });
  }

  void _onExit() {
    _hoverOpenTimer?.cancel();
    if (_pinned.value) return;
    _hoverCloseTimer?.cancel();
    _hoverCloseTimer = Timer(_hoverCloseDelay, () {
      if (!mounted || _pinned.value) return;
      _panel.hide();
    });
  }

  /// 点面板外面：收起（钉住了就不收）。
  void _closeByOutsideTap() {
    if (_pinned.value) return;
    _panel.hide();
  }

  Widget build(BuildContext context) {
    final history = ref.watch(routeHistoryProvider);
    final scheme = Theme.of(context).colorScheme;
    final iconColor = scheme.onSurfaceVariant;

    Widget button({
      required Key key,
      required IconData icon,
      String? tooltip,
      VoidCallback? onTap,
    }) =>
        IconButton(
          key: key,
          tooltip: tooltip,
          icon: Icon(icon, size: 17),
          color: iconColor,
          disabledColor: iconColor.withValues(alpha: 0.35),
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          splashRadius: 14,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(
          key: const Key('windowTitleBarBack'),
          icon: Icons.arrow_back_rounded,
          tooltip: history.canGoBack
              ? '后退（回到上一个页面）'
              : '后退（还没有可回退的页面）',
          onTap: history.canGoBack ? history.goBack : null,
        ),
        button(
          key: const Key('windowTitleBarForward'),
          icon: Icons.arrow_forward_rounded,
          tooltip: history.canGoForward
              ? '前进（回到后退前那一页）'
              : '前进（先后退一次才有可前进的页面）',
          onTap: history.canGoForward ? history.goForward : null,
        ),
        if (!history.isEmpty)
          CompositedTransformTarget(
            link: _link,
            child: MouseRegion(
              onEnter: (_) => _onEnter(),
              onExit: (_) => _onExit(),
              child: OverlayPortal(
                controller: _panel,
                overlayChildBuilder: (context) => CompositedTransformFollower(
                  link: _link,
                  // 面板左上角贴在按钮左下角，只留 2px —— 用户两次说「太远」，
                  // 所以这里刻意紧贴（改动前是 4）。
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: const Offset(0, 2),
                  child: Align(
                    alignment: Alignment.topLeft,
                    // ⚠ 两块：全屏透明屏障（点外面收起）+ 面板本体。
                    // 面板外面再垫一层 `ColoredBox(transparent)`：它**参与命中测试**，
                    // 于是「按钮 → 那道 2px 缝 → 面板」连成一整块悬停区，鼠标挪下来
                    // 不会在中途被判成「移出」（配 `_hoverCloseDelay` 双保险）。
                    child: Stack(
                      children: [
                        // 遮罩常驻，钉住时只是不响应（拆掉再装上也会闪）。
                        Positioned.fill(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _pinned,
                            builder: (_, pinned, _) => IgnorePointer(
                              ignoring: pinned,
                              child: GestureDetector(
                                key: const Key('windowTitleBarHistoryBarrier'),
                                behavior: HitTestBehavior.opaque,
                                onTap: _closeByOutsideTap,
                              ),
                            ),
                          ),
                        ),
                        MouseRegion(
                          onEnter: (_) => _onEnter(),
                          onExit: (_) => _onExit(),
                          child: ColoredBox(
                            color: Colors.transparent,
                            child: _panelBody(context, history, scheme),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                child: button(
                  key: const Key('windowTitleBarHistoryMenu'),
                  icon: Icons.history_rounded,
                  onTap: _panel.isShowing ? _panel.hide : _panel.show,
                ),
              ),
            ),
          ),
      ],
    );
  }
  /// 历史面板本体：**一张 git 提交图**（用户 2026-10-09：「我希望这个历史直接显示一个
  /// git 图」）—— 左侧一条竖线 + 节点，右边是那一格的名字；顶上一行是标题 + 固定按钮。
  ///
  /// 三条着色口径（照着 git 图的读法）：
  /// - **游标所在那一笔**：实心大点 + 外圈；
  /// - **祖先链上的路**（`activePathIndices()`）：实心小点 + 主色线；
  /// - **其余**（另一条分支 / 还没前进回去的尾巴）：空心点 + 灰线；其中「前进会去的那一笔」
  ///   额外套一圈主色，分叉之后一眼看出前进走哪支。
  Widget _panelBody(
    BuildContext context,
    RouteHistory history,
    ColorScheme scheme,
  ) {
    final total = history.entries.length;
    final activePath = history.activePathIndices();
    final forwardTarget = history.forwardTargetIndex;
    return Material(
      key: const Key('windowTitleBarHistoryPanel'),
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerHigh,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(minWidth: 200, maxWidth: 320, maxHeight: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题行 + 固定按钮。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 2),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                      '路由历史',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(width: 6),
                  ValueListenableBuilder<bool>(
                    valueListenable: _pinned,
                    builder: (_, pinned, _) => IconButton(
                    key: const Key('windowTitleBarHistoryPin'),
                    icon: Icon(
                      pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 15,
                    ),
                    color: pinned ? scheme.primary : scheme.onSurfaceVariant,
                    // 不 setState（见 _pinned 的注释）：只让这一枚和遮罩自己重建。
                    onPressed: () => _pinned.value = !_pinned.value,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 26, height: 26),
                    splashRadius: 12,
                  ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < total; i++)
                      InkWell(
                        key: Key('windowTitleBarHistoryItem$i'),
                        onTap: history.entries[i].canRestore
                            ? () {
                                history.goTo(i);
                                if (!_pinned.value) _panel.hide();
                              }
                            : null,
                        child: SizedBox(
                          height: 30,
                          child: Row(
                            // ⚠ 必须 stretch：Row 默认给子件**松约束**，裸 `CustomPaint`
                            // 于是高度算成 0 —— 节点画得出来、竖线长度 0（实测就是
                            // 「有红点没线」）。拉满之后沟槽才是 30 高，线才有得画。
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                // 每条泳道 14 宽，再加左右各 8 的边距。
                                width: 16.0 + history.laneCount * 14,
                                child: CustomPaint(
                                  painter: _HistoryGraphPainter(
                                    index: i,
                                    current: history.index,
                                    total: total,
                                    lane: history.laneOf(i),
                                    active: activePath.contains(i),
                                    isForwardTarget: i == forwardTarget,
                                    activePath: activePath,
                                    parentIndex: history.parentIndexOf(i),
                                    parentLane: history.parentIndexOf(i) >= 0
                                        ? history.laneOf(history.parentIndexOf(i))
                                        : 0,
                                    activeColor: scheme.primary,
                                    idleColor: scheme.outlineVariant,
                                    dimColor: scheme.outline,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  history.entries[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: history.entries[i].canRestore
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                    fontWeight: i == history.index
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _HistoryGraphPainter extends CustomPainter {
  const _HistoryGraphPainter({
    required this.index,
    required this.current,
    required this.total,
    required this.lane,
    required this.active,
    required this.isForwardTarget,
    required this.activePath,
    required this.parentIndex,
    required this.parentLane,
    required this.activeColor,
    required this.idleColor,
    required this.dimColor,
  });

  final int index;
  final int current;
  final int total;

  /// 本笔的泳道（0 = 主干）。
  final int lane;

  /// 本笔是否在「根 → 游标」那条祖先链上（**亮不亮就看它**，别看列表下标）。
  final bool active;

  /// 是不是「前进」会去的那一笔（分叉后标出来）。
  final bool isForwardTarget;

  /// 整条祖先链（判断父节点亮不亮要用）。
  final Set<int> activePath;

  /// 父节点在列表里的下标（-1 = 没有父）。
  final int parentIndex;
  final int parentLane;

  final Color activeColor;
  final Color idleColor;
  final Color dimColor;

  static const double _rowHeight = 30;
  static const double _laneStep = 14;

  double _x(int lane) => 8 + lane * _laneStep;

  @override
  void paint(Canvas canvas, Size size) {
    final node = Offset(_x(lane), size.height / 2);
    final isCurrent = index == current;

    // 连到父节点那一段（跨泳道 = 曲线，见下）。
    if (parentIndex >= 0) {
      final parentY = node.dy - (index - parentIndex) * _rowHeight;
      final parent = Offset(_x(parentLane), parentY);
      final parentActive = activePath.contains(parentIndex);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        // 一段线只有在**两端都在祖先链上**时才算「走过的路」（其余是另一条分支 / 尾巴）。
        ..color = (active && parentActive)
            ? activeColor.withValues(alpha: 0.85)
            : idleColor;
      if (parentLane == lane) {
        canvas.drawLine(node, parent, paint);
      } else {
        // 分叉**不画直斜线**（用户 2026-10-09）——三次贝塞尔：两端各留一半做
        // 「先竖后弯 / 先弯后竖」，是从主干弯出去的一条弧，控制点只在 y 上偏移，
        // 所以不会横向甩出去。
        final dy = node.dy - parent.dy;
        canvas.drawPath(
          Path()
            ..moveTo(node.dx, node.dy)
            ..cubicTo(node.dx, node.dy - dy * 0.5, parent.dx,
                parent.dy + dy * 0.5, parent.dx, parent.dy),
          paint,
        );
      }
    }

    // 节点：当前 = 实心大点 + 外圈；走过的 = 实心小点；其余（另一支 / 还没前进回去
    // 的尾巴）= 空心点。
    if (isCurrent) {
      canvas.drawCircle(node, 6.5, Paint()..color = activeColor);
      canvas.drawCircle(
        node,
        6.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = activeColor.withValues(alpha: 0.35),
      );
    } else if (active) {
      canvas.drawCircle(node, 4.5, Paint()..color = activeColor);
    } else {
      canvas.drawCircle(
        node,
        4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = isForwardTarget ? activeColor : dimColor,
      );
    }
    // 「前进」的目标额外套一圈 —— 分叉之后点前进会走这一支，得让人看出来。
    if (isForwardTarget && !isCurrent) {
      canvas.drawCircle(
        node,
        7.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = activeColor.withValues(alpha: 0.7),
      );
    }
    assert(total >= 0);
  }

  @override
  bool shouldRepaint(_HistoryGraphPainter old) =>
      old.index != index ||
      old.current != current ||
      old.total != total ||
      old.lane != lane ||
      old.active != active ||
      old.isForwardTarget != isForwardTarget ||
      old.parentIndex != parentIndex ||
      old.parentLane != parentLane ||
      old.activeColor != activeColor;
}
