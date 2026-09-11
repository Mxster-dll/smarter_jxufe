import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/anti_corruption/period_table_html_parser.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/live_session.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/school_calendar/data/wxcal_repository.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/teaching_week.dart';

void main() {
  // ───────────────────────────── 作息表 ─────────────────────────────

  group('PeriodTable', () {
    test('内置表 12 节，且首节为 08:00-08:45', () {
      const t = PeriodTable.builtin;
      expect(t.periods.length, 12);
      expect(t.isUsable, isTrue);
      final p1 = t.periodOf(1)!;
      expect(p1.start, '08:00');
      expect(p1.end, '08:45');
      expect(p1.durationMinutes, 45);
    });

    test('上午/下午/晚上分段：第 5 节 12:20 结束，第 6 节 14:00 开始', () {
      const t = PeriodTable.builtin;
      expect(t.endAt(DateTime(2026, 9, 14), 5)!.hour, 12);
      expect(t.endAt(DateTime(2026, 9, 14), 5)!.minute, 20);
      expect(t.startAt(DateTime(2026, 9, 14), 6)!.hour, 14);
    });

    test('连续节次段 span 取首节开始、末节结束', () {
      const t = PeriodTable.builtin;
      final span = t.span(DateTime(2026, 9, 14), 3, 4);
      expect(formatHhmm(span.start!), '09:55');
      expect(formatHhmm(span.end!), '11:30');
    });

    test('缺节次时 span 返回 (null, null)', () {
      const t = PeriodTable(
        periods: [ClassPeriod(index: 1, start: '08:00', end: '08:45')],
        label: 'x',
      );
      final span = t.span(DateTime(2026, 9, 14), 1, 2);
      expect(span.start, isNull);
      expect(span.end, isNull);
    });

    test('toJson/fromJson 往返一致', () {
      final round = PeriodTable.fromJson(PeriodTable.builtin.toJson())!;
      expect(round.periods.length, 12);
      expect(round.source, 'builtin');
      expect(round.periodOf(6)!.start, '14:00');
    });

    test('fromJson 容错：垃圾输入返回 null 而非抛异常', () {
      expect(PeriodTable.fromJson(null), isNull);
      expect(PeriodTable.fromJson('junk'), isNull);
      expect(PeriodTable.fromJson({'periods': []}), isNull);
      expect(
        PeriodTable.fromJson({
          'periods': [
            {'index': 'x'},
          ],
        }),
        isNull,
      );
    });

    test('节次所属时段名称', () {
      expect(periodSectionName(1), '上午');
      expect(periodSectionName(5), '上午');
      expect(periodSectionName(6), '下午');
      expect(periodSectionName(10), '晚上');
    });
  });

  // ───────────────────────────── 教学周 ─────────────────────────────

  group('resolveTeachingWeek（真实校历离线数据）', () {
    final terms = wxcalOfflineToDomain();

    test('261 学期：2026-09-10 为开学前第 0 周（老生 09-14 才上课）', () {
      final tw = resolveTeachingWeek(DateTime(2026, 9, 10), terms: terms)!;
      expect(tw.week, 0);
      expect(tw.isBeforeTerm, isTrue);
      expect(tw.label, '开学前');
      // 学期 start 是 09-07（教职工上班/新生军训周），但第一教学周自 09-14 起
      expect(tw.firstMonday, DateTime(2026, 9, 14));
    });

    test('261 学期：2026-09-14（周一）为第 1 教学周', () {
      final tw = resolveTeachingWeek(DateTime(2026, 9, 14), terms: terms)!;
      expect(tw.week, 1);
      expect(tw.isOdd, isTrue);
    });

    test('261 学期：2026-12-31 落在第 16 教学周（与「上课 16 周」吻合）', () {
      final tw = resolveTeachingWeek(DateTime(2026, 12, 31), terms: terms)!;
      expect(tw.week, 16);
      expect(tw.isEven, isTrue);
    });

    test('252 学期：2026-03-02（周一）为第 1 教学周', () {
      final tw = resolveTeachingWeek(DateTime(2026, 3, 2), terms: terms)!;
      expect(tw.week, 1);
      expect(tw.term.term, '252');
    });

    test('周一分界：周日仍属上一周，周一进入下一周', () {
      final sun = resolveTeachingWeek(DateTime(2026, 9, 20), terms: terms)!;
      final mon = resolveTeachingWeek(DateTime(2026, 9, 21), terms: terms)!;
      expect(sun.week, 1);
      expect(mon.week, 2);
    });

    test('空学期列表返回 null', () {
      expect(resolveTeachingWeek(DateTime(2026, 9, 14), terms: []), isNull);
    });

    test('includesWeek 区间判定', () {
      final tw = resolveTeachingWeek(DateTime(2026, 10, 5), terms: terms)!;
      // 2026-10-05 是周一，距 09-14 三周 → 第 4 教学周
      expect(tw.week, 4);
      expect(tw.includesWeek(1, 16), isTrue);
      expect(tw.includesWeek(1, 3), isFalse);
      expect(tw.includesWeek(4, 8), isTrue);
    });
  });

  // ───────────────────────────── 单双周 / 周次过滤 ─────────────────────────────

  group('classTimeAppliesInWeek', () {
    ClassTime ct({int s = 1, int e = 16, WeekParity p = WeekParity.every}) =>
        ClassTime(
          startWeek: s,
          endWeek: e,
          weekParity: p,
          dayOfWeek: DayOfWeek.monday,
          startPeriod: 1,
          endPeriod: 2,
          classroom: '麦三教3401',
        );

    test('全周课在所有周成立', () {
      expect(classTimeAppliesInWeek(ct(), 1), isTrue);
      expect(classTimeAppliesInWeek(ct(), 16), isTrue);
      expect(classTimeAppliesInWeek(ct(), 17), isFalse);
    });

    test('单周课只在奇数周成立', () {
      final odd = ct(p: WeekParity.odd);
      expect(classTimeAppliesInWeek(odd, 3), isTrue);
      expect(classTimeAppliesInWeek(odd, 4), isFalse);
    });

    test('双周课只在偶数周成立', () {
      final even = ct(p: WeekParity.even);
      expect(classTimeAppliesInWeek(even, 4), isTrue);
      expect(classTimeAppliesInWeek(even, 5), isFalse);
    });

    test('未开课的周次（0 周）一律不成立', () {
      expect(classTimeAppliesInWeek(ct(), 0), isFalse);
    });

    test('已结束的课（1-8 周）在第 9 周不成立', () {
      expect(classTimeAppliesInWeek(ct(s: 1, e: 8), 9), isFalse);
    });
  });

  // ───────────────────────────── 课表 → 当天日程 ─────────────────────────────

  group('sessionsOfDay / resolveLiveSession', () {
    // 2026-09-14 是周一，属第 1 教学周
    final monday = DateTime(2026, 9, 14);

    ScheduleEntry entryWith(List<ClassTime> times, {String name = '高等数学'}) =>
        ScheduleEntry(
          classCode: '001',
          className: '主干+',
          courseCode: '1001',
          courseName: name,
          totalHours: 64,
          credits: 4,
          studyNature: '初修',
          teacherCode: 'T1',
          teacherName: '张老师',
          selectionStatus: '选中',
          isCrossMajor: false,
          hasTextbook: true,
          classTimes: times,
        );

    ClassTime ct({
      DayOfWeek day = DayOfWeek.monday,
      int sp = 1,
      int ep = 2,
      int sw = 1,
      int ew = 16,
      WeekParity p = WeekParity.every,
      String room = '麦三教3401',
    }) => ClassTime(
      startWeek: sw,
      endWeek: ew,
      weekParity: p,
      dayOfWeek: day,
      startPeriod: sp,
      endPeriod: ep,
      classroom: room,
      campus: '麦庐园校区',
    );

    test('周一的 1-2 节被正确推算为 08:00-09:35', () {
      final s = sessionsOfDay(
        entries: [entryWith([ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        day: monday,
      );
      expect(s.length, 1);
      expect(formatHhmm(s.first.startAt), '08:00');
      expect(formatHhmm(s.first.endAt), '09:35');
      expect(s.first.periodLabel, '第1-2节');
      expect(s.first.clockLabel, '08:00-09:35');
    });

    test('开学前（第 0 周）无任何课', () {
      final s = sessionsOfDay(
        entries: [entryWith([ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 0,
        day: monday,
      );
      expect(s, isEmpty);
    });

    test('过滤掉非当天的课', () {
      final s = sessionsOfDay(
        entries: [entryWith([ct(day: DayOfWeek.tuesday)])],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        day: monday,
      );
      expect(s, isEmpty);
    });

    test('过滤掉不在本周的单周课', () {
      // 第 2 周是双周 → 单周课不成立
      final s = sessionsOfDay(
        entries: [entryWith([ct(p: WeekParity.odd)])],
        table: PeriodTable.builtin,
        teachingWeek: 2,
        day: monday,
      );
      expect(s, isEmpty);
    });

    test('按开始时刻升序排列', () {
      final s = sessionsOfDay(
        entries: [
          entryWith([ct(sp: 6, ep: 6)], name: '下午课'),
          entryWith([ct(sp: 1, ep: 2)], name: '上午课'),
        ],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        day: monday,
      );
      expect(s.map((e) => e.courseName).toList(), ['上午课', '下午课']);
    });

    test('作息表缺节次时跳过该条（宁可不显示，也不给错误倒计时）', () {
      const tiny = PeriodTable(
        periods: [ClassPeriod(index: 1, start: '08:00', end: '08:45')],
        label: 'x',
      );
      final s = sessionsOfDay(
        entries: [entryWith([ct(sp: 3, ep: 4)])],
        table: tiny,
        teachingWeek: 1,
        day: monday,
      );
      expect(s, isEmpty);
    });

    test('08:20 处于 1-2 节课内 → LiveInClass，剩 75 分钟', () {
      final state = resolveLiveSession(
        entries: [entryWith([ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 8, 20),
      );
      expect(state, isA<LiveInClass>());
      final s = (state as LiveInClass).session;
      expect(s.remainingAt(DateTime(2026, 9, 14, 8, 20)).inMinutes, 75);
      expect(formatCountdown(s.remainingAt(DateTime(2026, 9, 14, 8, 20))), '1 小时 15 分钟');
    });

    test('08:00 整已在上课（边界含首）', () {
      final state = resolveLiveSession(
        entries: [entryWith([ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 8, 0),
      );
      expect(state, isA<LiveInClass>());
    });

    test('09:35 整已下课（边界不含尾）', () {
      final state = resolveLiveSession(
        entries: [entryWith([ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 9, 35),
      );
      expect(state, isA<LiveIdle>());
    });

    test('课间 09:40 → LiveUpcoming（下一节 3-4 节 09:55）', () {
      final state = resolveLiveSession(
        entries: [
          entryWith([ct(sp: 1, ep: 2)], name: '高等数学'),
          entryWith([ct(sp: 3, ep: 4)], name: '大学英语'),
        ],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 9, 40),
      );
      expect(state, isA<LiveUpcoming>());
      final s = (state as LiveUpcoming).session;
      expect(s.courseName, '大学英语');
      expect(s.untilStartAt(DateTime(2026, 9, 14, 9, 40)).inMinutes, 15);
    });

    test('上课中时带上「下一节」', () {
      final state = resolveLiveSession(
        entries: [
          entryWith([ct(sp: 1, ep: 2)], name: '高等数学'),
          entryWith([ct(sp: 3, ep: 4)], name: '大学英语'),
        ],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 8, 20),
      );
      expect(state, isA<LiveInClass>());
      expect((state as LiveInClass).next?.courseName, '大学英语');
    });

    test('当天课全部结束后 → LiveIdle，但保留今日课程列表', () {
      final state = resolveLiveSession(
        entries: [entryWith([ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 22, 0),
      );
      expect(state, isA<LiveIdle>());
      expect((state as LiveIdle).todaySessions.length, 1);
    });

    test('上午 10:00 无课且下午有课 → LiveUpcoming', () {
      final state = resolveLiveSession(
        entries: [entryWith([ct(sp: 6, ep: 7)], name: '大学物理')],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 10, 0),
      );
      expect(state, isA<LiveUpcoming>());
      expect((state as LiveUpcoming).session.courseName, '大学物理');
    });

    test('进度：08:00-09:35 在 08:45 时为 45/95 分钟', () {
      final s = sessionsOfDay(
        entries: [entryWith([ct()])],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        day: monday,
      ).first;
      final p = s.progressMinutesAt(DateTime(2026, 9, 14, 8, 45));
      expect(p.$1, 45);
      expect(p.$2, 95);
      expect(s.progressAt(DateTime(2026, 9, 14, 9, 35)), 1.0);
      expect(s.progressAt(DateTime(2026, 9, 14, 7, 0)), 0.0);
    });
  });

  // ───────────────────────────── 通知内容与去重 ─────────────────────────────

  group('通知内容', () {
    ScheduleEntry entry({
      int sp = 1,
      int ep = 2,
      String name = '高等数学',
      String code = '1001',
    }) =>
        ScheduleEntry(
          classCode: '001',
          className: '主干+',
          courseCode: code,
          courseName: name,
          totalHours: 64,
          credits: 4,
          studyNature: '初修',
          teacherCode: 'T1',
          teacherName: '张老师',
          selectionStatus: '选中',
          isCrossMajor: false,
          hasTextbook: true,
          classTimes: [
            ClassTime(
              startWeek: 1,
              endWeek: 16,
              weekParity: WeekParity.every,
              dayOfWeek: DayOfWeek.monday,
              startPeriod: sp,
              endPeriod: ep,
              classroom: '麦三教3407',
              campus: '麦庐园校区',
            ),
          ],
        );

    test('上课中：标题含课程与教室，倒计时目标 = 下课时刻', () {
      final now = DateTime(2026, 9, 14, 8, 20);
      final state = resolveLiveSession(
        entries: [entry()],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: now,
      );
      final c = liveNotificationContent(state, now)!;
      expect(c.title, '高等数学 · 麦三教3407');
      expect(c.body, contains('上课中'));
      expect(c.countdownTo, DateTime(2026, 9, 14, 9, 35));
      expect(c.totalMinutes, 95);
      expect(c.elapsedMinutes, 20);
    });

    test('下一节课：倒计时目标 = 上课时刻', () {
      final now = DateTime(2026, 9, 14, 7, 30);
      final state = resolveLiveSession(
        entries: [entry()],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: now,
      );
      final c = liveNotificationContent(state, now)!;
      expect(c.countdownTo, DateTime(2026, 9, 14, 8, 0));
      expect(c.title, contains('08:00'));
      expect(c.totalMinutes, 0);
    });

    test('今日无课 → 无通知内容（应撤销通知）', () {
      final now = DateTime(2026, 9, 14, 23, 0);
      final state = resolveLiveSession(
        entries: [entry()],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: now,
      );
      expect(liveNotificationContent(state, now), isNull);
    });

    test('去重键：上课中与下一节不同；同一状态稳定', () {
      final inClass = resolveLiveSession(
        entries: [entry()],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 8, 20),
      );
      final upcoming = resolveLiveSession(
        entries: [entry()],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 7, 30),
      );
      final inClass2 = resolveLiveSession(
        entries: [entry()],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 8, 40),
      );
      expect(liveSessionKey(inClass), isNot(liveSessionKey(upcoming)));
      // 同一节课的同一状态 → 键相同（不会重复推送）
      expect(liveSessionKey(inClass), liveSessionKey(inClass2));
    });

    test('不同课拥有不同去重键', () {
      final a = resolveLiveSession(
        entries: [entry(name: '高等数学', code: '1001')],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 8, 20),
      );
      final b = resolveLiveSession(
        entries: [entry(name: '大学英语', code: '1002')],
        table: PeriodTable.builtin,
        teachingWeek: 1,
        now: DateTime(2026, 9, 14, 8, 20),
      );
      expect(liveSessionKey(a), isNot(liveSessionKey(b)));
    });

    test('formatCountdown 文本', () {
      expect(formatCountdown(const Duration(minutes: 23)), '23 分钟');
      expect(formatCountdown(const Duration(hours: 1, minutes: 5)), '1 小时 5 分钟');
      expect(formatCountdown(const Duration(hours: 2)), '2 小时');
      expect(formatCountdown(Duration.zero), '已结束');
      expect(formatCountdown(const Duration(seconds: -5)), '已结束');
    });
  });

  // ───────────────────────────── 课表序列化 ─────────────────────────────

  group('课表缓存序列化', () {
    test('ScheduleEntry 往返一致', () {
      final e = ScheduleEntry(
        classCode: '001',
        className: '主干+',
        courseCode: '1001',
        courseName: '高等数学',
        totalHours: 64,
        credits: 4,
        studyNature: '初修',
        teacherCode: 'T1',
        teacherName: '张老师',
        selectionStatus: '选中',
        isCrossMajor: false,
        hasTextbook: true,
        remark: '备注',
        classTimes: [
          ClassTime(
            startWeek: 1,
            endWeek: 16,
            weekParity: WeekParity.odd,
            dayOfWeek: DayOfWeek.wednesday,
            startPeriod: 3,
            endPeriod: 5,
            classroom: '麦三教3401',
            capacity: 70,
            campus: '麦庐园校区',
          ),
        ],
      );
      final round = ScheduleEntry.fromJson(e.toJson())!;
      expect(round.courseName, '高等数学');
      expect(round.credits, 4);
      expect(round.remark, '备注');
      final ct = round.classTimes.single;
      expect(ct.weekParity, WeekParity.odd);
      expect(ct.dayOfWeek, DayOfWeek.wednesday);
      expect(ct.startPeriod, 3);
      expect(ct.endPeriod, 5);
      expect(ct.capacity, 70);
      expect(ct.campus, '麦庐园校区');
    });

    test('缺关键字段返回 null，不抛异常', () {
      expect(ScheduleEntry.fromJson(null), isNull);
      expect(ScheduleEntry.fromJson({'courseCode': '1001'}), isNull);
      expect(ClassTime.fromJson({'startWeek': 1}), isNull);
    });

    test('枚举名损坏时回退为默认值', () {
      final round = ScheduleEntry.fromJson({
        'courseName': 'X',
        'classTimes': [
          {
            'startWeek': 1,
            'endWeek': 2,
            'startPeriod': 1,
            'endPeriod': 2,
            'classroom': 'A101',
            'weekParity': 'bogus',
            'dayOfWeek': 'bogus',
          },
        ],
      })!;
      expect(round.classTimes.single.weekParity, WeekParity.every);
      expect(round.classTimes.single.dayOfWeek, DayOfWeek.monday);
    });
  });

  // ─────────────── 真实教务响应解析（fixture） ───────────────

  group('PeriodTableHtmlParser（真实教务响应）', () {
    // 取自 https://jwxt.jxufe.edu.cn/public/SchoolTimetable.show.jsp（2026-0，免登录）
    final html = File('test/fixtures/timetable_261.html').readAsStringSync();

    test('解析出 12 个节次', () {
      final t = PeriodTableHtmlParser().parse(html, termCode: '2026-0')!;
      expect(t.periods.length, 12);
      expect(t.isUsable, isTrue);
      expect(t.termCode, '2026-0');
      expect(t.source, 'remote');
    });

    test('节次时刻与教务处公布值逐条一致', () {
      final t = PeriodTableHtmlParser().parse(html)!;
      const expected = {
        1: ('08:00', '08:45'),
        2: ('08:50', '09:35'),
        3: ('09:55', '10:40'),
        4: ('10:45', '11:30'),
        5: ('11:35', '12:20'),
        6: ('14:00', '14:45'),
        7: ('14:50', '15:35'),
        8: ('15:55', '16:40'),
        9: ('16:45', '17:30'),
        10: ('18:40', '19:25'),
        11: ('19:30', '20:15'),
        12: ('20:20', '21:05'),
      };
      expected.forEach((index, times) {
        final p = t.periodOf(index);
        expect(p, isNotNull, reason: '缺少第 $index 节');
        expect(p!.start, times.$1, reason: '第 $index 节开始时刻');
        expect(p.end, times.$2, reason: '第 $index 节结束时刻');
      });
    });

    test('rowspan 合并未干扰解析：第 6 节起仍是 14:00（下午段首行 5 格）', () {
      final t = PeriodTableHtmlParser().parse(html)!;
      expect(formatHhmm(t.startAt(DateTime(2026, 9, 14), 6)!), '14:00');
      expect(formatHhmm(t.startAt(DateTime(2026, 9, 14), 10)!), '18:40');
    });

    test('抓到了表格标题', () {
      final t = PeriodTableHtmlParser().parse(html)!;
      expect(t.label, contains('江西财经大学'));
      expect(t.label, contains('作息时间'));
    });

    test('解析结果与内置兜底表一致（当前学期属主流版）', () {
      final t = PeriodTableHtmlParser().parse(html)!;
      for (final p in PeriodTable.builtin.periods) {
        final r = t.periodOf(p.index)!;
        expect(
          (r.start, r.end),
          (p.start, p.end),
          reason: '第 ${p.index} 节与内置表不一致',
        );
      }
    });

    test('垃圾 HTML 返回 null 而非抛异常', () {
      expect(PeriodTableHtmlParser().parse('<html><body>无表格</body></html>'), isNull);
    });
  });
}
