/// 首页宫格**聚合布局**的持久化（Hive `homeGridPrefs` 单 key JSON）。
///
/// 与 `home_layout_prefs.dart` / `my_campus_prefs.dart` 同款：`ChangeNotifier`
/// 而非 `FutureProvider` —— 拖动合并松手后主页要**立刻**变成新布局，中间不能有
/// 一次异步读盘的空窗（否则会先闪一帧旧布局）。
///
/// 单独一个 box（而不是塞进 `homePrefs`）：`homePrefs` 在云同步的偏好清单里
/// （`libsp_payload.dart`），整表同步的是「布局形态」这个枚举；聚合布局是一份
/// 会随入口增删变化的**大 JSON**，混进同一个 box 会让云同步的语义变糊。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/box_reload_watcher.dart';
import 'package:smarter_jxufe/features/home/domain/home_grid_layout.dart';

/// 存储 box 名（与 `homePrefs` 分开）。
const homeGridPrefsBoxName = 'homeGridPrefs';

/// 单 key（值为 [HomeGridLayout] 的 JSON；缺省 = 没自定义过）。
const homeGridLayoutKey = 'gridLayout';

/// 宫格聚合布局存储（内存缓存 + Hive 落盘）。
///
/// 落盘「尽力而为」：Hive 打开失败时仅本次会话生效，不抛异常、不影响界面。
/// 混入 [BoxReloadWatcher]：外部写入（云同步 / 以后的导入）也要反映到界面。
class HomeGridStore extends ChangeNotifier with BoxReloadWatcher {
  /// [persist] = false 时**完全不碰 Hive**（测试用：`flutter_test` 的假异步区推不动
  /// 真 I/O，一旦真的开 box，widget 测试会静默挂死到超时 —— 与 §2.1 同源）。
  HomeGridStore({this.persist = true});

  /// 是否落盘。
  final bool persist;

  HomeGridLayout? _layout;
  Box<String>? _box;
  Future<void>? _loading;

  /// 已保存的聚合布局；null = 用户没自定义过（按目录顺序流式铺）。
  HomeGridLayout? get layout => _layout;

  /// 是否已有自定义聚合布局。
  bool get hasCustomLayout => _layout != null;

  /// 首次读取落盘值（幂等：并发调用共用同一个 Future）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    if (!persist) return;
    try {
      final box = await Hive.openBox<String>(homeGridPrefsBoxName);
      _box = box;
      bindBoxReload(box, _readFromBox);
      _readFromBox(box);
    } catch (_) {
      // 存档不可用 / 损坏：保持默认布局。
    }
  }

  /// 从 box 重读（首载与外部写入共用）；值没变就不通知。
  void _readFromBox(Box<String> box) {
    final parsed = homeGridLayoutFromJson(box.get(homeGridLayoutKey));
    if (parsed == _layout) return;
    _layout = parsed;
    notifyListeners();
  }

  /// 写入新布局（拖动 / 合并松手时调用）。绝不抛异常。
  Future<void> save(HomeGridLayout next) async {
    await ensureLoaded();
    if (next == _layout) return;
    _layout = next;
    notifyListeners();
    final box = _box;
    if (box == null) return; // 存储不可用 → 仅本次会话生效
    try {
      await box.put(homeGridLayoutKey, homeGridLayoutJson(next));
    } catch (_) {
      // 落盘失败不影响本次会话内的显示。
    }
  }

  /// 恢复默认布局（删掉存档 → 回到「按目录顺序流式铺」）。
  Future<void> reset() async {
    await ensureLoaded();
    _layout = null;
    notifyListeners();
    final box = _box;
    if (box == null) return;
    try {
      await box.delete(homeGridLayoutKey);
    } catch (_) {
      // 同上：删不掉也只是下次启动还留着旧布局。
    }
  }
}
/// 宫格聚合布局（改动即时通知）。
///
/// 实例由本 provider 持有/释放（`ChangeNotifierProvider` 会 dispose 它，
/// 故 [HomeGridStore] 不做全局单例）。
final homeGridStoreProvider = ChangeNotifierProvider<HomeGridStore>((ref) {
  final store = HomeGridStore();
  unawaited(store.ensureLoaded());
  return store;
});
