import 'dart:convert';

import 'package:hive/hive.dart';

import 'package:smarter_jxufe/core/network/schedule_repository.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/utils/Log.dart';

/// 课表 Hive box 名。
const scheduleCacheBoxName = 'scheduleCache';

/// 一次课表读取的结果（含缓存元信息与降级错误）。
class CachedSchedule {
  /// 课表条目（可能来自缓存，也可能是刚拉取的）。
  final List<ScheduleEntry> entries;

  /// 该数据的落库时间；仅当来自缓存时有值。
  final DateTime? fetchedAt;

  /// 是否来自本地缓存（true = 未联网或联网失败后降级）。
  final bool fromCache;

  /// 联网刷新失败时的错误信息（此时 [entries] 是缓存内容）。
  final String? refreshError;

  const CachedSchedule({
    required this.entries,
    this.fetchedAt,
    this.fromCache = false,
    this.refreshError,
  });

  bool get isEmpty => entries.isEmpty;
}

/// 课表缓存仓库（cache-first）。
///
/// 实况窗必须**离线可算**：断网、或教务会话过期时，倒计时仍要正确。
/// 故这里在既有 [ScheduleRepository]（纯在线）外面包一层缓存，
/// 不改动其原有调用方。
///
/// 读取策略：
/// - `refresh: false` → 先返回缓存（若有），无缓存才联网；
/// - `refresh: true`  → 联网刷新；失败时降级返回缓存并带上 [CachedSchedule.refreshError]。
class ScheduleCacheRepository {
  final ScheduleRepository _inner;

  ScheduleCacheRepository(this._inner);

  /// 读取课表。[refresh] 为 true 时强制联网。
  Future<CachedSchedule> load({
    required String year,
    required String semester,
    required String studentId,
    bool refresh = false,
  }) async {
    final box = await Hive.openBox<String>(scheduleCacheBoxName);
    final key = _key(year, semester, studentId);
    final cached = _readCache(box, key);

    if (!refresh && cached != null && !cached.isEmpty) {
      // 缓存命中：仍尝试静默刷新由调用方决定（此处不阻塞首屏）
      return cached;
    }

    try {
      final entries = await _inner.getSchedule(
        year: year,
        semester: semester,
        studentId: studentId,
      );
      if (entries.isNotEmpty) {
        await box.put(
          key,
          jsonEncode({
            'entries': entries.map((e) => e.toJson()).toList(),
            'fetchedAt': DateTime.now().toIso8601String(),
          }),
        );
      }
      return CachedSchedule(entries: entries);
    } catch (e) {
      logInfo('课表拉取失败: $e');
      if (cached != null) {
        return CachedSchedule(
          entries: cached.entries,
          fetchedAt: cached.fetchedAt,
          fromCache: true,
          refreshError: e.toString(),
        );
      }
      rethrow;
    }
  }

  /// 仅读缓存，不联网。用于实况窗在后台/首帧快速取数。
  Future<CachedSchedule?> readCache({
    required String year,
    required String semester,
    required String studentId,
  }) async {
    final box = await Hive.openBox<String>(scheduleCacheBoxName);
    return _readCache(box, _key(year, semester, studentId));
  }

  /// 读「任意学号」下该学期的缓存（不联网）。
  ///
  /// 场景：设置页的「显示周六 / 周日」开关要提示「这一学期周六有 N 门课」，
  /// 但设置页拿不到课表页的学籍上下文（`serialNo`）→ 按 key 前缀取已存在的
  /// 那一份缓存即可。[preferStudentId] 命中时优先，保证多账号设备上先用本人的。
  /// 没有任何缓存时返回 null（调用方按「判不出有没有课」处理）。
  Future<CachedSchedule?> readCacheAnyStudent({
    required String year,
    required String semester,
    String? preferStudentId,
  }) async {
    final box = await Hive.openBox<String>(scheduleCacheBoxName);
    final prefix = 'schedule|$year|$semester|';
    final preferred = preferStudentId == null || preferStudentId.isEmpty
        ? null
        : '$prefix$preferStudentId';
    final keys = box.keys
        .whereType<String>()
        .where((k) => k.startsWith(prefix))
        .toList();
    if (keys.isEmpty) return null;
    if (preferred != null && keys.contains(preferred)) {
      return _readCache(box, preferred);
    }
    keys.sort();
    return _readCache(box, keys.first);
  }

  CachedSchedule? _readCache(Box<String> box, String key) {
    final raw = box.get(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final entries = <ScheduleEntry>[];
      final rawEntries = decoded['entries'];
      if (rawEntries is List) {
        for (final item in rawEntries) {
          final e = ScheduleEntry.fromJson(item);
          if (e != null) entries.add(e);
        }
      }
      DateTime? fetchedAt;
      final rawAt = decoded['fetchedAt'];
      if (rawAt is String) fetchedAt = DateTime.tryParse(rawAt);
      if (entries.isEmpty) return null;
      return CachedSchedule(
        entries: entries,
        fetchedAt: fetchedAt,
        fromCache: true,
      );
    } catch (e) {
      // 旧缓存损坏时丢弃，不影响联网刷新
      logInfo('课表缓存解析失败: $e');
      return null;
    }
  }

  String _key(String year, String semester, String studentId) =>
      'schedule|$year|$semester|$studentId';
}
