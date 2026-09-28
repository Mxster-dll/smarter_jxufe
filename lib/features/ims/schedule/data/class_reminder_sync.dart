/// 课前提醒的排期同步（把系统通知排期对齐到「未来一周每节课」）。
///
/// 口径见 `domain/class_start_reminder.dart`；本文件负责三件事：
/// 1. [syncClassStartReminders]：算出期望排期 → 与系统现有排期对账 → 不一致才整段重排
///    （**幂等**：一致时一个系统调用都不发，避免每次回前台都扰动系统闹钟）；
/// 2. [cancelClassStartReminders]：关掉开关 / 退出登录时清空本模块区间内的排期；
/// 3. [ClassReminderSync]：面向 App 生命周期的驱动（读偏好 + 课表缓存 + 作息表 +
///    教学周 + 调课记录，再调上面两个）—— 由 `classReminderSyncProvider` 持有。
///
/// 驱动**只在 Android 上真排**：用户 2026-09-22 的口径是「移动端显示一个常驻通知」，
/// 而常驻（ongoing + 自动撤下 + 系统计时器）是 Android 形态。
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smarter_jxufe/core/network/current_account_provider.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/class_reminder_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/reschedule_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_start_reminder.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/student_info/data/providers/student_info_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/student_info/domain/student_info.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/wxcal_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/school_term.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';
import 'package:smarter_jxufe/shared/services/notification_service.dart';

/// 把系统排期对齐到 [entries]（幂等）。
///
/// 返回真正排上的条数；任何异常都吞掉并返回 0（提醒失败不该影响任何页面）。
Future<int> syncClassStartReminders({
  required List<ScheduleEntry> entries,
  required PeriodTable table,
  required int teachingWeek,
  required Duration lead,
  List<Reschedule> reschedules = const <Reschedule>[],
  NotificationService? service,
  DateTime? now,
  int days = classReminderHorizonDays,
  int max = classReminderMaxScheduled,
}) async {
  final at = now ?? DateTime.now();
  final svc = service ?? NotificationService.instance;
  try {
    final desired = classStartRemindersFor(
      entries: entries,
      table: table,
      teachingWeek: teachingWeek,
      now: at,
      lead: lead,
      reschedules: reschedules,
      days: days,
      max: max,
    );
    final pending = await svc.pendingScheduled();
    if (classStartScheduleMatches(desired: desired, pending: pending)) {
      return desired.length;
    }
    final stale = [
      for (final p in pending)
        if (classStartIdInRange(p.id)) p.id,
    ];
    if (stale.isNotEmpty) await svc.cancelScheduled(stale);

    var ok = 0;
    for (final r in desired) {
      final done = await svc.scheduleAt(
        id: r.id,
        title: r.title,
        body: r.body,
        when: r.when,
        payload: r.payload,
        // 常驻到上课那一刻：系统按 autoDismissAfter 自动撤下。
        ongoing: true,
        autoDismissAfter: r.dismissAfter,
        // 通知栏上由系统走秒，显示「距上课还有多久」。
        countdown: true,
        // 课前提醒是时间敏感的：能精确就精确，拿不到授权自动退回非精确。
        preferExact: true,
      );
      if (done) ok++;
    }
    if (desired.isNotEmpty) {
      debugPrint('🔔 课前提醒已排期 $ok/${desired.length} 条');
    }
    return ok;
  } catch (e) {
    debugPrint('⚠ 课前提醒排期失败: $e');
    return 0;
  }
}

/// 撤销本模块区间内的全部排期（关开关 / 退出登录时调用）。
Future<void> cancelClassStartReminders({NotificationService? service}) async {
  final svc = service ?? NotificationService.instance;
  try {
    final pending = await svc.pendingScheduled();
    final ids = [
      for (final p in pending)
        if (classStartIdInRange(p.id)) p.id,
    ];
    if (ids.isNotEmpty) await svc.cancelScheduled(ids);
  } catch (e) {
    debugPrint('⚠ 课前提醒撤销失败: $e');
  }
}

/// 测试提醒的固定 id。
///
/// 刻意落在本模块区间内（`classStartNotifyIdBase + 999`）→ 关开关 / 整段重排时会
/// 跟真提醒一起被清掉，不会留下一条撤不掉的常驻通知。
const int classStartTestNotifyId = classStartNotifyIdBase + 999;

/// 测试提醒：多久之后出现。
const Duration classTestReminderDelay = Duration(seconds: 5);

/// 测试提醒：出现后常驻多久（到点由系统自动撤下）。
const Duration classTestReminderLifetime = Duration(seconds: 15);

/// 排一条**测试**提醒：5 秒后出现、15 秒后由系统自动撤下。
///
/// 用途（2026-09-23）：让用户在自己手机上**当场**确认「常驻通知会出现、到点会自动
/// 消失」，不必等到某节课上课前 X 分钟。设置页「上课提醒」节的「发送测试提醒」按钮
/// 调它；内容刻意用「测试课程 / 测试教室」，避免被误认成真实课表。
Future<bool> sendTestClassReminder({
  NotificationService? service,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();
  final svc = service ?? NotificationService.instance;
  final when = at.add(classTestReminderDelay);
  const dismissAfter = classTestReminderLifetime;
  return svc.scheduleAt(
    id: classStartTestNotifyId,
    title: '即将上课 · 测试课程',
    body: '测试教室 · 第1-2节 08:00-08:45',
    when: when,
    payload: classStartReminderPayload(
      when: when,
      courseName: '测试课程',
      classroom: '测试教室',
      dismissAfter: dismissAfter,
    ),
    ongoing: true,
    autoDismissAfter: dismissAfter,
    countdown: true,
    // 2026-09-23 真机实测（华为 Mate 30 Pro / Android 12）：**必须**走精确闹钟 ——
    // 非精确（inexactAllowWhileIdle）会把 5 秒后的闹钟交给系统批处理，实测 10 秒内
    // 通知根本没出现（用户会以为功能坏了）；改精确后 12 秒时通知已在系统里、
    // 40 秒时已被 timeoutAfter 撤下。拿不到精确权限时仍自动退回非精确。
    preferExact: true,
  );
}

/// 课前提醒的排期驱动（首帧 / 回前台 / 用户在设置页改完偏好后调用）。
class ClassReminderSync {
  ClassReminderSync(this._ref);

  final Ref _ref;

  /// 按当前课表重排课前提醒（幂等）。
  ///
  /// [force] 只影响日志与「关掉开关也要真撤一次」的行为，不影响对账。
  Future<int> syncNow({bool force = false}) async {
    try {
      final store = _ref.read(classReminderPrefsStoreProvider);
      await store.ensureLoaded();
      final prefs = store.prefs;

      if (!prefs.enabled) {
        // 关掉开关：把已排的清干净（幂等，重复调用无副作用）。
        await cancelClassStartReminders();
        if (force) debugPrint('🔕 课前提醒已关闭，排期已清空');
        return 0;
      }

      // 移动端专属（用户口径）：桌面端不排常驻通知。
      if (!Platform.isAndroid) return 0;

      final account = _ref.read(currentAccountProvider);
      if (account.isEmpty) return 0;

      // 课表缓存的 key 用**学籍序号**（与实况窗 / 首页今日课程同口径）。
      final infoRepo = await _ref.read(studentInfoRepositoryProvider.future);
      StudentInfo? info;
      infoRepo.getCachedStudentInfo().fold((_) {}, (i) => info = i);
      final serial = info?.serialNo ?? '';
      if (serial.isEmpty) return 0;

      final now = DateTime.now();
      final terms = _ref.read(offlineSemesterTermsProvider);
      final term = currentSchoolTerm(now, terms: terms);
      final tw = resolveTeachingWeek(now, terms: terms);
      if (tw == null) return 0;

      // 作息表：缓存 / 内置兜底（免登录接口，离线也有表）。
      final table = await _ref
          .read(periodTableRepositoryProvider)
          .cachedOrBuiltin();
      // 课表：cache-first（不 refresh —— 回前台不该每次打教务）。
      final cacheRepo = await _ref.read(scheduleCacheRepositoryProvider.future);
      final cached = await cacheRepo.load(
        year: '${term.xn}',
        semester: '${term.xq}',
        studentId: serial,
        refresh: false,
      );
      final rTerm = RescheduleTerm('${term.xn}', '${term.xq}');
      final rStore = _ref.read(rescheduleStoreProvider);
      await rStore.ensureLoaded(rTerm);

      return syncClassStartReminders(
        entries: cached.entries,
        table: table,
        teachingWeek: tw.week,
        lead: prefs.lead,
        reschedules: rStore.recordsOf(rTerm),
      );
    } catch (e) {
      debugPrint('[classReminder] 课前提醒同步失败：$e');
      return 0;
    }
  }
}

/// 课前提醒的排期驱动（界面层用 `ref.read(classReminderSyncProvider)`）。
final classReminderSyncProvider = Provider<ClassReminderSync>(
  (ref) => ClassReminderSync(ref),
);
