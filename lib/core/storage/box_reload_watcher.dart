/// 让「读一次就存内存」的偏好 store 也能感知**外部写入**（云同步恢复 / 以后的导入）。
///
/// 背景（2026-09-17 实测的 bug）：本仓的偏好 store 都是 `ChangeNotifier` + Hive
/// `Box<String>`，值读一次就留在内存（`ensureLoaded()` 里 `_loading ??= _load()`，
/// 幂等缓存）。云同步「从云端恢复」走的是 `HiveLibspLocalStore.writePrefs` →
/// `box.put`，**只改了盘**：没有任何人通知内存，于是恢复报成功、界面一动不动
/// （用户原话「目前从云端同步似乎设置不会变」；`test/libsp_restore_live_test.dart`
/// 就是这条链的守卫，修前 6 例全红）。
///
/// 订阅 `Box.watch()` 之后，任何写入路径（自己 `save`、云同步恢复、以后新增的写入）
/// 都会让 store 重读一次；读到的值与内存相同就不通知，因此**不会形成通知回环**。
///
/// 用法：在 store 打开 box 之后 `bindBoxReload(box, _readFromBox)`，并把原来的首载
/// 读取逻辑抽成接受 `Box<String>` 的私有方法（首载与外部写入共用同一段）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 见文件头注释。
mixin BoxReloadWatcher on ChangeNotifier {
  final List<StreamSubscription<BoxEvent>> _boxSubscriptions =
      <StreamSubscription<BoxEvent>>[];
  bool _released = false;

  /// 订阅 [box] 的写入事件：事件到达后调 [read]（**由 [read] 自己判等**，
  /// 值没变就别通知；自己 `save()` 的那次写入也会走一遍，判等后静默）。
  void bindBoxReload(Box<String> box, void Function(Box<String> box) read) {
    _boxSubscriptions.add(
      box.watch().listen((_) {
        // Hive 的事件是异步投递的，`dispose()` 之后仍可能有一拍在路上；
        // 此时 `notifyListeners()` 会抛「used after being disposed」→ 丢弃。
        if (_released) return;
        read(box);
      }),
    );
  }

  @override
  void dispose() {
    _released = true;
    for (final sub in _boxSubscriptions) {
      unawaited(sub.cancel());
    }
    _boxSubscriptions.clear();
    super.dispose();
  }
}
