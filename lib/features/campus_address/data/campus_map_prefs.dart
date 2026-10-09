/// 校区地图风格偏好的持久化（Hive `campusMapPrefs` 单 key）。
///
/// 照 `my_campus_prefs.dart` 的范式：`ChangeNotifier` + `Box<String>` 单 key，
/// 改动即时反映到界面（不用 `FutureProvider`，那会先闪一次旧值）。
///
/// 语义三条：
/// - **值 = 用户手选过的风格**；键不存在 = 没手选过 → **跟随 App 主题**
///   （判定在 `presentation/campus_map_style.dart` 的 `resolveCampusMapStyle`）；
/// - 用户再点一次当前风格**不清空**：切换控件只有两档，没有「跟随」这一档。
///   要恢复跟随主题，走设置页的「校区地图」节（那里给三态）；
/// - 读失败 / 存档损坏一律视作「没手选过」，绝不抛异常。
///
/// ⚠ **本仓的偏好 box 都是懒打开的**（`HiveInitializer` 只 `initFlutter` +
/// 注册 adapter，不预开 box），所以「box 还没开」是常态而不是异常路径。因此：
/// - **读**：box 已开就**同步**读（首帧即正确，不闪）；没开才异步开。
/// - **写**：**先改内存 + `notifyListeners()`（同步生效，点一下就变）**，
///   落盘异步尽力而为 —— 界面绝不等待磁盘。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/box_reload_watcher.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_style.dart';

/// 存储 box 名（与 `myCampusPrefs`、`calendarPrefs` 等分开）。
const campusMapPrefsBoxName = 'campusMapPrefs';

/// 单 key（值为 [CampusMapStyleKind.name]；「跟随主题」= 该 key 不存在）。
const _styleKey = 'style';

/// 校区地图风格存储（内存缓存 + Hive 落盘）。
///
/// 落盘「尽力而为」：Hive 打开失败时仅本次会话生效。混入 [BoxReloadWatcher]：
/// **外部写入**（云同步「从云端恢复」若将来带上这个偏好）也要反映到界面。
///
/// ⚠ 这一项**故意不进云同步清单**（`libsp_payload.dart`）：它是「这台设备看地图
/// 想用哪种配色」的显示偏好，跟着账号跨设备同步没有意义，反而会在换设备后
/// 把对端的深色设置顶掉。
class CampusMapStore extends ChangeNotifier with BoxReloadWatcher {
  CampusMapStyleKind? _style;
  Box<String>? _box;
  Future<void>? _loading;

  /// 用户手选过的风格；`null` = 跟随 App 主题。
  CampusMapStyleKind? get style => _style;

  /// 是否跟随主题（没手选过）。
  bool get followsTheme => _style == null;

  /// 首次读取落盘值（幂等：并发调用共用同一个 Future）。
  ///
  /// box 已经开着时是**同步完成**的（调用方仍可 `await`，只是立刻返回）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      if (Hive.isBoxOpen(campusMapPrefsBoxName)) {
        _attach(Hive.box<String>(campusMapPrefsBoxName));
        return;
      }
      _attach(await Hive.openBox<String>(campusMapPrefsBoxName));
    } catch (_) {
      // 存档不可用 / 损坏：保持「跟随主题」。
    }
  }

  void _attach(Box<String> box) {
    _box = box;
    bindBoxReload(box, _readFromBox);
    _readFromBox(box);
  }

  /// 从 box 重读（首载与外部写入共用）；值没变就不通知。
  void _readFromBox(Box<String> box) {
    final parsed = CampusMapStyleKind.fromName(box.get(_styleKey));
    if (parsed == _style) return;
    _style = parsed;
    notifyListeners();
  }

  /// 写入风格（`null` = 恢复跟随主题）。绝不抛异常。
  ///
  /// **内存先改 + 通知同步发**，落盘在后台补 —— 于是「点了按钮立刻变」，
  /// 不受磁盘 IO 快慢影响（有测试钉着这条）。
  Future<void> save(CampusMapStyleKind? next) async {
    if (next != _style) {
      _style = next;
      notifyListeners();
    }
    // 落盘：box 还没开就顺带开一次（`ensureLoaded` 幂等）。
    await ensureLoaded();
    final box = _box;
    if (box == null) return; // 存储不可用 → 仅本次会话生效
    try {
      if (next == null) {
        await box.delete(_styleKey);
      } else {
        await box.put(_styleKey, next.name);
      }
    } catch (_) {
      // 落盘失败不影响本次会话内的显示。
    }
  }

  /// 在两种风格之间来回切（页内那个按钮用）。返回切换后的风格。
  ///
  /// ⚠ **要 `await save()`**：`save()` 的第一件事就是改内存 + 通知，所以界面
  /// 仍然是「点一下立刻变」；但**返回值必须等状态真的提交**，否则连续两次
  /// `toggle` 会读到同一个旧值 → 第二次调用算出同一个结果
  /// （实测：`toggle(dark)` 两次都返回 `dark`，传引用 `current` 的写法也救不了）。
  Future<CampusMapStyleKind> toggle(CampusMapStyleKind current) async {
    final next = current.other;
    await save(next);
    return next;
  }
}

/// 校区地图风格偏好（改动即时通知，页面直接 watch）。
///
/// 实例由本 provider 持有/释放（`ChangeNotifierProvider` 会 dispose 它，
/// 故 [CampusMapStore] 不做全局单例）。
final campusMapStoreProvider = ChangeNotifierProvider<CampusMapStore>((ref) {
  final store = CampusMapStore();
  unawaited(store.ensureLoaded());
  return store;
});
