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




import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/navigation/route_history.dart';

import 'package:smarter_jxufe/core/window/window_chrome.dart';
import 'package:smarter_jxufe/core/window/window_title_bar_actions.dart';
import 'package:smarter_jxufe/design/window_chrome/app_window_chrome.dart';
import 'package:smarter_jxufe/design/window_chrome/title_bar_history.dart';
import 'package:smarter_jxufe/design/window_chrome/title_bar_model.dart';
import 'package:smarter_jxufe/design/window_chrome/title_bar_regions.dart';
import 'package:smarter_jxufe/design/window_chrome/window_buttons.dart';
import 'package:smarter_jxufe/features/settings/data/window_bar_prefs.dart';

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

  /// 标题栏根节点 —— 所有交互区都折算到**它的坐标系**再上报（见 `title_bar_regions.dart`）。
  final GlobalKey _barKey = GlobalKey();

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
  @override
  Widget build(BuildContext context) {
    final store = ref.watch(windowBarPrefsProvider);
    final snapshot = ref.watch(windowChromeProvider);
    final actions = ref.watch(windowTitleBarActionsProvider);
    final history = ref.watch(routeHistoryProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 排布规则**全在模型里**（`title_bar_model.dart`）—— 这里只负责「照模型摆」。
        final model = TitleBarLayoutModel.compute(
          width: constraints.maxWidth,
          desktop: windowTitleBarSupported(context),
          style: store.style,
          swapSides: store.swapSides,
          hasActions: actions.visible,
          hasBrand: true,
          hasHistory: true,  // ← → 恒在（🕘 才看有没有历史）；见 build 里的注释
          hasSidebarToggle: actions.leadingVisible,
        );

        final actionsRow = actions.visible
            ? _region(_actionsToken, Builder(builder: actions.builder!), enabled: true)
            : null;
        // 中间组：侧栏开关 + 路由历史（宽屏恒居中；窄屏并入动作簇那一侧）。
        final centerRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (actions.leadingVisible) ...[
              _region(
                _leadingToken,
                Builder(builder: actions.leadingBuilder!),
                enabled: true,
              ),
              const SizedBox(width: 6),
            ],
              _region(_historyToken, const WindowTitleBarHistory(), enabled: true),
          ],
        );

        _queueLayoutSync();

        return Container(
          key: _barKey,
          height: kWindowTitleBarHeight,
          // ⚠ **不画底部分隔线**（用户 2026-10-09 六轮：「标题栏底部不要显示那根框线，
          // 从而让标题栏可以和侧边栏视觉上连续」）。
          decoration: BoxDecoration(color: windowTitleBarColor(context)),
          child: Stack(
            children: <Widget>[
              // 三键：位置只认偏好（模型保证窄屏也不动）。
              _zone(
                model.controls,
                WindowButtonsRow(
                  snapshot: snapshot,
                  style: store.style,
                  macOrderReversed: model.macOrderReversed,
                  macClusterOnLeft: model.controls == TitleBarSlot.left,
                  region: (token, child) =>
                      _region(token, child, enabled: true),
                ),
              ),
              // 动作簇：宽屏与三键同侧；窄屏在三键对侧，且**捎带**中间组（合并）。
              if (model.actions != TitleBarSlot.hidden)
                _zone(
                  model.actions,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (actionsRow != null) actionsRow,
                      if (model.narrow) centerRow,
                    ],
                  ),
                ),
              // 宽屏的中间组（窄屏时它已在上面那一坨里）。
              if (model.center != TitleBarSlot.hidden)
                _zone(model.center, centerRow),
              // 品牌：宽屏在三键对侧；窄屏 hidden（模型保证）。
              if (model.brand != TitleBarSlot.hidden)
                _zone(
                  model.brand,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _brand(
                      context,
                      compact: constraints.maxWidth < kWindowTitleBarCompactWidth,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 把一个区摆到模型给的槽位上（`hidden` 不该走到这里 —— 调用方已判过）。
  Widget _zone(TitleBarSlot slot, Widget child) => AnimatedAlign(
        alignment: switch (slot) {
          TitleBarSlot.left => Alignment.centerLeft,
          TitleBarSlot.center => Alignment.center,
          TitleBarSlot.right => Alignment.centerRight,
          TitleBarSlot.hidden => Alignment.center,
        },
        duration: kWindowTitleBarSwitchDuration,
        curve: kWindowTitleBarSwitchCurve,
        child: child,
      );

  /// 把一个子件登记成**交互区**（原生不接管，点击照常进 Flutter）。
  ///
  /// ⚠ 凡是栏里要响应点击的簇，都必须走这里 —— 顶栏其余部分是系统 caption
  /// （原生回 `HTCAPTION`），没登记就点不动（用户实测过「三个按钮都按不动」）。
  Widget _region(Object token, Widget child, {required bool enabled}) =>
      TitleBarRegion(
        key: ValueKey<Object>(token),
        barKey: _barKey,
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



}
