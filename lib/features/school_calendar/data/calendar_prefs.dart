/// 校历页「显示设置」的持久化（Hive `schoolCalendarPrefs` 单 key JSON）。
///
/// 三项均为用户可选（2026-09-11 需求）：角标风格、非新生是否显示军训、是否按
/// 培养层次过滤官方事件。用 [ChangeNotifier] 而非 AsyncNotifier：设置面板改动
/// 要立刻反映到当前页面的月历上（无需重新拉数据）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/box_reload_watcher.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';

/// 存储 box 名（与 `wxPlatform`、`scheduleReschedules` 等分开）。
const calendarPrefsBoxName = 'schoolCalendarPrefs';

/// 单 key（整表 JSON 存取，容错优先）。
const _prefsKey = 'display';

/// 校历显示偏好。
@immutable
class CalendarDisplayPrefs {
  /// 角标风格。
  final CalendarBadgeStyle badgeStyle;

  /// 非新生也显示军训角标（默认关：军训只在本人入学年显示）。
  final bool alwaysShowMilitary;

  /// 按本人培养层次过滤官方事件（默认开）。
  final bool filterByCategory;

  const CalendarDisplayPrefs({
    this.badgeStyle = CalendarBadgeStyle.underNumber,
    this.alwaysShowMilitary = false,
    this.filterByCategory = true,
  });

  CalendarDisplayPrefs copyWith({
    CalendarBadgeStyle? badgeStyle,
    bool? alwaysShowMilitary,
    bool? filterByCategory,
  }) => CalendarDisplayPrefs(
    badgeStyle: badgeStyle ?? this.badgeStyle,
    alwaysShowMilitary: alwaysShowMilitary ?? this.alwaysShowMilitary,
    filterByCategory: filterByCategory ?? this.filterByCategory,
  );

  Map<String, dynamic> toJson() => {
    'badgeStyle': badgeStyle.name,
    'alwaysShowMilitary': alwaysShowMilitary,
    'filterByCategory': filterByCategory,
  };

  /// 容错解析：字段缺失 / 类型异常 / 枚举名过期一律回落默认值。
  factory CalendarDisplayPrefs.fromJson(Map<String, dynamic> json) =>
      CalendarDisplayPrefs(
        badgeStyle: CalendarBadgeStyle.fromName(json['badgeStyle'] as String?),
        alwaysShowMilitary: json['alwaysShowMilitary'] as bool? ?? false,
        filterByCategory: json['filterByCategory'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is CalendarDisplayPrefs &&
      other.badgeStyle == badgeStyle &&
      other.alwaysShowMilitary == alwaysShowMilitary &&
      other.filterByCategory == filterByCategory;

  @override
  int get hashCode =>
      Object.hash(badgeStyle, alwaysShowMilitary, filterByCategory);
}

/// 校历显示偏好存储（内存缓存 + Hive 落盘）。
///
/// 由 `calendarPrefsStoreProvider` 持有与释放（**不是全局单例**：
/// `ChangeNotifierProvider` 会在容器释放时 dispose 掉实例，单例会被误伤）。
/// 落盘是「尽力而为」：Hive 打开失败时仅内存生效，不抛异常、不影响界面。
/// 混入 [BoxReloadWatcher]：**外部写入**（云同步「从云端恢复」）也要反映到界面。
class CalendarPrefsStore extends ChangeNotifier with BoxReloadWatcher {
  /// [initial] 用于测试或预览直接给定偏好（此时不再读 Hive，也不落盘）。
  CalendarPrefsStore({CalendarDisplayPrefs? initial})
    : _prefs = initial ?? const CalendarDisplayPrefs(),
      _loaded = initial != null;

  CalendarDisplayPrefs _prefs;
  bool _loaded;
  Box<String>? _box;

  CalendarDisplayPrefs get prefs => _prefs;

  bool get isLoaded => _loaded;

  /// 首次读取落盘值（幂等；失败保持默认值，且此后不再尝试落盘）。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final box = await Hive.openBox<String>(calendarPrefsBoxName);
      _box = box;
      bindBoxReload(box, _readFromBox);
      _readFromBox(box);
    } catch (_) {
      // 存档不可用 / 损坏：保留默认值。
    }
  }

  /// 从 box 重读（首载与外部写入共用）；解析不出来 / 值没变就不通知。
  void _readFromBox(Box<String> box) {
    try {
      final raw = box.get(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final next = CalendarDisplayPrefs.fromJson(
        decoded.map((k, v) => MapEntry('$k', v)),
      );
      if (next == _prefs) return;
      _prefs = next;
      notifyListeners();
    } catch (_) {
      // 脏数据：保留当前值。
    }
  }

  /// 写入新偏好（设置面板每次改动调用）。绝不抛异常。
  Future<void> save(CalendarDisplayPrefs next) async {
    if (next == _prefs) return;
    _prefs = next;
    notifyListeners();
    final box = _box;
    if (box == null) return; // 存储不可用 → 仅本次会话生效
    try {
      await box.put(_prefsKey, jsonEncode(next.toJson()));
    } catch (_) {
      // 落盘失败不影响本次会话内的显示。
    }
  }
}
