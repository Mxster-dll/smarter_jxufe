/// 「我的校区」偏好的持久化（Hive `myCampusPrefs` 单 key）。
///
/// 用 [ChangeNotifier] 而非 AsyncNotifier：设置页改动要立刻反映到学校地址 /
/// 校区地图 / 电费绑定三处（无需重新拉数据），与 `calendar_prefs.dart` 同款。
///
/// 值的**来源**（[MyCampusSource]）也一并记下：用户 2026-09-20 要求「校区设置改成
/// 直接用数据中心的数据，获取失败再手动设置」，裁定口径是**手动优先、数据中心只补空**
/// —— 设置页据此在卡片上标注「数据中心」/「手动」，接线在 `my_campus_center.dart`。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/box_reload_watcher.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_center.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';

/// 存储 box 名（与 `electricityBinding`、`wxPlatform` 等分开）。
const myCampusPrefsBoxName = 'myCampusPrefs';

/// 单 key（值为 [MyCampus.name]；「未设置」= 该 key 不存在）。
const _prefsKey = 'campus';

/// 来源 key（值为 [MyCampusSource.name]；老存档没有这个键 → 视为手动）。
const _sourceKey = 'campusSource';

/// 「我的校区」这个值是谁给的。
enum MyCampusSource {
  /// 用户在设置页手选的（含「不设置」之前的最后一次选择）。
  manual,

  /// 数据中心「基本信息」的「所属校区」（自动补空写入）。
  center;

  static MyCampusSource? fromName(String? name) {
    for (final s in MyCampusSource.values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// 「我的校区」存储（内存缓存 + Hive 落盘）。
///
/// 落盘是「尽力而为」：Hive 打开失败时仅本次会话生效，不抛异常、不影响界面。
/// 混入 [BoxReloadWatcher]：**外部写入**（云同步「从云端恢复」）也要反映到界面。
class MyCampusStore extends ChangeNotifier with BoxReloadWatcher {
  MyCampus? _campus;
  MyCampusSource? _source;
  Box<String>? _box;
  Future<void>? _loading;

  /// 当前校区；`null` = 未设置。
  MyCampus? get campus => _campus;

  /// 当前值的来源；`null` = 未设置（或老存档没记来源）。
  MyCampusSource? get source => _source;

  /// 首次读取落盘值（幂等：并发调用共用同一个 Future）。
  ///
  /// 失败时保持「未设置」，且此后不再尝试落盘。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final box = await Hive.openBox<String>(myCampusPrefsBoxName);
      _box = box;
      bindBoxReload(box, _readFromBox);
      _readFromBox(box);
    } catch (_) {
      // 存档不可用 / 损坏：保持「未设置」。
    }
  }

  /// 从 box 重读（首载与外部写入共用）；值没变就不通知。
  void _readFromBox(Box<String> box) {
    final parsed = MyCampus.fromName(box.get(_prefsKey));
    if (parsed == null) return; // 未设置 / 值不认识：保持现状
    final source = MyCampusSource.fromName(box.get(_sourceKey));
    // 来源只是**展示用**的元信息：老存档没有这个键 → null。
    // ⚠ `box.watch()` 的事件是异步投递的，读到「值到了、来源还没落盘」的半拉状态时
    // 不许把已知来源抹掉（否则设置页的「数据中心」角标会闪成「手动设置」）。
    if (parsed == _campus && (source == _source || source == null)) return;
    _campus = parsed;
    _source = source;
    notifyListeners();
  }

  /// 写入新校区（`null` = 清除设置）。绝不抛异常。
  ///
  /// [MyCampusSource.manual]：用户在设置页选的。
  Future<void> save(MyCampus? next) => _write(next, MyCampusSource.manual);

  /// **只在从未设置过时**写入（数据中心补空，见 `my_campus_center.dart`）。
  ///
  /// 先 `await ensureLoaded()` 再判空 —— 这是「拿到值才落闸」：存档还没读完时
  /// [campus] 也是 null，直接写会把用户手选过的校区冲掉（照
  /// `classroom_free_screen.dart` 里默认教学楼那条口径）。
  /// [next] 为 null（数据中心没有这一列 / 取不到）时什么都不做。
  Future<void> fillIfEmpty(MyCampus? next) async {
    if (next == null) return;
    await ensureLoaded();
    if (_campus != null) return;
    await _write(next, MyCampusSource.center);
  }

  Future<void> _write(MyCampus? next, MyCampusSource source) async {
    await ensureLoaded();
    if (next == _campus && (next == null || source == _source)) return;
    _campus = next;
    _source = next == null ? null : source;
    notifyListeners();
    final box = _box;
    if (box == null) return; // 存储不可用 → 仅本次会话生效
    try {
      // 值与来源**一次写完**（`putAll` 一帧 → 一个 watch 事件）：分两次 put 会在
      // 中间投递一个「值到了、来源还没到」的事件，界面上的来源角标会闪一下。
      if (next == null) {
        await box.deleteAll(const [_prefsKey, _sourceKey]);
      } else {
        await box.putAll({_prefsKey: next.name, _sourceKey: source.name});
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
///
/// 这里挂上「数据中心补空」的接线：任何一处读本 provider 的页面（设置页 /
/// 电费绑定 / 学校地址 / 校区地图 / 找空闲教室）都会顺带把数据中心那一份取来，
/// 只补空、不覆盖手选值。取数走的是「我的」页同一份 `dzjBasicInfoProvider`
/// （非 autoDispose，一个会话只请求一次；会话有缓存时不发网络）。
final myCampusStoreProvider = ChangeNotifierProvider<MyCampusStore>((ref) {
  final store = MyCampusStore();
  unawaited(store.ensureLoaded());
  bindMyCampusCenterFill(ref, store.fillIfEmpty);
  return store;
});
