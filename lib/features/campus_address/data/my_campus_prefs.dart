/// 「我的校区」偏好的持久化（Hive `myCampusPrefs` 单 key）。
///
/// 用 [ChangeNotifier] 而非 AsyncNotifier：设置页改动要立刻反映到学校地址 /
/// 校区地图 / 电费绑定三处（无需重新拉数据），与 `calendar_prefs.dart` 同款。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';

/// 存储 box 名（与 `electricityBinding`、`wxPlatform` 等分开）。
const myCampusPrefsBoxName = 'myCampusPrefs';

/// 单 key（值为 [MyCampus.name]；「未设置」= 该 key 不存在）。
const _prefsKey = 'campus';

/// 「我的校区」存储（内存缓存 + Hive 落盘）。
///
/// 落盘是「尽力而为」：Hive 打开失败时仅本次会话生效，不抛异常、不影响界面。
class MyCampusStore extends ChangeNotifier {
  MyCampus? _campus;
  Box<String>? _box;
  Future<void>? _loading;

  /// 当前校区；`null` = 未设置。
  MyCampus? get campus => _campus;

  /// 首次读取落盘值（幂等：并发调用共用同一个 Future）。
  ///
  /// 失败时保持「未设置」，且此后不再尝试落盘。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final box = await Hive.openBox<String>(myCampusPrefsBoxName);
      _box = box;
      final parsed = MyCampus.fromName(box.get(_prefsKey));
      if (parsed == null || parsed == _campus) return;
      _campus = parsed;
      notifyListeners();
    } catch (_) {
      // 存档不可用 / 损坏：保持「未设置」。
    }
  }

  /// 写入新校区（`null` = 清除设置）。绝不抛异常。
  Future<void> save(MyCampus? next) async {
    await ensureLoaded();
    if (next == _campus) return;
    _campus = next;
    notifyListeners();
    final box = _box;
    if (box == null) return; // 存储不可用 → 仅本次会话生效
    try {
      if (next == null) {
        await box.delete(_prefsKey);
      } else {
        await box.put(_prefsKey, next.name);
      }
    } catch (_) {
      // 落盘失败不影响本次会话内的显示。
    }
  }
}

/// 「我的校区」偏好（改动即时通知，页面直接 watch）。
///
/// 实例由本 provider 持有/释放（`ChangeNotifierProvider` 会 dispose 它，
/// 故 [MyCampusStore] 不做全局单例）。
final myCampusStoreProvider = ChangeNotifierProvider<MyCampusStore>((ref) {
  final store = MyCampusStore();
  unawaited(store.ensureLoaded());
  return store;
});
