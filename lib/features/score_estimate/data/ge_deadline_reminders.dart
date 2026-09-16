/// 分数估计 · 截止日期提醒（系统本地通知排期）。
///
/// 口径（2026-09-15 立，改动前先读）：
/// - 每条截止日期按 [geDeadlineDefaultLeads] 排 **提前 1 天 + 提前 1 小时** 两条；
/// - 重复条目（每周 / 每两周）**预排未来 [geDeadlineScheduleHorizon] 次**（每次 2 条，
///   约覆盖一个月）；之后每次 App 回前台 / 数据变动都会**整段重排**；
/// - 重排 = 先撤掉本模块 id 区间里的全部排期，再按需重排（**不需要额外记账**）；
///   已排内容与期望完全一致时直接跳过（避免每次回前台都扰动系统闹钟）；
/// - 已经过去的提醒时刻**不排**：Windows 插件对过去时刻直接抛
///   `ArgumentError: cannot schedule notifications in the past`，Android 会立刻弹出；
/// - 通知 id = [geDeadlineNotifyIdBase] + 序号（按 触发时刻 / deadlineId / 提前量 稳定排序），
///   上限 [geDeadlineMaxScheduled] 条。
library;

import 'package:flutter/foundation.dart';

import 'package:smarter_jxufe/shared/services/notification_service.dart';

import '../domain/ge_deadline.dart';
import '../domain/ge_models.dart';

/// 通知 id 区间起点（实况窗固定 8801；成绩通知用时间戳，不冲突）。
const int geDeadlineNotifyIdBase = 920000;

/// id 区间长度（同时也是单次最多排期条数）。
const int geDeadlineNotifyIdSpan = 2000;

/// 单次最多排期条数（避免条目过多时刷爆系统闹钟）。
const int geDeadlineMaxScheduled = 120;

/// 触发时刻至少要晚于「现在」这么久，否则不排（防止一进 App 就弹一串）。
const Duration geDeadlineNotifyMinLead = Duration(minutes: 1);

/// 一条待排的提醒（纯数据，便于测试）。
@immutable
class GeDeadlineReminder {
  const GeDeadlineReminder({
    required this.id,
    required this.deadlineId,
    required this.title,
    required this.body,
    required this.when,
  });

  /// 系统通知 id。
  final int id;

  /// 来源截止日期 id。
  final String deadlineId;

  /// 通知标题。
  final String title;

  /// 通知正文。
  final String body;

  /// 触发时刻（绝对时刻）。
  final DateTime when;

  @override
  bool operator ==(Object other) =>
      other is GeDeadlineReminder &&
      other.id == id &&
      other.deadlineId == deadlineId &&
      other.title == title &&
      other.body == body &&
      other.when == when;

  @override
  int get hashCode => Object.hash(id, deadlineId, title, body, when);

  @override
  String toString() => 'GeDeadlineReminder(#$id $when $title — $body)';
}

/// id 是否落在本模块区间内。
bool geDeadlineIdInRange(int id) =>
    id >= geDeadlineNotifyIdBase && id < geDeadlineNotifyIdBase + geDeadlineNotifyIdSpan;

/// 提前量文案：「提前 1 天」「提前 1 小时」「提前 30 分钟」。
String geDeadlineLeadLabel(Duration lead) {
  final d = lead.inDays;
  if (d > 0 && lead.inHours % 24 == 0) return '提前 $d 天';
  final h = lead.inHours;
  if (h > 0 && lead.inMinutes % 60 == 0) return '提前 $h 小时';
  return '提前 ${lead.inMinutes} 分钟';
}

/// 提前量的口语化说法：「明天」「1 小时后」「30 分钟后」。
String geDeadlineLeadShort(Duration lead) {
  final d = lead.inDays;
  if (d > 0 && lead.inHours % 24 == 0) return d == 1 ? '明天' : '$d 天后';
  final h = lead.inHours;
  if (h > 0 && lead.inMinutes % 60 == 0) return '$h 小时后';
  final m = lead.inMinutes;
  return m > 0 ? '$m 分钟后' : '即将';
}

/// 通知标题：「作业明天截止」「网课 1 小时后截止」。
String geDeadlineNotifyTitle(GeDeadline d, Duration lead) =>
    '${d.kind.label}${geDeadlineLeadShort(lead)}截止';

/// 通知正文：「每周 · 高等数学（上） · 第 3 章习题 · 10-08 23:59 截止」。
String geDeadlineNotifyBody({
  required String courseName,
  required GeDeadline d,
  required DateTime due,
  required DateTime now,
}) {
  final repeat = d.isRepeating ? '${d.repeat.label} · ' : '';
  final course = courseName.trim().isEmpty ? '' : '${courseName.trim()} · ';
  return '$repeat$course${d.displayTitle} · ${geDeadlineDueText(due, now)} 截止';
}

/// 收集所有课程的待排提醒（纯函数；[now] 注入便于测试）。
///
/// 只收「开了提醒」「未完成本期」的条目；每条按 [horizon] 次截止 × [leads] 个提前量展开。
List<GeDeadlineReminder> geDeadlineRemindersFor({
  required Iterable<GeCourse> courses,
  required DateTime now,
  List<Duration> leads = geDeadlineDefaultLeads,
  int horizon = geDeadlineScheduleHorizon,
  Duration minLead = geDeadlineNotifyMinLead,
}) {
  final drafts = <({String deadlineId, Duration lead, String title, String body, DateTime when})>[];
  final earliest = now.add(minLead);
  for (final course in courses) {
    for (final d in course.deadlines) {
      if (!d.remind) continue;
      if (geDeadlineDoneNow(d, now)) continue;
      // ⚠ 只有**重复**条目才展开 horizon 次：单次条目的 occurrence(i) 恒为同一个
      //   截止时刻，展开会把同一条提醒重复排 N 遍（曾实测排成 8 条而不是 2 条）。
      final times = d.isRepeating ? (horizon < 1 ? 1 : horizon) : 1;
      for (var i = 0; i < times; i++) {
        final due = geDeadlineOccurrence(d, now, i);
        for (final lead in leads) {
          final when = due.subtract(lead);
          if (!when.isAfter(earliest)) continue;
          drafts.add((
            deadlineId: d.id,
            lead: lead,
            title: geDeadlineNotifyTitle(d, lead),
            body: geDeadlineNotifyBody(
              courseName: course.name,
              d: d,
              due: due,
              now: now,
            ),
            when: when,
          ));
        }
      }
    }
  }
  drafts.sort((a, b) {
    final byWhen = a.when.compareTo(b.when);
    if (byWhen != 0) return byWhen;
    final byId = a.deadlineId.compareTo(b.deadlineId);
    if (byId != 0) return byId;
    return b.lead.compareTo(a.lead);
  });
  final out = <GeDeadlineReminder>[];
  for (var i = 0; i < drafts.length && i < geDeadlineMaxScheduled; i++) {
    final d = drafts[i];
    out.add(
      GeDeadlineReminder(
        id: geDeadlineNotifyIdBase + i,
        deadlineId: d.deadlineId,
        title: d.title,
        body: d.body,
        when: d.when,
      ),
    );
  }
  return out;
}

/// 期望排期与系统现有排期是否一致（用 payload 里的 epoch 毫秒对账）。
bool geDeadlineScheduleMatches({
  required List<GeDeadlineReminder> desired,
  required List<ScheduledNotificationInfo> pending,
}) {
  final current = <int, String>{};
  for (final p in pending) {
    if (!geDeadlineIdInRange(p.id)) continue;
    current[p.id] = p.payload ?? '';
  }
  if (current.length != desired.length) return false;
  for (final r in desired) {
    if (current[r.id] != '${r.when.millisecondsSinceEpoch}') return false;
  }
  return true;
}

/// 把系统排期对齐到 [courses]（幂等）。
///
/// 返回真正排上的条数；任何异常都吞掉并返回 0（提醒失败不能影响页面）。
Future<int> syncGeDeadlineReminders({
  required Iterable<GeCourse> courses,
  NotificationService? service,
  DateTime? now,
  List<Duration> leads = geDeadlineDefaultLeads,
  int horizon = geDeadlineScheduleHorizon,
}) async {
  final at = now ?? DateTime.now();
  final svc = service ?? NotificationService.instance;
  try {
    final desired = geDeadlineRemindersFor(
      courses: courses,
      now: at,
      leads: leads,
      horizon: horizon,
    );
    final pending = await svc.pendingScheduled();
    if (geDeadlineScheduleMatches(desired: desired, pending: pending)) {
      return desired.length;
    }
    final stale = [
      for (final p in pending)
        if (geDeadlineIdInRange(p.id)) p.id,
    ];
    if (stale.isNotEmpty) await svc.cancelScheduled(stale);
    var ok = 0;
    for (final r in desired) {
      final done = await svc.scheduleAt(
        id: r.id,
        title: r.title,
        body: r.body,
        when: r.when,
        payload: '${r.when.millisecondsSinceEpoch}',
      );
      if (done) ok++;
    }
    if (desired.isNotEmpty) {
      debugPrint('🔔 截止提醒已排期 $ok/${desired.length} 条');
    }
    return ok;
  } catch (e) {
    debugPrint('⚠ 截止提醒排期失败: $e');
    return 0;
  }
}
