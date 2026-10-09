/// 自绘窗口标题栏的 **Dart 侧地基件**：平台通道 + 窗口状态 + 命中区上报。
///
/// 用户 2026-10-09 立项（原话：「把系统标题栏隐藏，然后让我们的顶部标题栏支持三键
/// （最小化/最大化/关闭）。然后让我们的顶部标题栏支持系统标题栏的各种特性」）。
///
/// 分工（**改这里之前先读 `docs/agents/43-桌面窗口标题栏（隐藏系统标题栏·自绘三键·贴靠）.md`**）：
/// - **原生侧**（`windows/runner/window_chrome.cpp`）只做三件事：把系统标题栏藏掉
///   （`WM_NCCALCSIZE`）、把标题栏带 / 三键 / 缩放边框的**命中测试**交回系统
///   （`WM_NCHITTEST` → `HTCAPTION` / `HTMINBUTTON` / `HTMAXBUTTON` / `HTCLOSE` /
///   `HTLEFT`…），以及把「悬停 / 按下 / 最大化 / 失焦」这些状态回推给 Dart。
/// - **Dart 侧**（本文件 + `lib/design/window_title_bar.dart`）负责**画**，并把
///   量到的几何上报给原生 —— 两端共用同一份矩形，点哪儿就是哪儿。
///
/// 为什么命中测试不自己写：`HTMAXBUTTON` 是 Win11 贴靠布局（悬停最大化按钮弹贴靠
/// 面板）的**官方契约**，`HTCAPTION` 又白送拖动、双击最大化/还原、右键系统菜单、
/// Aero 贴靠 —— 全交回系统，比自己实现一遍更原生（见 MS Learn《Support snap
/// layouts for desktop apps on Windows 11》）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 通道名（原生 `kChannelName` 必须与它逐字一致）。
const String kWindowChromeChannelName = 'smarter_jxufe/window_chrome';

/// 通道本身（测试用 `setMockMethodCallHandler` 替换）。
const MethodChannel kWindowChromeChannel = MethodChannel(
  kWindowChromeChannelName,
);

/// 三键标识（与原生 `kButtonMinimize` / `kButtonMaximize` / `kButtonClose` 一致）。
enum WindowTitleBarButton { minimize, maximize, close }

/// 名字 → 枚举；认不出（含 null）= 没有按钮处于悬停/按下态。
WindowTitleBarButton? windowTitleBarButtonFromName(String? name) {
  if (name == null || name.isEmpty) return null;
  for (final button in WindowTitleBarButton.values) {
    if (button.name == name) return button;
  }
  return null;
}

/// 本平台是否有**原生实现**（目前只有 Windows 桌面；Android / iOS 没有窗口 chrome，
/// Linux / macOS 未实现 → 一律保持系统标题栏，Dart 侧也不画）。
bool get windowChromeSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// 标题栏几何（**逻辑像素**，原点 = 客户区左上角）。三键矩形按**功能**给，
/// 与它们在左边还是右边无关（左右互换只是画的位置变了）。
@immutable
class WindowTitleBarLayout {
  const WindowTitleBarLayout({
    required this.height,
    required this.minimize,
    required this.maximize,
    required this.close,
    this.interactive = const <Rect>[],
  });

  /// 标题栏高度（= 原生侧「标题栏带」的厚度）。
  final double height;

  final Rect minimize;
  final Rect maximize;
  final Rect close;

  /// 标题栏里**仍然属于客户区**的矩形（首页的设置 / 头像等）。
  ///
  /// 这些位置原生侧不接管：Flutter 照常收到鼠标事件（能点、能出 tooltip）。
  final List<Rect> interactive;

  Map<String, Object?> toMap() => <String, Object?>{
    'enabled': true,
    'height': height,
    'minimize': _rectToMap(minimize),
    'maximize': _rectToMap(maximize),
    'close': _rectToMap(close),
    'interactive': <Object?>[for (final rect in interactive) _rectToMap(rect)],
  };

  static List<double> _rectToMap(Rect rect) => <double>[
    rect.left,
    rect.top,
    rect.right,
    rect.bottom,
  ];

  @override
  bool operator ==(Object other) =>
      other is WindowTitleBarLayout &&
      other.height == height &&
      other.minimize == minimize &&
      other.maximize == maximize &&
      other.close == close &&
      listEquals(other.interactive, interactive);

  @override
  int get hashCode => Object.hash(
    height,
    minimize,
    maximize,
    close,
    Object.hashAll(interactive),
  );
}

/// 窗口状态 + 三键的悬停 / 按下（原生推，Dart 只读）。
@immutable
class WindowChromeSnapshot {
  const WindowChromeSnapshot({
    this.maximized = false,
    this.minimized = false,
    this.active = true,
    this.hovered,
    this.pressed,
    this.nativeReady = false,
  });

  /// 是否最大化（决定三键中间那枚画「最大化」还是「还原」）。
  final bool maximized;

  /// 是否已最小化。
  final bool minimized;

  /// 窗口是否处于激活态（失焦时三键不该有悬停高亮 —— 原生就是这个规矩）。
  final bool active;

  /// 当前悬停的三键（原生 `WM_NCMOUSEMOVE` 推上来）。
  final WindowTitleBarButton? hovered;

  /// 当前按下的三键（按下后滑出去再松手 = 取消，原生同理）。
  final WindowTitleBarButton? pressed;

  /// **原生侧应答过没有**（判据 = `getWindowState` 有回值，或收到过任何原生事件）。
  ///
  /// 兜住「旧 exe + 新 Dart 包」这种错配：那时通道根本不存在，Dart 侧照画就会画出一条
  /// **三键点不动**的假标题栏（而且系统标题栏还在，屏幕上两条）。没应答 = 整条 chrome
  /// 不画，退回「只有系统标题栏」的旧观感 —— 宁可少一条栏，也不要给个能看不能点的。
  final bool nativeReady;

  bool isHovered(WindowTitleBarButton button) => active && hovered == button;
  bool isPressed(WindowTitleBarButton button) => active && pressed == button;

  WindowChromeSnapshot copyWith({
    bool? maximized,
    bool? minimized,
    bool? active,
    WindowTitleBarButton? hovered,
    WindowTitleBarButton? pressed,
    bool? nativeReady,
    bool clearHovered = false,
    bool clearPressed = false,
  }) => WindowChromeSnapshot(
    maximized: maximized ?? this.maximized,
    minimized: minimized ?? this.minimized,
    active: active ?? this.active,
    hovered: clearHovered ? null : (hovered ?? this.hovered),
    pressed: clearPressed ? null : (pressed ?? this.pressed),
    nativeReady: nativeReady ?? this.nativeReady,
  );

  @override
  bool operator ==(Object other) =>
      other is WindowChromeSnapshot &&
      other.maximized == maximized &&
      other.minimized == minimized &&
      other.active == active &&
      other.hovered == hovered &&
      other.pressed == pressed &&
      other.nativeReady == nativeReady;

  @override
  int get hashCode =>
      Object.hash(maximized, minimized, active, hovered, pressed, nativeReady);
}

/// 窗口 chrome 的唯一控制器。
///
/// 只做两件事：① 把标题栏几何推给原生（**值没变就一条消息都不发** —— 每帧都推会
/// 把通道刷爆）；② 接原生推上来的窗口状态 / 三键状态。
class WindowChromeController extends Notifier<WindowChromeSnapshot> {
  WindowTitleBarLayout? _lastSent;
  bool _lastEnabled = false;

  @override
  WindowChromeSnapshot build() {
    if (windowChromeSupported) {
      kWindowChromeChannel.setMethodCallHandler(_onPlatformCall);
      ref.onDispose(() {
        kWindowChromeChannel.setMethodCallHandler(null);
      });
      unawaited(_pullState());
    }
    return const WindowChromeSnapshot();
  }

  /// 上报标题栏几何；`null` = 本帧量不到（或平台没有标题栏）→ 告诉原生
  /// 「整窗都是客户区」，宁可少一个拖动区，也不要让点击被一个看不见的带子吃掉。
  Future<void> syncLayout(WindowTitleBarLayout? layout) async {
    if (!windowChromeSupported) return;
    if (layout == null) {
      if (!_lastEnabled) return;
      _lastEnabled = false;
      _lastSent = null;
      await _invoke('setTitleBarLayout', <String, Object?>{'enabled': false});
      return;
    }
    if (_lastEnabled && layout == _lastSent) return;
    _lastEnabled = true;
    _lastSent = layout;
    await _invoke('setTitleBarLayout', layout.toMap());
  }

  Future<void> _pullState() async {
    try {
      final raw = await kWindowChromeChannel.invokeMethod<Object?>(
        'getWindowState',
      );
      if (raw is Map) {
        // 有回值 = 原生侧确实在（旧 exe + 新 Dart 包时这里会抛 MissingPluginException）。
        state = _mergeState(
          state,
          raw,
        ).copyWith(nativeReady: true);
      }
    } on MissingPluginException {
      // 没有原生实现（非 Windows / 单测 / exe 与 Dart 包版本错配）→ 保持默认值，不吵。
    } catch (_) {}
  }

  Future<void> _invoke(String method, Object? arguments) async {
    try {
      await kWindowChromeChannel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      // 同上：没有原生实现时静默降级。
    } catch (_) {}
  }

  Future<void> _onPlatformCall(MethodCall call) async {
    final arguments = call.arguments;
    final map = arguments is Map ? arguments : const <Object?, Object?>{};
    switch (call.method) {
      case 'windowState':
        state = _mergeState(state, map).copyWith(nativeReady: true);
      case 'titleBarPointer':
        state = _mergePointer(state, map).copyWith(nativeReady: true);
    }
  }

  static WindowChromeSnapshot _mergeState(
    WindowChromeSnapshot current,
    Map<Object?, Object?> raw,
  ) {
    bool read(Object? value, bool fallback) =>
        value is bool ? value : fallback;
    return current.copyWith(
      maximized: read(raw['maximized'], current.maximized),
      minimized: read(raw['minimized'], current.minimized),
      active: read(raw['active'], current.active),
    );
  }

  static WindowChromeSnapshot _mergePointer(
    WindowChromeSnapshot current,
    Map<Object?, Object?> raw,
  ) {
    final hovered = windowTitleBarButtonFromName(raw['hovered'] as String?);
    final pressed = windowTitleBarButtonFromName(raw['pressed'] as String?);
    return current.copyWith(
      maximized: raw['maximized'] is bool
          ? raw['maximized']! as bool
          : current.maximized,
      active: raw['active'] is bool ? raw['active']! as bool : current.active,
      hovered: hovered,
      pressed: pressed,
      clearHovered: hovered == null,
      clearPressed: pressed == null,
    );
  }
}

/// 窗口 chrome 状态 provider。
final windowChromeProvider =
    NotifierProvider<WindowChromeController, WindowChromeSnapshot>(
      WindowChromeController.new,
    );

