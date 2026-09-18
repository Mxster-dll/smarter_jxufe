import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/box_reload_watcher.dart';

/// 外观偏好 box 名（照 `lib/features/campus_address/data/my_campus_prefs.dart` 的口径：
/// Hive `Box<String>` 单 key + `ChangeNotifier` + `ChangeNotifierProvider`）。
const String themePrefsBoxName = 'themePrefs';

/// 单 key：存 `ThemeMode.name`（`system` / `light` / `dark`）。
const String _prefsKey = 'themeMode';

/// 外观模式（跟随系统 / 浅色 / 深色）存储。
///
/// - **默认跟随系统**；读不到 / 存的值认不出 / Hive 不可用 → 保持默认，绝不抛异常。
/// - `ensureLoaded()` 幂等（`_loading ??= _load()`），可以在 `main()` 里预热一次、
///   之后由 provider 再调一次也不会重复读盘。
/// - 用 `ChangeNotifier` 而不是 `FutureProvider`：`MaterialApp` 直接 `watch` 它，
///   切换后立即重建整棵树，中间没有「先闪一次旧值」的空窗（§3 偏好存储口径）。
/// - 混入 [BoxReloadWatcher]：**外部写入**（云同步「从云端恢复」）也要反映到界面 ——
///   否则恢复只改了盘、内存不动（用户 2026-09-17 报的「设置不会变」）。
class ThemeModeStore extends ChangeNotifier with BoxReloadWatcher {
  ThemeMode _mode = ThemeMode.system;
  Box<String>? _box;
  Future<void>? _loading;

  /// 当前外观模式。
  ThemeMode get mode => _mode;

  /// 幂等加载；任何失败都静默（拿不到 box 时保持「跟随系统」）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final box = await Hive.openBox<String>(themePrefsBoxName);
      _box = box;
      bindBoxReload(box, _readFromBox);
      _readFromBox(box);
    } catch (_) {}
  }

  /// 从 box 重读（首载与外部写入共用）；值没变就不通知。
  void _readFromBox(Box<String> box) {
    final parsed = themeModeFromName(box.get(_prefsKey));
    if (parsed == null || parsed == _mode) return;
    _mode = parsed;
    notifyListeners();
  }

  /// 写入并立即通知。落盘尽力而为（失败不影响本次切换）。
  Future<void> save(ThemeMode next) async {
    await ensureLoaded();
    if (next == _mode) return;
    _mode = next;
    notifyListeners();
    final box = _box;
    if (box == null) return;
    try {
      await box.put(_prefsKey, next.name);
    } catch (_) {}
  }
}

/// `ThemeMode.name` → 枚举；空 / 认不出 → `null`（= 保持默认「跟随系统」）。
ThemeMode? themeModeFromName(String? name) {
  if (name == null) return null;
  for (final mode in ThemeMode.values) {
    if (mode.name == name) return mode;
  }
  return null;
}

/// 设置页「外观」节三档的标题（唯一出处）。
String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => '跟随系统',
  ThemeMode.light => '浅色',
  ThemeMode.dark => '深色',
};

/// 三档的说明文案（唯一出处）。
String themeModeDescription(ThemeMode mode) => switch (mode) {
  ThemeMode.system => '随系统的深色 / 浅色设置自动切换',
  ThemeMode.light => '始终使用浅色外观',
  ThemeMode.dark => '始终使用深色外观',
};

/// 外观模式 provider。
///
/// `main()` 里已经预热过一次（`ensureLoaded()`），这里再调是幂等的 ——
/// 于是首帧就能拿到用户选定的模式，不会先浅后深地闪一下。
final themeModeStoreProvider = ChangeNotifierProvider<ThemeModeStore>((ref) {
  final store = ThemeModeStore();
  unawaited(store.ensureLoaded());
  return store;
});
