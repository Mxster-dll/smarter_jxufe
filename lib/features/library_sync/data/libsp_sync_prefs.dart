/// 图书馆订阅词云同步 · 开关与节流闸门（Hive 单 key JSON + ChangeNotifier）。
///
/// 口径（Q12）：
/// - **opt-in**：默认关闭；开启时界面必须逐项列出会同步的内容（含宿舍房间号）。
/// - **防抖 60s**：改动后只在最后一次变更满 60 秒才自动上传（沿用本仓
///   §3「数据更新最小间隔 1 分钟」的既有口径，不引入新概念）。
/// - **每日上限**：自动上传按天计数，超过就只允许手动同步 —— 别把图书馆服务器
///   当草稿纸（一次同步 ≈ 14 片写入 + 逐片读回 + 对账，约 30 次请求）。
/// - **窗口起点 = 上一次真的写成功**（不是「发出请求」）：网络抖动不该封锁窗口，
///   否则一次失败会让人一分钟内连重试都做不了（与畅想之星闸门同一条教训）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 同步偏好的 box 名。
const String libspSyncPrefsBoxName = 'libspSyncPrefs';

/// 单 key（整份状态一个 JSON）。
const String _prefsKey = 'state';

/// 自动上传的最小间隔（防抖窗口）。
const Duration libspMinUploadInterval = Duration(seconds: 60);

/// 自动上传的每日次数上限（手动同步不受限）。
const int libspDailyUploadLimit = 20;

/// 持久化的同步状态。
class LibspSyncState {
  const LibspSyncState({
    this.enabled = false,
    this.lastUploadedAt,
    this.lastCloudGeneratedAt,
    this.lastError,
    this.dailyCount = 0,
    this.dailyCountDay,
  });

  /// 用户是否开启同步（opt-in）。
  final bool enabled;

  /// 上次**成功**写入云端的时刻（epoch ms）。
  final int? lastUploadedAt;

  /// 云端最新一版的生成时刻（对账用）。
  final int? lastCloudGeneratedAt;

  /// 上次失败原因（成功即清空）。
  final String? lastError;

  /// 当天自动上传次数。
  final int dailyCount;

  /// 计数归属日（`yyyyMMdd`）。
  final int? dailyCountDay;

  LibspSyncState copyWith({
    bool? enabled,
    int? lastUploadedAt,
    int? lastCloudGeneratedAt,
    Object? lastError = _sentinel,
    int? dailyCount,
    int? dailyCountDay,
  }) => LibspSyncState(
    enabled: enabled ?? this.enabled,
    lastUploadedAt: lastUploadedAt ?? this.lastUploadedAt,
    lastCloudGeneratedAt: lastCloudGeneratedAt ?? this.lastCloudGeneratedAt,
    lastError: identical(lastError, _sentinel) ? this.lastError : lastError as String?,
    dailyCount: dailyCount ?? this.dailyCount,
    dailyCountDay: dailyCountDay ?? this.dailyCountDay,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'lastUploadedAt': lastUploadedAt,
    'lastCloudGeneratedAt': lastCloudGeneratedAt,
    'lastError': lastError,
    'dailyCount': dailyCount,
    'dailyCountDay': dailyCountDay,
  };

  static LibspSyncState fromJson(Object? raw) {
    if (raw is! Map) return const LibspSyncState();
    int? intOf(Object? v) => v is num ? v.toInt() : null;
    return LibspSyncState(
      enabled: raw['enabled'] == true,
      lastUploadedAt: intOf(raw['lastUploadedAt']),
      lastCloudGeneratedAt: intOf(raw['lastCloudGeneratedAt']),
      lastError: raw['lastError'] as String?,
      dailyCount: intOf(raw['dailyCount']) ?? 0,
      dailyCountDay: intOf(raw['dailyCountDay']),
    );
  }
}

const Object _sentinel = Object();

/// 闸门（纯逻辑，可单测）：防抖 + 每日上限 + 手动豁免。
class LibspSyncGate {
  const LibspSyncGate({
    this.minInterval = libspMinUploadInterval,
    this.dailyLimit = libspDailyUploadLimit,
  });

  final Duration minInterval;
  final int dailyLimit;

  /// 是否允许这次**自动**上传（手动同步不走这里）。
  bool allowsAuto(LibspSyncState state, DateTime now) {
    final last = state.lastUploadedAt;
    if (last != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(last)) <
            minInterval) {
      return false;
    }
    return _countToday(state, now) < dailyLimit;
  }

  /// 还要等多久才允许自动上传（已允许 → `Duration.zero`）。
  Duration remainingCooldown(LibspSyncState state, DateTime now) {
    final last = state.lastUploadedAt;
    if (last == null) return Duration.zero;
    final elapsed = now.difference(DateTime.fromMillisecondsSinceEpoch(last));
    if (elapsed >= minInterval) return Duration.zero;
    return minInterval - elapsed;
  }

  /// 今天还能自动上传几次。
  int remainingToday(LibspSyncState state, DateTime now) =>
      (dailyLimit - _countToday(state, now)).clamp(0, dailyLimit);

  /// 记录一次成功上传后的新状态（跨天自动归零计数）。
  LibspSyncState afterUpload(
    LibspSyncState state,
    DateTime now, {
    int? cloudGeneratedAt,
  }) => state.copyWith(
    lastUploadedAt: now.millisecondsSinceEpoch,
    lastCloudGeneratedAt: cloudGeneratedAt,
    lastError: null,
    dailyCount: _countToday(state, now) + 1,
    dailyCountDay: _dayKey(now),
  );

  int _countToday(LibspSyncState state, DateTime now) =>
      state.dailyCountDay == _dayKey(now) ? state.dailyCount : 0;

  static int _dayKey(DateTime t) => t.year * 10000 + t.month * 100 + t.day;
}

/// 同步偏好存储（内存缓存 + Hive 落盘，落盘尽力而为，绝不抛）。
class LibspSyncPrefsStore extends ChangeNotifier {
  LibspSyncState _state = const LibspSyncState();
  Box<String>? _box;
  Future<void>? _loading;

  LibspSyncState get state => _state;

  bool get enabled => _state.enabled;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final box = await Hive.openBox<String>(libspSyncPrefsBoxName);
      _box = box;
      final raw = box.get(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      _state = LibspSyncState.fromJson(jsonDecode(raw));
      notifyListeners();
    } catch (_) {
      // 存档不可用 / 损坏 → 保持「未开启」。
    }
  }

  /// 更新状态（内部用；界面调用 [setEnabled] / [markError]）。
  Future<void> update(LibspSyncState next) async {
    await ensureLoaded();
    _state = next;
    notifyListeners();
    final box = _box;
    if (box == null) return;
    try {
      await box.put(_prefsKey, jsonEncode(next.toJson()));
    } catch (_) {}
  }

  /// 开启 / 关闭同步。
  ///
  /// **关闭只停上传，不删云端**（Q13）：用户想清除要走「清除云端数据」。
  Future<void> setEnabled(bool value) => update(_state.copyWith(enabled: value));

  /// 记录一次失败（只留最近一条）。
  Future<void> markError(String? message) =>
      update(_state.copyWith(lastError: message));
}

/// 闸门 provider（无状态，直接构造）。
final libspSyncGateProvider = Provider<LibspSyncGate>(
  (ref) => const LibspSyncGate(),
);

/// 同步偏好 provider。
final libspSyncPrefsProvider = ChangeNotifierProvider<LibspSyncPrefsStore>((ref) {
  final store = LibspSyncPrefsStore();
  unawaited(store.ensureLoaded());
  return store;
});
