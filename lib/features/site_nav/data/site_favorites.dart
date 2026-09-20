/// 网站导航 · 收藏（星标）持久化 —— Hive `siteNavPrefs` 单 key JSON 数组。
///
/// 存的是 [CampusSite.key]（= URL）列表：**用 URL 而不是名称**，站点改名后收藏不丢。
/// 收藏段在页面里**恒排最前**（`campusSiteSections` 里已定死），因此这里只负责
/// 「谁被收藏了」，不负责顺序 —— 段内顺序一律跟随目录顺序（改目录即改显示）。
///
/// ⚠ **不做账号隔离**（与「我的校区」同款全局偏好）：收藏的是学校官网，与学号无关。
///
/// 落盘是「尽力而为」：Hive 打开失败 / 数据损坏时仅本次会话生效，绝不抛异常、
/// 不影响界面。混入 [BoxReloadWatcher]：**外部写入**（云同步「从云端恢复」）
/// 也要反映到界面，否则恢复报成功、星标一动不动。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/box_reload_watcher.dart';

/// 存储 box 名（与 `myCampusPrefs`、`electricityBinding` 等分开）。
const siteNavPrefsBoxName = 'siteNavPrefs';

/// 单 key（值为收藏 URL 的 JSON 数组；无收藏 = 该 key 不存在）。
const siteNavFavoritesKey = 'favorites';

/// 收藏集合（内存缓存 + Hive 落盘）。
class SiteFavoritesStore extends ChangeNotifier with BoxReloadWatcher {
  final Set<String> _keys = <String>{};
  Box<String>? _box;
  Future<void>? _loading;

  /// 收藏的站点键（只读视图，别改它）。
  Set<String> get keys => Set<String>.unmodifiable(_keys);

  /// 收藏条数。
  int get length => _keys.length;

  /// 一条都没收藏。
  bool get isEmpty => _keys.isEmpty;

  /// 有收藏。
  bool get isNotEmpty => _keys.isNotEmpty;

  /// 是否已收藏 [key]（= URL）。
  bool contains(String key) => _keys.contains(key);

  /// 首次读取落盘值（幂等：并发调用共用同一个 Future）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final box = await Hive.openBox<String>(siteNavPrefsBoxName);
      _box = box;
      bindBoxReload(box, _readFromBox);
      _readFromBox(box);
    } catch (_) {
      // 存档不可用 / 损坏：保持空收藏，且此后不再尝试落盘。
    }
  }

  /// 从 box 重读（首载与外部写入共用）；集合没变就不通知。
  void _readFromBox(Box<String> box) {
    final parsed = siteFavoritesFromJson(box.get(siteNavFavoritesKey));
    if (setEquals(parsed, _keys)) return;
    _keys
      ..clear()
      ..addAll(parsed);
    notifyListeners();
  }

  /// 星标开关（页面那一颗星的唯一入口）。
  Future<void> toggle(String key) =>
      contains(key) ? remove(key) : add(key);

  /// 收藏一个站点；已收藏则什么都不做。
  Future<void> add(String key) async {
    await ensureLoaded();
    if (!_keys.add(key)) return;
    notifyListeners();
    await _persist();
  }

  /// 取消收藏；未收藏则什么都不做。
  Future<void> remove(String key) async {
    await ensureLoaded();
    if (!_keys.remove(key)) return;
    notifyListeners();
    await _persist();
  }

  /// 清空收藏（设置页 / 测试用）。
  Future<void> clear() async {
    await ensureLoaded();
    if (_keys.isEmpty) return;
    _keys.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final box = _box;
    if (box == null) return; // 存储不可用 → 仅本次会话生效
    try {
      if (_keys.isEmpty) {
        await box.delete(siteNavFavoritesKey);
      } else {
        await box.put(siteNavFavoritesKey, siteFavoritesToJson(_keys));
      }
    } catch (_) {
      // 落盘失败不影响本次会话内的显示。
    }
  }
}

/// 解析收藏 JSON；任何脏数据（非 JSON、非数组、非字符串项、空串）一律忽略。
Set<String> siteFavoritesFromJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <String>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <String>{};
    return {
      for (final item in decoded)
        if (item is String && item.trim().isNotEmpty) item,
    };
  } catch (_) {
    return <String>{};
  }
}

/// 序列化收藏（列表形态，便于人工查看/云同步 diff）。
String siteFavoritesToJson(Iterable<String> keys) =>
    jsonEncode(keys.toList(growable: false));

/// 收藏偏好（改动即时通知，页面直接 watch；实例由 provider 持有/释放）。
final siteFavoritesProvider = ChangeNotifierProvider<SiteFavoritesStore>((ref) {
  final store = SiteFavoritesStore();
  unawaited(store.ensureLoaded());
  return store;
});
