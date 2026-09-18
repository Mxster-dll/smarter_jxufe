/// 课表显示偏好（是否显示周六 / 周日、是否显示表格线）的持久化。
///
/// Hive `schedulePrefs` 单 key JSON，口径与 `school_calendar/data/calendar_prefs.dart`
/// 一致：`ChangeNotifier` + 「尽力而为」落盘（Hive 打不开时仅本次会话生效）。
/// 用户 2026-09-17 需求：「课表加两个设置，是否显示周六、是否显示周日」+
/// 「我希望课表可以设置是否显示表格线」—— 按 §3 的偏好口径，**开关只在设置页**
/// （课表页的齿轮进设置页「课表」节），两个偏好共用这一个 box / key。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 存储 box 名（与 `schoolCalendarPrefs`、`scheduleCache` 等分开）。
const schedulePrefsBoxName = 'schedulePrefs';

/// 单 key（整表 JSON 存取，容错优先）。
const _prefsKey = 'display';

/// 课表显示偏好。
@immutable
class ScheduleDisplayPrefs {
  /// 显示周六（默认开）。
  final bool showSaturday;

  /// 显示周日（默认开）。
  final bool showSunday;

  /// 显示表格线（默认开 = 改动前的观感）。
  ///
  /// 用户 2026-09-17：「我希望课表可以设置是否显示表格线」。关掉后竖版 / 横版的
  /// **所有**表格分隔线都不画（含表头里的白线），课格靠自身底色区分；
  /// **语义标记线**（调课格的橙色上边、`补/调/停` 角标）不属于表格线，照旧。
  final bool showGridLines;

  const ScheduleDisplayPrefs({
    this.showSaturday = true,
    this.showSunday = true,
    this.showGridLines = true,
  });

  ScheduleDisplayPrefs copyWith({
    bool? showSaturday,
    bool? showSunday,
    bool? showGridLines,
  }) => ScheduleDisplayPrefs(
    showSaturday: showSaturday ?? this.showSaturday,
    showSunday: showSunday ?? this.showSunday,
    showGridLines: showGridLines ?? this.showGridLines,
  );

  Map<String, dynamic> toJson() => {
    'showSaturday': showSaturday,
    'showSunday': showSunday,
    'showGridLines': showGridLines,
  };

  /// 容错解析：字段缺失 / 类型异常一律回落默认值（默认 = 都显示 / 显示表格线）。
  ///
  /// ⚠ 不能用 `json['x'] as bool?`：脏数据（如 `'no'`）会抛
  /// `type 'String' is not a subtype of type 'bool?'`（守卫测试实测抓到）。
  /// 旧存档没有 `showGridLines` 键 → [_boolOf] 给 true（= 历史观感，不改变老用户）。
  factory ScheduleDisplayPrefs.fromJson(Map<String, dynamic> json) =>
      ScheduleDisplayPrefs(
        showSaturday: _boolOf(json['showSaturday']),
        showSunday: _boolOf(json['showSunday']),
        showGridLines: _boolOf(json['showGridLines']),
      );

  /// 只认真正的 bool，其余（null / 字符串 / 数字）一律当作默认 true。
  static bool _boolOf(Object? raw) => raw is bool ? raw : true;

  @override
  bool operator ==(Object other) =>
      other is ScheduleDisplayPrefs &&
      other.showSaturday == showSaturday &&
      other.showSunday == showSunday &&
      other.showGridLines == showGridLines;

  @override
  int get hashCode => Object.hash(showSaturday, showSunday, showGridLines);
}

/// 课表显示偏好存储（内存缓存 + Hive 落盘）。
///
/// 由 `scheduleDisplayPrefsStoreProvider` 持有与释放（**不是全局单例**：
/// `ChangeNotifierProvider` 会在容器释放时 dispose 掉实例）。
class ScheduleDisplayPrefsStore extends ChangeNotifier {
  /// [initial] 用于测试或预览直接给定偏好（此时不再读 Hive，也不落盘）。
  ScheduleDisplayPrefsStore({ScheduleDisplayPrefs? initial})
    : _prefs = initial ?? const ScheduleDisplayPrefs(),
      _loaded = initial != null;

  ScheduleDisplayPrefs _prefs;
  bool _loaded;
  Box<String>? _box;

  ScheduleDisplayPrefs get prefs => _prefs;

  bool get isLoaded => _loaded;

  /// 首次读取落盘值（幂等；失败保持默认值）。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final box = await Hive.openBox<String>(schedulePrefsBoxName);
      _box = box;
      final raw = box.get(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _prefs = ScheduleDisplayPrefs.fromJson(
          decoded.map((k, v) => MapEntry('$k', v)),
        );
        notifyListeners();
      }
    } catch (_) {
      // 存档不可用 / 损坏：保留默认值。
    }
  }

  /// 写入新偏好（设置页每次改动调用）。绝不抛异常。
  Future<void> save(ScheduleDisplayPrefs next) async {
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
