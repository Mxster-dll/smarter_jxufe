/// 课前提醒（上课前 X 分钟起的常驻通知）——领域口径 + 排期同步的守卫测试。
///
/// 用户 2026-09-22 原话：「我希望在任何一节课上课前x分钟(x可设置，默认30）到上课前，
/// 移动端显示一个常驻通知，下节课的名称和教室」。
///
/// 覆盖：教学周跨天推进（周一对齐）、提前量夹紧与文案、提醒列表（窗口夹紧 / 停课 /
/// 已开始 / 单双周跨周 / 上限 / 去重）、payload 对账、幂等重排与撤销。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/class_start_reminder.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/class_reminder_sync.dart';
import 'package:smarter_jxufe/shared/services/notification_service.dart';

// ─── 构造工具（照 `reschedule_engine_test.dart` / `live_session_test.dart` 的口径）───

/// 2026-09-14 是周一，属第 2 教学周（261 第 1 周自 09-07 起）。
final DateTime _monday = DateTime(2026, 9, 14);

ClassTime _ct({
  DayOfWeek day = DayOfWeek.monday,
  int startPeriod = 1,
  int endPeriod = 2,
  String classroom = '麦三教3407',
  String? campus = '麦庐园校区',
  int startWeek = 1,
  int endWeek = 16,
  WeekParity parity = WeekParity.every,
}) => ClassTime(
  startWeek: startWeek,
  endWeek: endWeek,
  weekParity: parity,
  dayOfWeek: day,
  startPeriod: startPeriod,
  endPeriod: endPeriod,
  classroom: classroom,
  campus: campus,
);

ScheduleEntry _entry({
  String courseCode = 'C1',
  String courseName = '高等数学',
  String classCode = '001-01',
  required List<ClassTime> classTimes,
}) => ScheduleEntry(
  classCode: classCode,
  className: '主干+',
  courseCode: courseCode,
  courseName: courseName,
  totalHours: 48,
  credits: 3,
  studyNature: '初修',
  teacherCode: 'T1',
  teacherName: '张三',
  selectionStatus: '选中',
  isCrossMajor: false,
  hasTextbook: true,
  classTimes: classTimes,
);

Reschedule _cancelRecord({
  String courseCode = 'C1',
  String courseName = '高等数学',
  String classCode = '001-01',
  int week = 2,
  DayOfWeek day = DayOfWeek.monday,
  int startPeriod = 1,
  int endPeriod = 2,
}) => Reschedule(
  id: 'r1',
  kind: RescheduleKind.cancel,
  scope: RescheduleScope.once,
  week: week,
  courseCode: courseCode,
  courseName: courseName,
  classCode: classCode,
  originTeacher: '张三',
  originDay: day,
  originStartPeriod: startPeriod,
  originEndPeriod: endPeriod,
  originClassroom: '麦三教3407',
  targetDay: null,
  targetStartPeriod: null,
  targetEndPeriod: null,
  targetClassroom: '',
  newTeacher: null,
  note: '',
  createdAt: DateTime(2026, 9, 10),
  updatedAt: DateTime(2026, 9, 10),
);

/// 当天的第 [start]–[end] 节的开始时刻（从作息表推，避免把时间写死在测试里）。
DateTime _periodStart(DateTime day, int start) =>
    PeriodTable.builtin.span(day, start, start).start!;

/// 记录调用参数的假通知服务。
class _FakeService extends NotificationService {
  _FakeService({List<ScheduledNotificationInfo> pending = const []})
    : _pending = [...pending];

  final List<ScheduledNotificationInfo> _pending;

  final List<
    ({
      int id,
      String title,
      String body,
      DateTime when,
      String? payload,
      bool ongoing,
      Duration? autoDismissAfter,
      bool countdown,
      bool preferExact,
    })
  >
  scheduled = [];

  final List<List<int>> cancelled = [];

  int pendingCalls = 0;

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
    bool ongoing = false,
    Duration? autoDismissAfter,
    bool countdown = false,
    bool preferExact = false,
  }) async {
    scheduled.add((
      id: id,
      title: title,
      body: body,
      when: when,
      payload: payload,
      ongoing: ongoing,
      autoDismissAfter: autoDismissAfter,
      countdown: countdown,
      preferExact: preferExact,
    ));
    _pending.add(ScheduledNotificationInfo(id: id, payload: payload));
    return true;
  }

  @override
  Future<void> cancelScheduled(Iterable<int> ids) async {
    final list = ids.toList();
    cancelled.add(list);
    _pending.removeWhere((p) => list.contains(p.id));
  }

  @override
  Future<List<ScheduledNotificationInfo>> pendingScheduled() async {
    pendingCalls++;
    return List.of(_pending);
  }
}

void main() {
  const lead30 = Duration(minutes: 30);

  group('教学周跨天推进（周一对齐）', () {
    test('同一周内的任意一天都是同一教学周', () {
      final sunday = DateTime(2026, 9, 20);
      expect(
        teachingWeekOfDay(now: _monday, teachingWeek: 2, day: _monday),
        2,
      );
      expect(teachingWeekOfDay(now: _monday, teachingWeek: 2, day: sunday), 2);
    });

    test('下周一 = 下一教学周', () {
      final nextMonday = DateTime(2026, 9, 21);
      expect(
        teachingWeekOfDay(now: _monday, teachingWeek: 2, day: nextMonday),
        3,
      );
    });

    test('周日晚上看「明天（周一）」也要 +1（不能按天数 ~/7 分桶）', () {
      final sunday = DateTime(2026, 9, 20);
      final nextMonday = DateTime(2026, 9, 21);
      // 相差 1 天：`1 ~/ 7 == 0` 会算成同一周 → 周日晚上看下周一的课会取错周次。
      expect(
        teachingWeekOfDay(now: sunday, teachingWeek: 2, day: nextMonday),
        3,
      );
    });
  });

  group('提前量口径', () {
    test('夹进 1–120 分钟', () {
      expect(clampClassReminderLead(0), classReminderMinLeadMinutes);
      expect(clampClassReminderLead(-5), classReminderMinLeadMinutes);
      expect(clampClassReminderLead(30), 30);
      expect(clampClassReminderLead(999), classReminderMaxLeadMinutes);
    });

    test('文案：分钟 / 整小时', () {
      expect(classReminderLeadLabel(30), '提前 30 分钟');
      expect(classReminderLeadLabel(5), '提前 5 分钟');
      expect(classReminderLeadLabel(60), '提前 1 小时');
      expect(classReminderLeadLabel(90), '提前 90 分钟');
    });

    test('默认 30 分钟、可选值里有 30', () {
      expect(classReminderDefaultLeadMinutes, 30);
      expect(classReminderLeadOptions, contains(30));
      expect(classReminderLeadOptions, orderedEquals(<int>[5, 10, 15, 20, 30, 45, 60]));
    });

    test('id 区间不与实况窗 / 截止提醒重叠', () {
      expect(classStartIdInRange(classStartNotifyIdBase), isTrue);
      expect(classStartIdInRange(classStartNotifyIdBase + 999), isTrue);
      expect(classStartIdInRange(classStartNotifyIdBase - 1), isFalse);
      expect(classStartIdInRange(8801), isFalse);
      expect(classStartIdInRange(920001), isFalse);
    });
  });

  group('课前提醒列表', () {
    test('一节今天上午的课 → 触发时刻 = 上课前 30 分钟，常驻 30 分钟', () {
      final now = DateTime(2026, 9, 14, 7, 0);
      final list = classStartRemindersFor(
        entries: [_entry(classTimes: [_ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        now: now,
        lead: lead30,
      );
      expect(list, hasLength(1));
      final r = list.single;
      final start = _periodStart(_monday, 1);
      expect(r.id, classStartNotifyIdBase);
      expect(r.startAt, start);
      expect(r.when, start.subtract(lead30));
      expect(r.dismissAfter, lead30);
      expect(r.title, '即将上课 · 高等数学');
      expect(r.body, contains('麦三教3407'));
      expect(r.body, contains('第1-2节'));
      expect(r.lead, lead30);
    });

    test('已进入窗口（还差 10 分钟上课）→ 夹到此刻，常驻到上课那一刻', () {
      final start = _periodStart(_monday, 1);
      final now = start.subtract(const Duration(minutes: 10));
      final list = classStartRemindersFor(
        entries: [_entry(classTimes: [_ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        now: now,
        lead: lead30,
      );
      expect(list, hasLength(1));
      final r = list.single;
      expect(r.when, now.add(classReminderMinLead));
      expect(
        r.dismissAfter,
        start.difference(now.add(classReminderMinLead)),
        reason: '常驻到上课那一刻（不是 30 分钟）',
      );
    });

    test('已经开始的课不排', () {
      final start = _periodStart(_monday, 1);
      final list = classStartRemindersFor(
        entries: [_entry(classTimes: [_ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        now: start.add(const Duration(minutes: 1)),
        lead: lead30,
        days: 1,
      );
      expect(list, isEmpty);
    });

    test('停课的日程不排（与实况窗「下一节」同口径）', () {
      final now = DateTime(2026, 9, 14, 7, 0);
      final list = classStartRemindersFor(
        entries: [_entry(classTimes: [_ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        now: now,
        lead: lead30,
        reschedules: [_cancelRecord()],
      );
      expect(list, isEmpty);
    });

    test('单周课在双周不排、跨到下一周（单周）才排 —— 教学周确实 +1', () {
      final now = _monday.add(const Duration(hours: 7)); // 第 2 周周一 07:00
      final nextMonday = DateTime(2026, 9, 21);
      final list = classStartRemindersFor(
        entries: [
          _entry(classTimes: [_ct(parity: WeekParity.odd, startWeek: 1, endWeek: 16)]),
        ],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        now: now,
        lead: lead30,
        days: 8, // 覆盖到下一周周一（09-21，第 3 周 = 单周）
      );
      expect(list, hasLength(1));
      expect(list.single.startAt, _periodStart(nextMonday, 1));
    });

    test('同一天两门课 → 两条提醒、id 连续、按触发时刻排序', () {
      final now = DateTime(2026, 9, 14, 7, 0);
      final list = classStartRemindersFor(
        entries: [
          _entry(
            courseCode: 'C2',
            courseName: '大学英语',
            classCode: '002-01',
            classTimes: [_ct(startPeriod: 3, endPeriod: 4, classroom: '麦三教3501')],
          ),
          _entry(classTimes: [_ct()]),
        ],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        now: now,
        lead: lead30,
      );
      expect(list, hasLength(2));
      expect(list[0].courseName, '高等数学');
      expect(list[0].id, classStartNotifyIdBase);
      expect(list[1].courseName, '大学英语');
      expect(list[1].id, classStartNotifyIdBase + 1);
      expect(list[0].when.isBefore(list[1].when), isTrue);
    });

    test('同一节课被解析成两条（重叠时段）只排一条', () {
      final now = DateTime(2026, 9, 14, 7, 0);
      final list = classStartRemindersFor(
        entries: [
          _entry(classTimes: [_ct(), _ct()]),
        ],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        now: now,
        lead: lead30,
      );
      expect(list, hasLength(1));
    });

    test('上限：max 截断（不会把系统闹钟排爆）', () {
      final now = DateTime(2026, 9, 14, 7, 0);
      final list = classStartRemindersFor(
        entries: [
          for (var i = 0; i < 5; i++)
            _entry(
              courseCode: 'C$i',
              courseName: '课程$i',
              classCode: '00$i-01',
              classTimes: [_ct(startPeriod: 1 + i * 2, endPeriod: 2 + i * 2)],
            ),
        ],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        now: now,
        lead: lead30,
        max: 2,
      );
      expect(list, hasLength(2));
      expect(list.map((r) => r.id).toList(), <int>[
        classStartNotifyIdBase,
        classStartNotifyIdBase + 1,
      ]);
    });

    test('payload 里带上触发时刻 / 课程名 / 教室 / 常驻时长', () {
      final now = DateTime(2026, 9, 14, 7, 0);
      final r = classStartRemindersFor(
        entries: [_entry(classTimes: [_ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        now: now,
        lead: lead30,
      ).single;
      expect(
        r.payload,
        '${r.when.millisecondsSinceEpoch}|高等数学|麦三教3407|1800',
      );
    });
  });

  group('对账（classStartScheduleMatches）', () {
    test('期望为空且系统里没有本模块排期 → 一致', () {
      expect(
        classStartScheduleMatches(desired: const [], pending: const []),
        isTrue,
      );
    });

    test('id 与 payload 全对 → 一致；内容变了 → 不一致', () {
      final desired = [
        ClassStartReminder(
          id: classStartNotifyIdBase,
          courseName: '高等数学',
          classroom: '麦三教3407',
          campus: null,
          periodLabel: '第1-2节',
          clockLabel: '08:00-09:40',
          startAt: DateTime(2026, 9, 14, 8),
          when: DateTime(2026, 9, 14, 7, 30),
          dismissAfter: const Duration(minutes: 30),
          lead: const Duration(minutes: 30),
        ),
      ];
      final ok = [
        ScheduledNotificationInfo(
          id: desired.single.id,
          payload: desired.single.payload,
        ),
      ];
      expect(classStartScheduleMatches(desired: desired, pending: ok), isTrue);
      // 教室变了（payload 变）→ 需要重排
      final changed = [
        ScheduledNotificationInfo(
          id: desired.single.id,
          payload: '${desired.single.when.millisecondsSinceEpoch}|高等数学|麦三教9999|1800',
        ),
      ];
      expect(
        classStartScheduleMatches(desired: desired, pending: changed),
        isFalse,
      );
      // 数量不同 → 需要重排
      expect(classStartScheduleMatches(desired: desired, pending: const []), isFalse);
    });

    test('区间外的排期（实况窗 / 截止提醒）不影响本模块对账', () {
      final desired = [
        ClassStartReminder(
          id: classStartNotifyIdBase,
          courseName: '高等数学',
          classroom: '麦三教3407',
          campus: null,
          periodLabel: '第1-2节',
          clockLabel: '08:00-09:40',
          startAt: DateTime(2026, 9, 14, 8),
          when: DateTime(2026, 9, 14, 7, 30),
          dismissAfter: const Duration(minutes: 30),
          lead: const Duration(minutes: 30),
        ),
      ];
      expect(
        classStartScheduleMatches(
          desired: desired,
          pending: [
            const ScheduledNotificationInfo(id: 920001, payload: 'x'),
            const ScheduledNotificationInfo(id: 8801, payload: 'y'),
            ScheduledNotificationInfo(
              id: desired.single.id,
              payload: desired.single.payload,
            ),
          ],
        ),
        isTrue,
      );
    });
  });

  group('排期同步（幂等 + 撤销）', () {
    List<ScheduleEntry> entries() => [_entry(classTimes: [_ct()])];

    test('首次同步：按常驻形态排期（ongoing / 自动撤下 / 计时器 / 尽量精确）', () async {
      final svc = _FakeService();
      final now = DateTime(2026, 9, 14, 7, 0);
      final ok = await syncClassStartReminders(
        entries: entries(),
        table: PeriodTable.builtin,
        teachingWeek: 2,
        lead: lead30,
        service: svc,
        now: now,
      );
      expect(ok, 1);
      expect(svc.scheduled, hasLength(1));
      final s = svc.scheduled.single;
      expect(s.ongoing, isTrue, reason: '常驻');
      expect(s.autoDismissAfter, lead30, reason: '到上课那一刻由系统撤下');
      expect(s.countdown, isTrue, reason: '系统计时器走秒');
      expect(s.preferExact, isTrue);
      expect(s.title, '即将上课 · 高等数学');
      expect(s.when, _periodStart(_monday, 1).subtract(lead30));
    });

    test('第二次同步（内容一致）→ 一个 scheduleAt 都不再发', () async {
      final svc = _FakeService();
      final now = DateTime(2026, 9, 14, 7, 0);
      Future<int> run() => syncClassStartReminders(
        entries: entries(),
        table: PeriodTable.builtin,
        teachingWeek: 2,
        lead: lead30,
        service: svc,
        now: now,
      );
      expect(await run(), 1);
      expect(await run(), 1);
      expect(svc.scheduled, hasLength(1), reason: '幂等：不重复扰动系统闹钟');
      expect(svc.pendingCalls, 2);
    });

    test('提前量变了 → 先撤旧排期再重排', () async {
      final svc = _FakeService();
      final now = DateTime(2026, 9, 14, 7, 0);
      await syncClassStartReminders(
        entries: entries(),
        table: PeriodTable.builtin,
        teachingWeek: 2,
        lead: lead30,
        service: svc,
        now: now,
      );
      final ok = await syncClassStartReminders(
        entries: entries(),
        table: PeriodTable.builtin,
        teachingWeek: 2,
        lead: const Duration(minutes: 10),
        service: svc,
        now: now,
      );
      expect(ok, 1);
      expect(svc.cancelled, hasLength(1));
      expect(svc.cancelled.single, <int>[classStartNotifyIdBase]);
      expect(svc.scheduled, hasLength(2));
      expect(svc.scheduled.last.when, _periodStart(_monday, 1).subtract(const Duration(minutes: 10)));
      expect(svc.scheduled.last.autoDismissAfter, const Duration(minutes: 10));
    });

    test('关闭开关：撤销只删本模块区间的排期', () async {
      final svc = _FakeService(
        pending: [
          const ScheduledNotificationInfo(id: 8801, payload: 'live'),
          const ScheduledNotificationInfo(id: 920001, payload: 'deadline'),
          const ScheduledNotificationInfo(id: classStartNotifyIdBase, payload: 'mine'),
          const ScheduledNotificationInfo(id: classStartNotifyIdBase + 3, payload: 'mine2'),
        ],
      );
      await cancelClassStartReminders(service: svc);
      expect(svc.cancelled, hasLength(1));
      expect(
        svc.cancelled.single,
        <int>[classStartNotifyIdBase, classStartNotifyIdBase + 3],
      );
      final left = await svc.pendingScheduled();
      expect(left.map((p) => p.id), <int>[8801, 920001]);
    });

    test('没有任何课 → 不排也不撤（空表幂等）', () async {
      final svc = _FakeService();
      final ok = await syncClassStartReminders(
        entries: const [],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        lead: lead30,
        service: svc,
        now: DateTime(2026, 9, 14, 7, 0),
      );
      expect(ok, 0);
      expect(svc.scheduled, isEmpty);
      expect(svc.cancelled, isEmpty);
    });
  });

  group('测试提醒（设置页「发送测试提醒」按钮）', () {
    test('5 秒后出现、常驻 15 秒、id 落在本模块区间内（能被一起清掉）', () async {
      final svc = _FakeService();
      final now = DateTime(2026, 9, 14, 7, 0);
      final ok = await sendTestClassReminder(service: svc, now: now);
      expect(ok, isTrue);
      expect(svc.scheduled, hasLength(1));
      final s = svc.scheduled.single;
      expect(s.id, classStartTestNotifyId);
      expect(classStartIdInRange(s.id), isTrue, reason: '关开关时会被一起撤掉');
      expect(s.when, now.add(classTestReminderDelay));
      expect(s.autoDismissAfter, classTestReminderLifetime);
      expect(s.ongoing, isTrue);
      expect(s.countdown, isTrue);
      // 5 秒的提醒必须精确：非精确会被系统批处理推迟（真机实测 10 秒内不出现）。
      expect(s.preferExact, isTrue);
      expect(s.title, contains('测试课程'));
      expect(s.body, contains('测试教室'));
    });

    test('测试提醒与真提醒的 id 不撞车', () async {
      final svc = _FakeService();
      final now = DateTime(2026, 9, 14, 7, 0);
      await syncClassStartReminders(
        entries: [
          _entry(classTimes: [_ct()]),
        ],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        lead: lead30,
        service: svc,
        now: now,
      );
      await sendTestClassReminder(service: svc, now: now);
      final ids = svc.scheduled.map((s) => s.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: 'id 唯一');
      expect(ids, containsAll(<int>[classStartNotifyIdBase, classStartTestNotifyId]));
    });
  });
}
