/// AI 助手配置的持久化（Hive `aiSettings` 单 key JSON）。
///
/// 照 `lib/features/campus_address/data/my_campus_prefs.dart` 的范式：
/// Hive `Box<String>` 单 key + [ChangeNotifier] + [ChangeNotifierProvider]
/// —— 设置页改完要**立刻**反映到对话页 / 悬浮球，用 FutureProvider 会先闪一次旧值。
///
/// ⚠ 本 box **不得**加入云同步载荷白名单（`lib/features/library_sync/data/libsp_payload.dart`）：
/// 里面存着 API Key，云同步是明文过图书馆订阅词这条通道，不该外传。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:smarter_jxufe/core/storage/box_reload_watcher.dart';
import 'package:smarter_jxufe/features/ai/domain/ai_config.dart';

/// 存储 box 名。
const aiSettingsBoxName = 'aiSettings';

/// 单 key。
const _settingsKey = 'settings';

/// 生成配置档 id（与仓库其它地方一致，用 uuid v4）。
String newAiConfigId() => const Uuid().v4();

/// AI 配置存储（内存缓存 + Hive 落盘）。
///
/// 落盘「尽力而为」：Hive 打不开时仅本次会话生效，不抛异常、不打崩设置页。
class AiSettingsStore extends ChangeNotifier with BoxReloadWatcher {
  /// `false` = 只在内存里改，不碰 Hive。
  ///
  /// 给测试用（widget 测试里 Hive 的文件 IO 会挂在假异步时钟上）；
  /// 也让以后做「访客模式 / 不写盘」时有个现成开关。
  final bool persist;

  AiSettingsStore({this.persist = true});

  AiSettings _settings = AiSettings.empty;
  Box<String>? _box;
  Future<void>? _loading;
  String? _lastRaw;

  /// 当前设置。
  AiSettings get settings => _settings;

  /// 首次读取落盘值（幂等：并发调用共用同一个 Future）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    if (!persist) return;
    try {
      final box = await Hive.openBox<String>(aiSettingsBoxName);
      _box = box;
      bindBoxReload(box, _readFromBox);
      _readFromBox(box);
    } catch (_) {
      // 存档不可用 / 损坏：保持「未配置」。
    }
  }

  /// 从 box 重读（首载与外部写入共用）；内容没变就不通知。
  void _readFromBox(Box<String> box) {
    final raw = box.get(_settingsKey);
    if (raw == _lastRaw) return;
    _lastRaw = raw;
    _settings = decodeAiSettings(raw);
    notifyListeners();
  }

  /// 整体替换设置。绝不抛异常。
  Future<void> save(AiSettings next) async {
    await ensureLoaded();
    final raw = jsonEncode(next.toJson());
    if (raw == _lastRaw) return;
    _settings = next;
    _lastRaw = raw;
    notifyListeners();
    final box = _box;
    if (box == null) return; // 存储不可用 → 仅本次会话生效
    try {
      await box.put(_settingsKey, raw);
    } catch (_) {
      // 落盘失败不影响本次会话内的使用。
    }
  }

  /// 新增 / 更新一套配置。
  Future<void> upsertProfile(AiConfig profile) =>
      save(_settings.upsertProfile(profile));

  /// 删除一套配置。
  Future<void> removeProfile(String id) => save(_settings.removeProfile(id));

  /// 切换当前生效配置。
  Future<void> activate(String id) => save(_settings.activate(id));

  /// 开关悬浮球。
  Future<void> setFloatingBall(bool value) =>
      save(_settings.copyWith(floatingBall: value));

  /// 改工具轮次上限。
  Future<void> setMaxToolRounds(int value) =>
      save(_settings.copyWith(maxToolRounds: value));
}

/// 容错解析存盘 JSON（坏数据 → 空设置，绝不抛）。
AiSettings decodeAiSettings(String? raw) {
  if (raw == null || raw.trim().isEmpty) return AiSettings.empty;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return AiSettings.fromJson(Map<String, dynamic>.from(decoded));
    }
  } catch (_) {
    // 坏存档：当作没配过
  }
  return AiSettings.empty;
}

/// AI 设置（改动即时通知，页面直接 watch）。
final aiSettingsStoreProvider = ChangeNotifierProvider<AiSettingsStore>((ref) {
  final store = AiSettingsStore();
  unawaited(store.ensureLoaded());
  return store;
});

/// 当前生效的配置（未配置 / 未加载完 → null）。
final aiActiveConfigProvider = Provider<AiConfig?>((ref) {
  final store = ref.watch(aiSettingsStoreProvider);
  return store.settings.active;
});

/// 是否已配好到可以直接开聊。
final aiReadyProvider = Provider<bool>((ref) {
  final store = ref.watch(aiSettingsStoreProvider);
  return store.settings.ready;
});

/// 悬浮球开关。
final aiFloatingBallProvider = Provider<bool>((ref) {
  final store = ref.watch(aiSettingsStoreProvider);
  return store.settings.floatingBall;
});
