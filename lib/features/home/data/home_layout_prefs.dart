/// 主页布局偏好的持久化（Hive `homePrefs` 单 key）。
///
/// 与 `my_campus_prefs.dart` / `calendar_prefs.dart` 同款：`ChangeNotifier`
/// 而非 `AsyncNotifier` —— 设置页改完要**立刻**反映到主页（切换布局不该等
/// 一次异步读盘，否则会先闪一帧旧布局）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/box_reload_watcher.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';

/// 存储 box 名（与 `myCampusPrefs`、`schoolCalendarPrefs` 等分开）。
const homePrefsBoxName = 'homePrefs';

/// 单 key（值为 [HomeLayout.name]；缺省 = 宫格）。
const _layoutKey = 'homeLayout';

/// 主页布局偏好存储（内存缓存 + Hive 落盘）。
///
/// 落盘「尽力而为」：Hive 打开失败时仅本次会话生效，不抛异常、不影响界面。
/// 混入 [BoxReloadWatcher]：**外部写入**（云同步「从云端恢复」）也要反映到界面。
class HomeLayoutStore extends ChangeNotifier with BoxReloadWatcher {
  HomeLayout _layout = HomeLayout.grid;
  Box<String>? _box;
  Future<void>? _loading;

  /// 当前布局（默认宫格）。
  HomeLayout get layout => _layout;

  /// 首次读取落盘值（幂等：并发调用共用同一个 Future）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final box = await Hive.openBox<String>(homePrefsBoxName);
      _box = box;
      bindBoxReload(box, _readFromBox);
      _readFromBox(box);
    } catch (_) {
      // 存档不可用 / 损坏：保持宫格。
    }
  }

  /// 从 box 重读（首载与外部写入共用）；值没变就不通知。
  void _readFromBox(Box<String> box) {
    final parsed = HomeLayout.fromName(box.get(_layoutKey));
    if (parsed == _layout) return;
    _layout = parsed;
    notifyListeners();
  }

  /// 写入新布局。绝不抛异常。
  Future<void> save(HomeLayout next) async {
    await ensureLoaded();
    if (next == _layout) return;
    _layout = next;
    notifyListeners();
    final box = _box;
    if (box == null) return; // 存储不可用 → 仅本次会话生效
    try {
      await box.put(_layoutKey, next.name);
    } catch (_) {
      // 落盘失败不影响本次会话内的显示。
    }
  }
}

/// 主页布局偏好（改动即时通知）。
///
/// 实例由本 provider 持有/释放（`ChangeNotifierProvider` 会 dispose 它，
/// 故 [HomeLayoutStore] 不做全局单例）。
final homeLayoutStoreProvider = ChangeNotifierProvider<HomeLayoutStore>((ref) {
  final store = HomeLayoutStore();
  unawaited(store.ensureLoaded());
  return store;
});
