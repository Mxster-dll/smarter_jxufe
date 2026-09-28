/// 课前提醒的 provider（偏好 store）。
///
/// `classReminderSyncProvider`（排期驱动）在 `data/class_reminder_sync.dart`：
/// 它反过来 import 本文件，故两者**只能单向依赖**，本文件不 import 它。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/class_reminder_prefs.dart';

/// 课前提醒偏好（Hive `schedulePrefs` / key `classReminder`）。
///
/// ⚠ 只读不写：**唯一写入点 = 设置页「上课提醒」节**（用户 2026-09-22 需求，
/// 与 §3「新增用户偏好一律收拢到设置页」一致）。
final classReminderPrefsStoreProvider =
    ChangeNotifierProvider<ClassReminderPrefsStore>((ref) {
      final store = ClassReminderPrefsStore();
      unawaited(store.ensureLoaded());
      return store;
    });
