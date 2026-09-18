/// 课表显示偏好与「按学期读缓存课表」的 provider。
///
/// 为了让**设置页**（而不是课表页）也能判断「周六 / 周日有没有课」，
/// 这里提供一个只读缓存的轻量 provider：设置页拿不到课表页的学籍上下文，
/// 就按 `scheduleCache` 的 key 前缀取一份该学期的缓存
/// （见 [ScheduleCacheRepository.readCacheAnyStudent]），**不联网**。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/dio_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/schedule_display_prefs.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';

/// 课表显示偏好（Hive `schedulePrefs` / key `display`）。
///
/// ⚠ 只读不写：**唯一写入点 = 设置页「课表」节**（用户 2026-09-17 裁定，
/// 与 §3「新增用户偏好一律收拢到设置页」一致）。
final scheduleDisplayPrefsStoreProvider =
    ChangeNotifierProvider<ScheduleDisplayPrefsStore>((ref) {
      final store = ScheduleDisplayPrefsStore();
      unawaited(store.ensureLoaded());
      return store;
    });

/// 某学期的课表（**只读缓存，不联网**；没有缓存就是空列表）。
final scheduleCachedEntriesProvider =
    FutureProvider.family<List<ScheduleEntry>, ({int xn, int xq})>((
      ref,
      term,
    ) async {
      try {
        final repository = await ref.watch(scheduleCacheRepositoryProvider.future);
        final cached = await repository.readCacheAnyStudent(
          year: '${term.xn}',
          semester: '${term.xq}',
          preferStudentId: ref.read(currentAccountProvider),
        );
        return cached?.entries ?? const <ScheduleEntry>[];
      } catch (_) {
        // 设置页的确认提示属于「尽力而为」：取不到就当没有课，不阻塞开关。
        return const <ScheduleEntry>[];
      }
    });
