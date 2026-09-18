/// 图书馆订阅词云同步 · 编排层（界面只跟它打交道）。
///
/// 责任边界：**它管状态与闸门，不管协议**（协议在 `libsp_sync_service.dart`），
/// 也**不弹任何对话框**（确认与展示在 presentation 层）。依赖全部注入 → 可单测。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:smarter_jxufe/features/library_sync/data/libsp_dirty_watch.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_prefs.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_service.dart';
import 'package:smarter_jxufe/features/library_sync/domain/libsp_remote.dart';

/// 控制器状态。
enum LibspSyncStatus { idle, running, ok, failed }

/// 同步控制器。
class LibspSyncController extends ChangeNotifier {
  LibspSyncController({
    required Future<LibspSyncService> Function() service,
    required LibspSyncPrefsStore prefs,
    required LibspSyncGate gate,
    required String Function() account,
    DateTime Function()? clock,
    this.debounce = libspMinUploadInterval,
    this.onRestored,
  }) : _service = service,
       _prefs = prefs,
       _gate = gate,
       _account = account,
       _clock = clock ?? DateTime.now;

  final Future<LibspSyncService> Function() _service;
  final LibspSyncPrefsStore _prefs;
  final LibspSyncGate _gate;
  final String Function() _account;
  final DateTime Function() _clock;

  /// 恢复成功后的回调（装配层用它叫醒「把数据读进自己 State」的页面）。
  ///
  /// 为什么需要：偏好 store 自己订阅了 box（`BoxReloadWatcher`），写盘即跟上；
  /// 而分数估计 / 综测这类页面是**把数据读进 State** 的，恢复写盘它们不会自己知道，
  /// 靠这个回调 bump 一个版本号让它们重读。
  final void Function()? onRestored;

  /// 变更后的防抖窗口（默认 60s，与 `LibspSyncGate.minInterval` 同源）。
  final Duration debounce;

  /// 由装配层注入的「本机有改动」监听器；恢复期间用它抑制自写事件。
  LibspDirtyWatcher? dirtyWatcher;

  Timer? _debounceTimer;

  LibspSyncStatus _status = LibspSyncStatus.idle;
  String? _message;
  bool _dirty = false;

  LibspSyncStatus get status => _status;

  /// 最近一次同步的结果文案（成功/失败都有）。
  String? get message => _message;

  bool get busy => _status == LibspSyncStatus.running;

  /// 本机有改动尚未上传（防抖窗口内）。
  bool get dirty => _dirty;

  /// 标记「本机有改动」（由 [LibspDirtyWatcher] 在 Hive box 变化时调用）。
  ///
  /// 行为：开一个 [debounce] 窗口，窗口内再改只会**顺延**（Q12 的防抖）；
  /// 窗口到点才真的上传，而且上传仍要过 `LibspSyncGate`（60s + 每日上限）。
  void markDirty() {
    final wasDirty = _dirty;
    _dirty = true;
    if (!wasDirty) notifyListeners();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(syncNow(auto: true));
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// 同步（[auto] = 自动触发：未开启 / 闸门未过则直接返回）。
  Future<void> syncNow({bool auto = false}) async {
    if (_status == LibspSyncStatus.running) return;
    if (auto) {
      if (!_prefs.enabled) return;
      if (!_gate.allowsAuto(_prefs.state, _clock())) return;
    }
    _status = LibspSyncStatus.running;
    _message = null;
    notifyListeners();

    try {
      final service = await _service();
      final outcome = await service.upload(
        account: _account(),
        nowMs: _clock().millisecondsSinceEpoch,
      );
      if (outcome.ok) {
        await _prefs.update(
          _gate.afterUpload(
            _prefs.state,
            _clock(),
            cloudGeneratedAt: _clock().millisecondsSinceEpoch,
          ),
        );
        _dirty = false;
        _status = LibspSyncStatus.ok;
        _message = outcome.up?.error == null
            ? outcome.summary
            : '${outcome.summary}（${outcome.up!.error}）';
      } else {
        await _prefs.markError(outcome.message);
        _status = LibspSyncStatus.failed;
        _message = outcome.message ?? '同步失败';
      }
    } catch (e) {
      await _prefs.markError('$e');
      _status = LibspSyncStatus.failed;
      _message = '同步失败：$e';
    }
    notifyListeners();
  }

  /// 只读预览云端最新一版（**不改本机任何东西**）。
  Future<LibspCloudSummary?> preview() async {
    try {
      final service = await _service();
      return await service.latestSummary();
    } catch (e) {
      _message = '读取云端失败：$e';
      notifyListeners();
      return null;
    }
  }

  /// 从云端恢复：**先留档本机现状**，留档失败就不动本机（Q6）。
  Future<bool> restoreFromCloud() async {
    if (_status == LibspSyncStatus.running) return false;
    _status = LibspSyncStatus.running;
    notifyListeners();
    try {
      final service = await _service();
      final snapshot = await service.latestSnapshot();
      if (snapshot == null) {
        _status = LibspSyncStatus.failed;
        _message = '云端没有完整的快照可恢复';
        notifyListeners();
        return false;
      }
      final archived = await service.backupBeforeRestore(
        account: _account(),
        nowMs: _clock().millisecondsSinceEpoch,
      );
      if (!archived) {
        _status = LibspSyncStatus.failed;
        _message = '恢复前留档失败，已中止（本机数据未被改动）';
        notifyListeners();
        return false;
      }
      // 恢复本身要写这些 box → 期间暂停「有改动」监听，否则自己写的事件
      // 会在 60s 后触发一次毫无意义的回传。
      Future<void> apply() => service.restore(
        snapshot,
        nowMs: _clock().millisecondsSinceEpoch,
      );
      final watcher = dirtyWatcher;
      if (watcher != null) {
        await watcher.pauseWhile(apply);
      } else {
        await apply();
      }
      _dirty = false;
      _status = LibspSyncStatus.ok;
      _message = '已从云端恢复';
      _notifyRestored();
      notifyListeners();
      return true;
    } catch (e) {
      _status = LibspSyncStatus.failed;
      _message = '恢复失败：$e';
      notifyListeners();
      return false;
    }
  }

  /// 叫醒页面重读；回调自己抛异常不影响「恢复成功」这个事实。
  void _notifyRestored() {
    final callback = onRestored;
    if (callback == null) return;
    try {
      callback();
    } catch (e) {
      debugPrint('[libsp] onRestored 回调异常：$e');
    }
  }

  /// 清除云端数据（按结构全删 + 对账）。
  Future<LibspClearResult?> clearCloud() async {
    if (_status == LibspSyncStatus.running) return null;
    _status = LibspSyncStatus.running;
    notifyListeners();
    try {
      final service = await _service();
      final result = await service.clearCloud();
      await _prefs.update(
        _prefs.state.copyWith(
          lastCloudGeneratedAt: null,
          lastUploadedAt: null,
          dailyCount: 0,
        ),
      );
      _dirty = false;
      _status = result.clean
          ? LibspSyncStatus.ok
          : LibspSyncStatus.failed;
      _message = result.clean
          ? '已清除云端的 ${result.deleted} 条同步数据'
          : '清除未完成：仍有 ${result.remaining} 条残留，请重试';
      notifyListeners();
      return result;
    } catch (e) {
      _status = LibspSyncStatus.failed;
      _message = '清除失败：$e';
      notifyListeners();
      return null;
    }
  }
}
