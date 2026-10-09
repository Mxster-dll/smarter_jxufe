import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/network/trace_text.dart' show clipForTrace200;
import 'package:smarter_jxufe/core/window/window_chrome.dart';

/// 记住上次启动时的窗口大小（用户 2026-10-10：「我希望应用记住上次启动时的窗口大小」）。
///
/// 分成两半，各自只有一件事：
/// - **恢复** = [restore]：启动后读一次落盘的尺寸，经通道 `setClientSize` 交给原生
///   （原生按窗口 DPI 换算、并补回那圈不可见的原生边框，见 `window_chrome.cpp`）；
/// - **记录** = [WindowSizeKeeper]（`WidgetsBindingObserver`）：窗口尺寸一变就落盘一次，
///   带 700ms 防抖 —— 拖拽缩放期间 `didChangeMetrics` 会连发几十次，不防抖就是几十次写盘。
///
/// ⚠ 存的是**客户区逻辑像素**（`physicalSize / devicePixelRatio`）：与原生那侧的口径一致，
/// 换 DPI / 换显示器时窗口按逻辑尺寸还原（用户看到的「大小」不变）。
///
/// ⚠ 与 `windowBarPrefs` 分开一个 box：那个是「标题栏两项设置」，这个是窗口几何，
/// 混在一起会让「清设置」连带把窗口大小也清掉。
const String windowSizePrefsBoxName = 'windowSizePrefs';

/// 落盘的 key：`"宽,高"`（逻辑像素）。
const String windowSizeKey = 'clientSize';

/// 防抖窗口：拖拽缩放停下来 700ms 之后才写盘。
const Duration windowSizeSaveDebounce = Duration(milliseconds: 700);

/// 小于这个尺寸的一律不认（非法值 / 首帧的 0 尺寸），避免把窗口还原成一个点。
const Size windowSizeMinimum = Size(480, 360);

class WindowSizeKeeper extends StatefulWidget {
  const WindowSizeKeeper({super.key, required this.child});

  final Widget child;

  /// 启动后调用一次：把上次的窗口大小交给原生。
  ///
  /// 静默降级：非 Windows / 单测 / 旧 exe（没有这个原生方法）时一律当作没存过。
  static Future<void> restore() async {
    try {
      final box = await Hive.openBox<String>(windowSizePrefsBoxName);
      final raw = box.get(windowSizeKey);
      if (raw == null) return;
      final size = parseWindowSize(raw);
      if (size == null) return;
      await kWindowChromeChannel.invokeMethod<Object?>(
        'setClientSize',
        <String, Object?>{'width': size.width, 'height': size.height},
      );
    } catch (_) {
      // 老 exe（MissingPluginException）/ 没有 box / 数值坏掉 —— 都不该拦启动。
    }
  }

  /// 解析 `"宽,高"`；不合法返回 null。
  static Size? parseWindowSize(String raw) {
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final width = double.tryParse(parts[0].trim());
    final height = double.tryParse(parts[1].trim());
    if (width == null || height == null) return null;
    if (width < windowSizeMinimum.width || height < windowSizeMinimum.height) {
      return null;
    }
    return Size(width, height);
  }

  @override
  State<WindowSizeKeeper> createState() => _WindowSizeKeeperState();
}

class _WindowSizeKeeperState extends State<WindowSizeKeeper>
    with WidgetsBindingObserver {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 窗口尺寸变了（拖边框 / 最大化 / 换显示器）→ 防抖后落盘。
  @override
  void didChangeMetrics() {
    _debounce?.cancel();
    _debounce = Timer(windowSizeSaveDebounce, _save);
  }

  Future<void> _save() async {
    try {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final ratio = view.devicePixelRatio;
      if (ratio <= 0) return;
      final size = view.physicalSize / ratio;
      final keeper = WindowSizeKeeper.parseWindowSize(
        '${size.width.round()},${size.height.round()}',
      );
      if (keeper == null) return;
      final box = await Hive.openBox<String>(windowSizePrefsBoxName);
      await box.put(
        windowSizeKey,
        '${keeper.width.round()},${keeper.height.round()}',
      );
    } catch (error) {
      // 写盘失败（无 box / 只读环境）不该影响使用；留一行被截断的痕迹便于排查。
      debugPrint('[window] 记录窗口大小失败：${clipForTrace200('$error')}');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
