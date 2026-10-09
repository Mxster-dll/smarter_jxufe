import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/box_reload_watcher.dart';

/// 窗口三键的风格 —— 用户 2026-10-09 原话：「允许选择 win 风格三键与 mac 风格」。
///
/// **枚举住在这里**（设置自己的偏好），画法在 `lib/design/window_title_bar.dart`；
/// 与 `themeModeLabel` 同一套路（枚举与文案同处，画的地方只认枚举）。
enum WindowButtonsStyle {
  /// Windows 11 观感：右上角三个矩形按钮，悬停高亮、关闭键变红。
  windows,

  /// macOS 观感：三个圆形指示灯（红 / 黄 / 绿），默认排在**左边**（mac 惯例）。
  mac,
}

/// 窗口标题栏偏好 box 名（照 `theme_prefs.dart` 的口径：Hive `Box<String>` 单 key +
/// `ChangeNotifier` + `ChangeNotifierProvider`）。
const String windowBarPrefsBoxName = 'windowBarPrefs';

/// 单 key：三键风格（`WindowButtonsStyle.name`）。
const String _styleKey = 'buttonsStyle';

/// 单 key：是否交换 logo 与三键的位置。
const String _swapKey = 'swapSides';

/// 三键到底在不在左边 —— **唯一口径**（标题栏绘制与设置页文案共用）。
///
/// 用户 2026-10-09 二轮拍板：「选 mac 风格时三键默认自动靠左（mac 惯例），仍可用
/// 第一项设置换到右侧」→ mac 风格的默认值是「交换」，`swapSides` 依旧能把它翻回来。
/// Windows 风格默认不交换（logo 在左、三键在右 = Windows 惯例）。
bool windowButtonsOnLeft({
  required WindowButtonsStyle style,
  required bool swapSides,
}) => style == WindowButtonsStyle.mac ? !swapSides : swapSides;

/// 窗口标题栏（自绘三键）的两项设置 —— 用户 2026-10-09 原话：
/// 「设置里可以调关于此标题栏的两项：① 交换左侧应用 logo 与右侧三键的位置，变成
/// 左侧三键，右侧 logo；② 允许选择 win 风格三键与 mac 风格」。
///
/// 读不到 / 值认不出 / Hive 不可用 → 一律保持默认（`windows` + 不交换），绝不抛异常。
/// 与主题一样在 `main()` 里**预热**：标题栏是第一帧就画的东西，异步读盘会让它先按
/// 默认值画一次再跳一下。
class WindowBarPrefsStore extends ChangeNotifier with BoxReloadWatcher {
  WindowButtonsStyle _style = WindowButtonsStyle.windows;
  bool _swapSides = false;
  Box<String>? _box;
  Future<void>? _loading;

  /// 三键风格（默认 Windows —— 这是 Windows 桌面应用）。
  WindowButtonsStyle get style => _style;

  /// 是否交换：默认 false（Windows 惯例：logo 在左、三键在右）。
  bool get swapSides => _swapSides;

  /// 最终位置：三键在不在左边。
  bool get buttonsOnLeft =>
      windowButtonsOnLeft(style: _style, swapSides: _swapSides);

  /// 幂等加载；任何失败都静默（拿不到 box 时保持默认值）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final box = await Hive.openBox<String>(windowBarPrefsBoxName);
      _box = box;
      bindBoxReload(box, _readFromBox);
      _readFromBox(box);
    } catch (_) {}
  }

  /// 从 box 重读（首载与外部写入共用）；值没变就不通知。
  void _readFromBox(Box<String> box) {
    final style = windowButtonsStyleFromName(box.get(_styleKey));
    final swap = box.get(_swapKey) == 'true';
    if ((style == null || style == _style) && swap == _swapSides) return;
    if (style != null) _style = style;
    _swapSides = swap;
    notifyListeners();
  }

  /// 改三键风格。
  Future<void> saveStyle(WindowButtonsStyle next) async {
    await ensureLoaded();
    if (next == _style) return;
    _style = next;
    notifyListeners();
    await _put(_styleKey, next.name);
  }

  /// 改「交换 logo / 三键位置」。
  Future<void> saveSwapSides(bool next) async {
    await ensureLoaded();
    if (next == _swapSides) return;
    _swapSides = next;
    notifyListeners();
    await _put(_swapKey, next ? 'true' : 'false');
  }

  Future<void> _put(String key, String value) async {
    final box = _box;
    if (box == null) return;
    try {
      await box.put(key, value);
    } catch (_) {}
  }
}

/// `WindowButtonsStyle.name` → 枚举；空 / 认不出 → `null`（= 保持默认）。
WindowButtonsStyle? windowButtonsStyleFromName(String? name) {
  if (name == null) return null;
  for (final value in WindowButtonsStyle.values) {
    if (value.name == name) return value;
  }
  return null;
}

/// 设置页里三键风格的标题（唯一出处）。
String windowButtonsStyleLabel(WindowButtonsStyle style) => switch (style) {
  WindowButtonsStyle.windows => 'Windows 风格',
  WindowButtonsStyle.mac => 'macOS 风格',
};

/// 设置页里三键风格的说明（唯一出处）。
String windowButtonsStyleDescription(WindowButtonsStyle style) =>
    switch (style) {
      WindowButtonsStyle.windows => '右上角三个矩形按钮，悬停高亮、关闭键变红',
      WindowButtonsStyle.mac => '三个圆形指示灯（红 / 黄 / 绿），默认排在左边',
    };

/// 窗口标题栏偏好 provider；`main()` 已预热，这里再调是幂等的。
final windowBarPrefsProvider = ChangeNotifierProvider<WindowBarPrefsStore>((
  ref,
) {
  final store = WindowBarPrefsStore();
  unawaited(store.ensureLoaded());
  return store;
});
