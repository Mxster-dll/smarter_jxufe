/// 公共查询（找空闲教室 / 找无课时间）的用户偏好持久化 —— Hive `publicQueryPrefs` 单 key。
///
/// 目前只有一项：**默认教学楼**（用户 2026-09-19：「教学楼默认选哪个是可以设置的」）。
/// 唯一设置入口 = 设置页「公共查询」节（§3「新增用户偏好一律收拢到设置页」）。
///
/// 用 [ChangeNotifier] 而非 FutureProvider：设置页一改，找空闲教室页下次打开（乃至
/// 本次打开时若还没落定）就要用上新值，中间不能有异步空窗（照
/// `lib/features/campus_address/data/my_campus_prefs.dart`）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/box_reload_watcher.dart';

/// 存储 box 名（与 `myCampusPrefs`、`tsgxsPrefs` 等分开）。
const publicQueryPrefsBoxName = 'publicQueryPrefs';

/// 单 key（值是整份偏好的 JSON；「未设置」= 该 key 不存在）。
const _prefsKey = 'defaults';

/// 默认教学楼：**必须连它的校区一起记**（楼房码只在所属校区内有意义，实测
/// `MsSchoolArea_LF` 的 `lf_m` 是按校区过滤的）。
@immutable
class PublicQueryBuilding {
  /// 校区码（`MsSchoolArea` 的 code，如 `3`）。
  final String campusCode;

  /// 校区显示名（如 `麦庐园校区`）——只为在设置页里显示得完整。
  final String campusName;

  /// 楼房码（`MsSchoolArea_LF` 的 code，如 `35`）。
  final String buildingCode;

  /// 楼房显示名（如 `白云楼`）。
  final String buildingName;

  const PublicQueryBuilding({
    required this.campusCode,
    required this.campusName,
    required this.buildingCode,
    required this.buildingName,
  });

  /// 设置页里的展示文案：`麦庐园校区 · 白云楼`。
  String get label {
    if (campusName.isEmpty) return buildingName;
    if (buildingName.isEmpty) return campusName;
    return '$campusName · $buildingName';
  }

  /// 三项足以定位一栋楼（校区/楼房码 + 名字）；名字缺失时仍可用（只是显示得朴素）。
  bool get isUsable => buildingCode.trim().isNotEmpty;

  Map<String, Object?> toJson() => {
    'campusCode': campusCode,
    'campusName': campusName,
    'buildingCode': buildingCode,
    'buildingName': buildingName,
  };

  /// 容错解析：非 Map / 楼房码缺失 → null（**不猜**，宁可当没设过）。
  static PublicQueryBuilding? fromJson(Object? value) {
    if (value is! Map) return null;
    final campusCode = '${value['campusCode'] ?? ''}'.trim();
    final campusName = '${value['campusName'] ?? ''}'.trim();
    final buildingCode = '${value['buildingCode'] ?? ''}'.trim();
    final buildingName = '${value['buildingName'] ?? ''}'.trim();
    if (buildingCode.isEmpty) return null;
    return PublicQueryBuilding(
      campusCode: campusCode,
      campusName: campusName,
      buildingCode: buildingCode,
      buildingName: buildingName,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PublicQueryBuilding &&
      other.campusCode == campusCode &&
      other.campusName == campusName &&
      other.buildingCode == buildingCode &&
      other.buildingName == buildingName;

  @override
  int get hashCode =>
      Object.hash(campusCode, campusName, buildingCode, buildingName);

  @override
  String toString() => 'PublicQueryBuilding($label)';
}

/// 公共查询的全部偏好（现在只有一项，后续新增字段往这里加即可，别另开 key）。
@immutable
class PublicQueryPrefs {
  /// 默认教学楼；`null` = 不预选（用户没设过，或已清除）。
  final PublicQueryBuilding? building;

  const PublicQueryPrefs({this.building});

  static const empty = PublicQueryPrefs();

  PublicQueryPrefs copyWith({PublicQueryBuilding? building, bool clearBuilding = false}) =>
      PublicQueryPrefs(building: clearBuilding ? null : (building ?? this.building));

  Map<String, Object?> toJson() => {'building': building?.toJson()};

  /// 容错解析：非 Map / 字段坏 → 回落 [empty]（旧存档、脏数据都不许崩）。
  static PublicQueryPrefs fromJson(Object? value) {
    if (value is! Map) return empty;
    return PublicQueryPrefs(building: PublicQueryBuilding.fromJson(value['building']));
  }

  @override
  bool operator ==(Object other) =>
      other is PublicQueryPrefs && other.building == building;

  @override
  int get hashCode => building.hashCode;

  @override
  String toString() => 'PublicQueryPrefs(building=${building?.label})';
}

/// 公共查询偏好存储（内存缓存 + Hive 落盘）。
///
/// 落盘「尽力而为」：Hive 打不开时仅本次会话生效，不抛异常、不影响界面。
/// 混入 [BoxReloadWatcher]：**外部写入**（云同步「从云端恢复」）也要反映到界面。
class PublicQueryPrefsStore extends ChangeNotifier with BoxReloadWatcher {
  PublicQueryPrefs _prefs = PublicQueryPrefs.empty;
  Box<String>? _box;
  Future<void>? _loading;

  /// 当前偏好（永不返回 null）。
  PublicQueryPrefs get prefs => _prefs;

  /// 默认教学楼（`null` = 没设过）。
  PublicQueryBuilding? get defaultBuilding => _prefs.building;

  /// 首次读取落盘值（幂等：并发调用共用同一个 Future）。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final box = await Hive.openBox<String>(publicQueryPrefsBoxName);
      _box = box;
      bindBoxReload(box, _readFromBox);
      _readFromBox(box);
    } catch (_) {
      // 存档不可用 / 损坏：保持未设置。
    }
  }

  /// 从 box 重读（首载与外部写入共用）；值没变就不通知。
  void _readFromBox(Box<String> box) {
    final raw = box.get(_prefsKey);
    PublicQueryPrefs parsed;
    try {
      parsed = raw == null
          ? PublicQueryPrefs.empty
          : PublicQueryPrefs.fromJson(jsonDecode(raw));
    } catch (_) {
      parsed = PublicQueryPrefs.empty;
    }
    if (parsed == _prefs) return;
    _prefs = parsed;
    notifyListeners();
  }

  /// 写入默认教学楼（`null` = 清除）。绝不抛异常。
  Future<void> saveBuilding(PublicQueryBuilding? next) async {
    await ensureLoaded();
    if (next == _prefs.building) return;
    _prefs = _prefs.copyWith(building: next, clearBuilding: next == null);
    notifyListeners();
    final box = _box;
    if (box == null) return; // 存储不可用 → 仅本次会话生效
    try {
      if (next == null) {
        await box.delete(_prefsKey);
      } else {
        await box.put(_prefsKey, jsonEncode(_prefs.toJson()));
      }
    } catch (_) {
      // 落盘失败不影响本次会话内的显示。
    }
  }
}

/// 公共查询偏好（改动即时通知，页面直接 watch）。
final publicQueryPrefsStoreProvider =
    ChangeNotifierProvider<PublicQueryPrefsStore>((ref) {
      final store = PublicQueryPrefsStore();
      unawaited(store.ensureLoaded());
      return store;
    });
