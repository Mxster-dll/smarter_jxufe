/// 图书馆订阅词云同步 · 「本机有改动」监听（Q12 防抖的起点）。
///
/// 为什么不逐个 store 埋点：偏好在 6 个 box、分数估计在账号级 box 里，各自由不同
/// feature 的 `ChangeNotifier` 写盘 —— 逐个埋点会**漏掉以后新增的写入路径**，
/// 还会让别的 feature 反向依赖同步模块。改为**监听 Hive box 本身**
/// （`Box.watch()`），于是任何写入路径（包括未来新增的）都自动被覆盖。
///
/// 恢复期间要 `pause()`：恢复本身就在写这些 box，不暂停会把自己写的当成
/// 「本机新改动」，60 秒后又上传一遍。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/library_sync/data/libsp_payload.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_store.dart';
import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';

/// 监听白名单偏好 box + 账号级分数估计 box 的变化。
class LibspDirtyWatcher {
  LibspDirtyWatcher({
    required this.account,
    required this.onDirty,
    this.boxNames = kLibspSyncedPrefBoxes,
  });

  /// 当前账号（分数估计用账号级 box）。
  final String account;

  /// 有改动时回调（控制器据此启动防抖计时）。
  final void Function() onDirty;

  /// 要监听的偏好 box（默认白名单）。
  final List<String> boxNames;

  final List<StreamSubscription<BoxEvent>> _subs = [];
  bool _paused = false;
  bool _started = false;

  /// 是否已开始监听（幂等）。
  bool get started => _started;

  /// 开始监听（失败只打日志：监听不到最坏就是少了防抖，同步仍会在回前台时跑）。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    for (final name in boxNames) {
      try {
        final box = await Hive.openBox<String>(name);
        _subs.add(box.watch().listen((_) => _emit()));
      } catch (e) {
        debugPrint('[libsp] 监听 $name 失败：$e');
      }
    }
    try {
      final box = await openAccountScopedBox(geBoxName, account);
      _subs.add(box.watch().listen((_) => _emit()));
    } catch (e) {
      debugPrint('[libsp] 监听分数估计失败：$e');
    }
  }

  /// 暂停（恢复本机数据期间用），[action] 结束后自动恢复。
  Future<T> pauseWhile<T>(Future<T> Function() action) async {
    _paused = true;
    try {
      return await action();
    } finally {
      _paused = false;
    }
  }

  void _emit() {
    if (_paused) return;
    onDirty();
  }

  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }
}
