/// 课前提醒偏好（开关 + 提前量 X 分钟，默认 30）的持久化。
///
/// 用户 2026-09-22 原话：「我希望在任何一节课上课前x分钟(x可设置，默认30）到上课前，
/// 移动端显示一个常驻通知，下节课的名称和教室」。
///
/// Hive `schedulePrefs` 单 key JSON（与课表显示偏好**同一个 box、不同 key**），
/// 口径与 `schedule_display_prefs.dart` 一致：`ChangeNotifier` + 「尽力而为」落盘
/// （Hive 打不开时仅本次会话生效）。**唯一写入点 = 设置页「上课提醒」节**
/// （§3 铁律：新增用户偏好一律收拢到设置页，页面里不另开弹层）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/schedule_display_prefs.dart'
    show schedulePrefsBoxName;
import 'package:smarter_jxufe/features/ims/schedule/domain/class_start_reminder.dart';

/// 单 key（与课表显示偏好的 `display` 分开，互不覆盖）。
const String classReminderPrefsKey = 'classReminder';

/// 课前提醒偏好。
@immutable
class ClassReminderPrefs {
  /// 是否开启课前提醒（默认开 —— 用户 2026-09-22 立项即想要这个功能）。
  final bool enabled;

  /// 提前量（分钟），默认 30。
  final int leadMinutes;

  const ClassReminderPrefs({
    this.enabled = true,
    this.leadMinutes = classReminderDefaultLeadMinutes,
  });

  /// 提前量（[Duration] 形态，排期直接用）。
  Duration get lead => Duration(minutes: leadMinutes);

  ClassReminderPrefs copyWith({bool? enabled, int? leadMinutes}) =>
      ClassReminderPrefs(
        enabled: enabled ?? this.enabled,
        leadMinutes: leadMinutes ?? this.leadMinutes,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'leadMinutes': leadMinutes,
  };

  /// 容错解析：字段缺失 / 类型异常一律回落默认值，并把提前量夹进合法区间。
  ///
  /// ⚠ 不能用 `json['x'] as bool?`：脏数据（如 `'no'`）会抛
  /// `type 'String' is not a subtype of type 'bool?'`（课表显示偏好实测抓到过）。
  factory ClassReminderPrefs.fromJson(Map<String, dynamic> json) {
    final rawLead = json['leadMinutes'];
    return ClassReminderPrefs(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      leadMinutes: clampClassReminderLead(
        rawLead is num ? rawLead.toInt() : classReminderDefaultLeadMinutes,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClassReminderPrefs &&
      other.enabled == enabled &&
      other.leadMinutes == leadMinutes;

  @override
  int get hashCode => Object.hash(enabled, leadMinutes);
}

/// 课前提醒偏好存储（内存缓存 + Hive 落盘）。
///
/// 由 `classReminderPrefsStoreProvider` 持有与释放（**不是全局单例**：
/// `ChangeNotifierProvider` 会在容器释放时 dispose 掉实例）。
class ClassReminderPrefsStore extends ChangeNotifier {
  /// [initial] 用于测试或预览直接给定偏好（此时不再读 Hive，也不落盘）。
  ClassReminderPrefsStore({ClassReminderPrefs? initial})
    : _prefs = initial ?? const ClassReminderPrefs(),
      _loaded = initial != null;

  ClassReminderPrefs _prefs;
  bool _loaded;
  Box<String>? _box;

  ClassReminderPrefs get prefs => _prefs;

  bool get isLoaded => _loaded;

  /// 首次读取落盘值（幂等；失败保持默认值）。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final box = await Hive.openBox<String>(schedulePrefsBoxName);
      _box = box;
      final raw = box.get(classReminderPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _prefs = ClassReminderPrefs.fromJson(
          decoded.map((k, v) => MapEntry('$k', v)),
        );
        notifyListeners();
      }
    } catch (_) {
      // 存档不可用 / 损坏：保留默认值。
    }
  }

  /// 写入新偏好（设置页每次改动调用）。绝不抛异常。
  Future<void> save(ClassReminderPrefs next) async {
    if (next == _prefs) return;
    _prefs = next;
    notifyListeners();
    final box = _box;
    if (box == null) return; // 存储不可用 → 仅本次会话生效
    try {
      await box.put(classReminderPrefsKey, jsonEncode(next.toJson()));
    } catch (_) {
      // 落盘失败不影响本次会话内的提醒。
    }
  }
}
