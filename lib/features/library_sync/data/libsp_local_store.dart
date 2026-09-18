/// 图书馆订阅词云同步 · 本机存储的真实实现（Hive）。
///
/// 三条口径：
/// 1. **偏好整箱搬运**（`box → key → 原样值`），不解析语义 —— 新增偏好落在白名单
///    box 里就自动跟随，无需改协议；
/// 2. 分数估计与综测走**账号级 box**（`score_estimate_<账号>` / `zongce_<账号>`），
///    与 App 现有隔离口径一致；
/// 3. **写入白名单守卫**：云端载荷里若出现非白名单 box（例如有人伪造一份
///    带 `imsAuth` 的载荷），一律跳过不写 —— 同步通道不能变成任意写入口。
library;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/storage/account_scoped_box.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_payload.dart';
import 'package:smarter_jxufe/features/library_sync/domain/libsp_remote.dart';
import 'package:smarter_jxufe/features/score_estimate/data/ge_store.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_models.dart';
import 'package:smarter_jxufe/features/zongce/data/zc_providers.dart';

/// Hive 实现。
class HiveLibspLocalStore implements LibspLocalStore {
  const HiveLibspLocalStore({required this.account});

  /// 当前登录账号（学号）；空 = 未登录（此时账号级 box 用 `__none`，不会误读他人数据）。
  final String account;

  @override
  Future<Map<String, Map<String, String>>> readPrefs() async {
    final out = <String, Map<String, String>>{};
    for (final name in kLibspSyncedPrefBoxes) {
      try {
        final box = await Hive.openBox<String>(name);
        final entries = <String, String>{};
        for (final key in box.keys) {
          final value = box.get(key.toString());
          if (value != null) entries[key.toString()] = value;
        }
        if (entries.isNotEmpty) out[name] = entries;
      } catch (e) {
        debugPrint('[libsp] 读取偏好 $name 失败：$e');
      }
    }
    return out;
  }

  @override
  Future<void> writePrefs(Map<String, Map<String, String>> prefs) async {
    for (final entry in prefs.entries) {
      if (!kLibspSyncedPrefBoxes.contains(entry.key)) {
        debugPrint('[libsp] 忽略非白名单 box：${entry.key}');
        continue;
      }
      // 只覆盖载荷里出现的 key（不整箱清空），避免把本机新增的偏好抹掉。
      try {
        final box = await Hive.openBox<String>(entry.key);
        for (final kv in entry.value.entries) {
          await box.put(kv.key, kv.value);
        }
      } catch (e) {
        debugPrint('[libsp] 写入偏好 ${entry.key} 失败：$e');
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> readCourses() async {
    try {
      final box = await openAccountScopedBox(geBoxName, account);
      final courses = await GeStore(box).loadCourses();
      return [for (final c in courses) c.toJson()];
    } catch (e) {
      debugPrint('[libsp] 读取分数估计失败：$e');
      return const [];
    }
  }

  @override
  Future<void> writeCourses(List<Map<String, dynamic>> courses) async {
    try {
      final box = await openAccountScopedBox(geBoxName, account);
      // 走真实模型解析一次：载荷里的脏字段在这一步被 clamp / 兜底，
      // 不会写进一个 Hive 读不回来的形态。
      await GeStore(box).saveCourses([
        for (final json in courses) GeCourse.fromJson(json),
      ]);
    } catch (e) {
      debugPrint('[libsp] 写入分数估计失败：$e');
    }
  }

  @override
  Future<Map<String, String>> readZongceEntries() async {
    try {
      final box = await openAccountScopedBox(zcBoxName, account);
      final out = <String, String>{};
      for (final key in box.keys) {
        final value = box.get(key.toString());
        if (value != null) out[key.toString()] = value;
      }
      return out;
    } catch (e) {
      debugPrint('[libsp] 读取综测失败：$e');
      return const {};
    }
  }

  @override
  Future<void> writeZongceEntries(Map<String, String> entries) async {
    try {
      final box = await openAccountScopedBox(zcBoxName, account);
      for (final entry in entries.entries) {
        await box.put(entry.key, entry.value);
      }
    } catch (e) {
      debugPrint('[libsp] 写入综测失败：$e');
    }
  }
}
