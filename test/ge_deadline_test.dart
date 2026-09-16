/// 课程「截止日期」领域逻辑守卫：
/// 重复锚点滚动 / 本期完成自动失效 / 状态判定 / 文案 / 排序 / 提醒排期与对账。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/score_estimate/data/ge_deadline_reminders.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_deadline.dart';
import 'package:smarter_jxufe/features/score_estimate/domain/ge_models.dart';
import 'package:smarter_jxufe/shared/services/notification_service.dart';

/// 固定「现在」：2026-10-08 12:00。
final DateTime kNow = DateTime(2026, 10, 8, 12);

GeDeadline deadline({
  String id = 'd1',
  String title = '第 3 章习题',
  GeDeadlineKind kind = GeDeadlineKind.homework,
  required DateTime dueAt,
  GeDeadlineRepeat repeat = GeDeadlineRepeat.none,
  String note = '',
  DateTime? doneAt,
  bool remind = true,
}) => GeDeadline(
  id: id,
  title: title,
  kind: kind,
  dueAt: dueAt,
  repeat: repeat,
  note: note,
  doneAt: doneAt,
  remind: remind,
  createdAt: 0,
);

/// 记录排期的假通知服务。
class _FakeService extends NotificationService {
  final Map<int, DateTime> scheduled = {};
  final Map<int, String?> payloads = {};
  final List<String> titles = [];
  int cancelCalls = 0;
  bool acceptAll = true;

  @override
  Future<void> init() async {}

  @override
  void showGradeChanges({
    required List<String> addedNames,
    required List<String> removedNames,
  }) {}

  @override
  void showLiveClass({
    required String title,
    required String body,
    required DateTime countdownTo,
    int elapsedMinutes = 0,
    int totalMinutes = 0,
  }) {}

  @override
  void cancelLiveClass() {}

  @override
  Future<bool> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    if (!acceptAll) return false;
    scheduled[id] = when;
    payloads[id] = payload;
    titles.add(title);
    return true;
  }

  @override
  Future<void> cancelScheduled(Iterable<int> ids) async {
    cancelCalls++;
    for (final id in ids) {
      scheduled.remove(id);
      payloads.remove(id);
    }
  }

  @override
  Future<List<ScheduledNotificationInfo>> pendingScheduled() async => [
    for (final e in scheduled.entries)
      ScheduledNotificationInfo(id: e.key, payload: payloads[e.key]),
  ];
}

void main() {
  group('模型 · JSON 容错', () {
    test('往返：全部字段保留', () {
      final d = deadline(
        dueAt: DateTime(2026, 10, 8, 23, 59),
        repeat: GeDeadlineRepeat.weekly,
        note: '超星学习通',
        kind: GeDeadlineKind.onlineCourse,
        remind: false,
      );
      final back = GeDeadline.fromJson(d.toJson())!;
      expect(back, d);
      expect(back.note, '超星学习通');
      expect(back.remind, isFalse);
    });

    test('脏数据：非 Map / 缺 dueAt → null；未知枚举回落默认值', () {
      expect(GeDeadline.fromJson(null), isNull);
      expect(GeDeadline.fromJson('nope'), isNull);
      expect(GeDeadline.fromJson({'title': '没有时间'}), isNull);

      final parsed = GeDeadline.fromJson({
        'id': 'x',
        'title': 't',
        'kind': '火星类型',
        'repeat': '每三天',
        'dueAt': '2026-10-08T23:59:00.000',
        'remind': 'yes', // 非 bool → 默认 true
      })!;
      expect(parsed.kind, GeDeadlineKind.homework);
      expect(parsed.repeat, GeDeadlineRepeat.none);
      expect(parsed.remind, isTrue);
    });

    test('列表容错：跳过脏项，保留能解析的', () {
      final list = geDeadlinesFromJson([
        {'id': 'a', 'title': 'A', 'dueAt': '2026-10-08T23:59:00.000'},
        'garbage',
        {'title': '无时间'},
        {'id': 'b', 'title': 'B', 'dueAt': 1791503940000},
      ]);
      expect(list.map((e) => e.id), ['a', 'b']);
    });

    test('课程 JSON 里没有 deadlines 字段 → 空列表（旧数据兼容）', () {
      final course = GeCourse.fromJson({'id': 'c', 'name': '高数'});
      expect(course.deadlines, isEmpty);
    });
  });

  group('重复规则 · 锚点滚动', () {
    test('每周：锚点在过去 → 下一个未来时刻（严格晚于 now）', () {
      final d = deadline(
        dueAt: DateTime(2026, 9, 17, 23, 59),
        repeat: GeDeadlineRepeat.weekly,
      );
      // 09-17 → 09-24 → 10-01 → 10-08（12:00 时 10-08 23:59 尚未到）
      expect(geDeadlineEffectiveDue(d, kNow), DateTime(2026, 10, 8, 23, 59));
    });

    test('每两周：按 14 天滚动', () {
      final d = deadline(
        dueAt: DateTime(2026, 9, 10, 23, 59),
        repeat: GeDeadlineRepeat.biweekly,
      );
      expect(geDeadlineEffectiveDue(d, kNow), DateTime(2026, 10, 8, 23, 59));
    });

    test('锚点在未来 → 就是锚点；恰好等于 now → 滚到下一期', () {
      final future = deadline(
        dueAt: DateTime(2026, 10, 20, 23, 59),
        repeat: GeDeadlineRepeat.weekly,
      );
      expect(geDeadlineEffectiveDue(future, kNow), DateTime(2026, 10, 20, 23, 59));

      final exact = deadline(dueAt: kNow, repeat: GeDeadlineRepeat.weekly);
      expect(
        geDeadlineEffectiveDue(exact, kNow),
        DateTime(2026, 10, 15, 12),
        reason: '不能停在 now 上（严格晚于）',
      );
    });

    test('occurrence(i) 依次递增；单次条目恒为自身', () {
      final weekly = deadline(
        dueAt: DateTime(2026, 10, 8, 23, 59),
        repeat: GeDeadlineRepeat.weekly,
      );
      expect(geDeadlineOccurrence(weekly, kNow, 0), DateTime(2026, 10, 8, 23, 59));
      expect(geDeadlineOccurrence(weekly, kNow, 1), DateTime(2026, 10, 15, 23, 59));
      expect(geDeadlineOccurrence(weekly, kNow, 3), DateTime(2026, 10, 29, 23, 59));

      final once = deadline(dueAt: DateTime(2026, 10, 1));
      expect(geDeadlineOccurrence(once, kNow, 5), DateTime(2026, 10, 1));
    });

    test('很久以前的锚点：跳过错过的周期（不能一次算一年）', () {
      final d = deadline(
        dueAt: DateTime(2025, 1, 1, 23, 59),
        repeat: GeDeadlineRepeat.weekly,
      );
      final next = geDeadlineEffectiveDue(d, kNow);
      expect(next.isAfter(kNow), isTrue);
      expect(next.difference(kNow).inDays, lessThanOrEqualTo(7));
    });
  });

  group('本期完成 · 自动失效', () {
    test('重复条目：完成于本期 → 已完成；滚到下一期自动变未完成', () {
      final due = DateTime(2026, 10, 8, 23, 59);
      final d = deadline(
        dueAt: due,
        repeat: GeDeadlineRepeat.weekly,
        doneAt: DateTime(2026, 10, 7, 20),
      );
      expect(geDeadlineDoneNow(d, kNow), isTrue);
      // 到了下一期（10-08 23:59 之后）
      final later = DateTime(2026, 10, 9, 8);
      expect(geDeadlineDoneNow(d, later), isFalse);
      expect(geDeadlineStatus(d, later), GeDeadlineStatus.upcoming);
    });

    test('重复条目：完成于**上一期** → 本期仍未完成', () {
      final d = deadline(
        dueAt: DateTime(2026, 10, 8, 23, 59),
        repeat: GeDeadlineRepeat.weekly,
        // 本期起点 = 下一次截止 − 7 天 = 10-01 23:59；10-01 12:00 落在上一期。
        doneAt: DateTime(2026, 10, 1, 12),
      );
      expect(geDeadlineDoneNow(d, kNow), isFalse);
    });

    test('单次条目：doneAt 非空即永久完成', () {
      final d = deadline(
        dueAt: DateTime(2026, 10, 1),
        doneAt: DateTime(2026, 10, 2),
      );
      expect(geDeadlineDoneNow(d, kNow), isTrue);
      expect(geDeadlineStatus(d, kNow), GeDeadlineStatus.done);
    });
  });

  group('状态与文案', () {
    test('单次：过期 / 今天 / 3 天内 / 更远', () {
      expect(
        geDeadlineStatus(deadline(dueAt: DateTime(2026, 10, 1)), kNow),
        GeDeadlineStatus.overdue,
      );
      expect(
        geDeadlineStatus(deadline(dueAt: DateTime(2026, 10, 8, 23, 59)), kNow),
        GeDeadlineStatus.today,
      );
      expect(
        geDeadlineStatus(deadline(dueAt: DateTime(2026, 10, 10, 9)), kNow),
        GeDeadlineStatus.soon,
      );
      expect(
        geDeadlineStatus(deadline(dueAt: DateTime(2026, 10, 30, 9)), kNow),
        GeDeadlineStatus.upcoming,
      );
    });

    test('倒计时文案', () {
      expect(
        geDeadlineCountdownText(
          deadline(dueAt: DateTime(2026, 10, 8, 23, 59)),
          kNow,
        ),
        '今天 23:59 截止',
      );
      expect(
        geDeadlineCountdownText(
          deadline(dueAt: DateTime(2026, 10, 10, 15)),
          kNow,
        ),
        '还剩 2 天 3 小时',
      );
      expect(
        geDeadlineCountdownText(deadline(dueAt: DateTime(2026, 10, 6)), kNow),
        '已过期 2 天 12 小时',
      );
      expect(
        geDeadlineCountdownText(
          deadline(dueAt: DateTime(2026, 10, 8, 13, 30)),
          kNow,
        ),
        '今天 13:30 截止',
      );
      expect(
        geDeadlineCountdownText(
          deadline(dueAt: DateTime(2026, 10, 1), doneAt: DateTime(2026, 9, 30)),
          kNow,
        ),
        '已完成',
      );
      expect(
        geDeadlineCountdownText(
          deadline(
            dueAt: DateTime(2026, 9, 17, 23, 59),
            repeat: GeDeadlineRepeat.weekly,
            doneAt: DateTime(2026, 10, 8, 9),
          ),
          kNow,
        ),
        '本期已完成',
      );
    });

    test('时刻 / 日期文案：同年省略年份', () {
      expect(geDeadlineDueText(DateTime(2026, 10, 8, 23, 59), kNow), '10-08 23:59');
      expect(
        geDeadlineDueText(DateTime(2027, 1, 5, 9, 5), kNow),
        '2027-01-05 09:05',
      );
      expect(
        geDeadlineRepeatText(
          deadline(
            dueAt: DateTime(2026, 10, 1, 23, 59),
            repeat: GeDeadlineRepeat.weekly,
          ),
          kNow,
        ),
        '每周 · 下次 10-08 23:59',
      );
    });

    test('剩余时长的边界：不到 1 分钟 / 只有分钟 / 只有小时', () {
      expect(geDeadlineRemainingText(const Duration(seconds: 30)), '还剩 不到 1 分钟');
      expect(geDeadlineRemainingText(const Duration(minutes: 25)), '还剩 25 分钟');
      expect(geDeadlineRemainingText(const Duration(hours: 3)), '还剩 3 小时');
      expect(
        geDeadlineRemainingText(const Duration(hours: 3, minutes: 20)),
        '还剩 3 小时 20 分',
      );
      expect(geDeadlineRemainingText(const Duration(days: 3)), '还剩 3 天');
      expect(geDeadlineRemainingText(-const Duration(minutes: 5)), '已过期 5 分钟');
    });
  });

  group('排序', () {
    test('未完成在前（按截止升序），已完成 / 已过期沉底', () {
      final items = [
        deadline(id: 'late', dueAt: DateTime(2026, 10, 20)),
        deadline(id: 'overdue', dueAt: DateTime(2026, 10, 1)),
        deadline(id: 'soon', dueAt: DateTime(2026, 10, 9)),
        deadline(
          id: 'done',
          dueAt: DateTime(2026, 10, 30),
          doneAt: DateTime(2026, 10, 7),
        ),
      ];
      expect(
        geSortedDeadlines(items, kNow).map((e) => e.id),
        ['soon', 'late', 'overdue', 'done'],
      );
    });
  });

  group('提醒 · 内容与提前量', () {
    test('提前量文案', () {
      expect(geDeadlineLeadLabel(const Duration(days: 1)), '提前 1 天');
      expect(geDeadlineLeadLabel(const Duration(hours: 1)), '提前 1 小时');
      expect(geDeadlineLeadLabel(const Duration(minutes: 30)), '提前 30 分钟');
      expect(geDeadlineLeadShort(const Duration(days: 1)), '明天');
      expect(geDeadlineLeadShort(const Duration(days: 2)), '2 天后');
      expect(geDeadlineLeadShort(const Duration(hours: 1)), '1 小时后');
      expect(geDeadlineLeadShort(const Duration(minutes: 30)), '30 分钟后');
    });

    test('通知标题与正文', () {
      final d = deadline(
        kind: GeDeadlineKind.onlineCourse,
        dueAt: DateTime(2026, 10, 9, 23, 59),
        repeat: GeDeadlineRepeat.weekly,
      );
      expect(geDeadlineNotifyTitle(d, const Duration(days: 1)), '网课明天截止');
      expect(
        geDeadlineNotifyBody(
          courseName: '高等数学（上）',
          d: d,
          due: DateTime(2026, 10, 9, 23, 59),
          now: kNow,
        ),
        '每周 · 高等数学（上） · 第 3 章习题 · 10-09 23:59 截止',
      );
      final once = deadline(dueAt: DateTime(2026, 10, 9, 23, 59));
      expect(
        geDeadlineNotifyBody(
          courseName: '高等数学（上）',
          d: once,
          due: once.dueAt,
          now: kNow,
        ),
        '高等数学（上） · 第 3 章习题 · 10-09 23:59 截止',
      );
    });

    test('排期集合：默认 1 天 + 1 小时；跳过已完成 / 关提醒 / 已过去的时刻', () {
      final courses = [
        GeCourse(
          id: 'c1',
          name: '高数',
          deadlines: [
            deadline(id: 'a', dueAt: DateTime(2026, 10, 10, 23, 59)),
            deadline(
              id: 'b',
              dueAt: DateTime(2026, 10, 11, 23, 59),
              doneAt: DateTime(2026, 10, 7),
            ),
            deadline(
              id: 'c',
              dueAt: DateTime(2026, 10, 12, 23, 59),
              remind: false,
            ),
            // 已过期单次：只剩「过期前」的提醒时刻，全部在过去 → 不排
            deadline(id: 'd', dueAt: DateTime(2026, 10, 2)),
          ],
        ),
      ];
      final reminders = geDeadlineRemindersFor(courses: courses, now: kNow);
      expect(reminders.length, 2, reason: '只有 a 的两条');
      expect(reminders.every((r) => r.deadlineId == 'a'), isTrue);
      // 按触发时刻升序：提前 1 天（10-09 23:59）在前，提前 1 小时（10-10 22:59）在后
      expect(reminders[0].when, DateTime(2026, 10, 9, 23, 59));
      expect(reminders[1].when, DateTime(2026, 10, 10, 22, 59));
      expect(reminders[0].id, geDeadlineNotifyIdBase);
      expect(reminders[1].id, geDeadlineNotifyIdBase + 1);
      expect(geDeadlineIdInRange(reminders[0].id), isTrue);
      expect(geDeadlineIdInRange(12345), isFalse);
    });

    test('重复条目：预排 horizon 次（每次 2 条），且全部在未来', () {
      final courses = [
        GeCourse(
          id: 'c1',
          name: '高数',
          deadlines: [
            deadline(
              id: 'w',
              dueAt: DateTime(2026, 9, 17, 23, 59),
              repeat: GeDeadlineRepeat.weekly,
            ),
          ],
        ),
      ];
      final reminders = geDeadlineRemindersFor(
        courses: courses,
        now: kNow,
        horizon: 4,
      );
      // 4 期 × 2 条 = 8，但第一期的「提前 1 天」（10-07 23:59）已经过去 → 只剩 7 条。
      expect(reminders.length, 7);
      expect(reminders.every((r) => r.when.isAfter(kNow)), isTrue);
      final days = reminders.map((r) => r.when.day).toSet();
      expect(days, {8, 14, 15, 21, 22, 28, 29});
    });

    test('数量上限：单次最多 geDeadlineMaxScheduled 条', () {
      final courses = [
        GeCourse(
          id: 'c1',
          name: '高数',
          deadlines: [
            for (var i = 0; i < 200; i++)
              deadline(id: 'x$i', dueAt: DateTime(2026, 10, 20).add(Duration(days: i))),
          ],
        ),
      ];
      final reminders = geDeadlineRemindersFor(courses: courses, now: kNow);
      expect(reminders.length, geDeadlineMaxScheduled);
      expect(reminders.last.id, geDeadlineNotifyIdBase + geDeadlineMaxScheduled - 1);
    });
  });

  group('提醒 · 排期同步（幂等 / 对账 / 撤销）', () {
    test('首次同步：写入系统排期', () async {
      final svc = _FakeService();
      final courses = [
        GeCourse(
          id: 'c1',
          name: '高数',
          deadlines: [deadline(id: 'a', dueAt: DateTime(2026, 10, 10, 23, 59))],
        ),
      ];
      final n = await syncGeDeadlineReminders(
        courses: courses,
        service: svc,
        now: kNow,
      );
      expect(n, 2);
      expect(svc.scheduled.length, 2);
      expect(svc.cancelCalls, 0);
      expect(svc.payloads.values.first, isNotNull);
    });

    test('数据未变：不撤销、不重排（避免每次回前台扰动系统闹钟）', () async {
      final svc = _FakeService();
      final courses = [
        GeCourse(
          id: 'c1',
          name: '高数',
          deadlines: [deadline(id: 'a', dueAt: DateTime(2026, 10, 10, 23, 59))],
        ),
      ];
      await syncGeDeadlineReminders(courses: courses, service: svc, now: kNow);
      final before = Map<int, DateTime>.from(svc.scheduled);
      await syncGeDeadlineReminders(courses: courses, service: svc, now: kNow);
      expect(svc.cancelCalls, 0);
      expect(svc.scheduled, before);
    });

    test('数据变了：先撤本区间排期再重排（区间外的通知不动）', () async {
      final svc = _FakeService();
      // 假装系统里已有一条**别的模块**的排期（区间外），以及一条本模块的旧排期。
      svc.scheduled[4242] = DateTime(2026, 10, 9);
      svc.payloads[4242] = 'x';
      svc.scheduled[geDeadlineNotifyIdBase] = DateTime(2026, 10, 5);
      svc.payloads[geDeadlineNotifyIdBase] = 'stale';

      final courses = [
        GeCourse(
          id: 'c1',
          name: '高数',
          deadlines: [deadline(id: 'a', dueAt: DateTime(2026, 10, 10, 23, 59))],
        ),
      ];
      await syncGeDeadlineReminders(courses: courses, service: svc, now: kNow);
      expect(svc.cancelCalls, 1);
      expect(svc.scheduled.containsKey(4242), isTrue, reason: '区间外的不该被动');
      expect(svc.scheduled[geDeadlineNotifyIdBase], DateTime(2026, 10, 9, 23, 59));
      expect(svc.payloads[geDeadlineNotifyIdBase], isNotNull);
    });

    test('删掉全部条目：撤销本区间排期且不再排', () async {
      final svc = _FakeService();
      svc.scheduled[geDeadlineNotifyIdBase] = DateTime(2026, 10, 9);
      svc.payloads[geDeadlineNotifyIdBase] = 'x';
      final n = await syncGeDeadlineReminders(
        courses: const [],
        service: svc,
        now: kNow,
      );
      expect(n, 0);
      expect(svc.scheduled, isEmpty);
    });

    test('排期失败不抛异常（服务未就绪 / 平台不支持）', () async {
      final svc = _FakeService()..acceptAll = false;
      final courses = [
        GeCourse(
          id: 'c1',
          name: '高数',
          deadlines: [deadline(id: 'a', dueAt: DateTime(2026, 10, 10, 23, 59))],
        ),
      ];
      final n = await syncGeDeadlineReminders(
        courses: courses,
        service: svc,
        now: kNow,
      );
      expect(n, 0);
    });

    test('对账判定：完全一致 → true；缺一条 / 时刻不同 → false', () {
      final courses = [
        GeCourse(
          id: 'c1',
          name: '高数',
          deadlines: [deadline(id: 'a', dueAt: DateTime(2026, 10, 10, 23, 59))],
        ),
      ];
      final desired = geDeadlineRemindersFor(courses: courses, now: kNow);
      final ok = [
        for (final r in desired)
          ScheduledNotificationInfo(
            id: r.id,
            payload: '${r.when.millisecondsSinceEpoch}',
          ),
      ];
      expect(geDeadlineScheduleMatches(desired: desired, pending: ok), isTrue);
      expect(
        geDeadlineScheduleMatches(desired: desired, pending: [ok.first]),
        isFalse,
      );
      expect(
        geDeadlineScheduleMatches(
          desired: desired,
          pending: [
            ScheduledNotificationInfo(id: ok.first.id, payload: '1'),
            ok.last,
          ],
        ),
        isFalse,
      );
      // 区间外的排期不参与对账
      expect(
        geDeadlineScheduleMatches(
          desired: desired,
          pending: [...ok, const ScheduledNotificationInfo(id: 4242)],
        ),
        isTrue,
      );
    });
  });
}
