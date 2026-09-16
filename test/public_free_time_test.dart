import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/public_query/domain/free_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';

/// 造槽的便捷函数：周一~周五均可。
ScheduleSlot slot(
  int weekday,
  int startPeriod,
  int endPeriod, {
  int startWeek = 1,
  int endWeek = 18,
  String owner = 'A',
  String course = '课程',
}) => ScheduleSlot(
  weekday: weekday,
  startPeriod: startPeriod,
  endPeriod: endPeriod,
  startWeek: startWeek,
  endWeek: endWeek,
  owner: owner,
  courseName: course,
);

void main() {
  group('半日块', () {
    test('默认块 = 江财作息表推导的 1-5 / 6-9 / 10-12', () {
      expect(kDefaultPeriodBlocks, [(1, 5), (6, 9), (10, 12)]);
    });

    test('periodBlocksFromTimes 从真实作息表推出三段（含午休/晚饭断点）', () {
      final blocks = periodBlocksFromTimes([
        for (final p in PeriodTable.builtin.periods)
          (index: p.index, start: p.start, end: p.end),
      ]);
      expect(blocks, kDefaultPeriodBlocks);
    });

    test('periodBlocksFromTimes：间隔刚好等于阈值不断块，超过才断', () {
      final blocks = periodBlocksFromTimes([
        (index: 1, start: '08:00', end: '08:45'),
        (index: 2, start: '09:30', end: '10:15'), // 间隔 45 分钟 = 阈值 → 不断
        (index: 3, start: '11:01', end: '11:45'), // 间隔 46 分钟 → 断
      ], gapMinutes: 45);
      expect(blocks, [(1, 2), (3, 3)]);
    });
  });

  group('findFreeWindows', () {
    test('零占用 → 周一~周五 × 三个半日块，全空', () {
      final windows = findFreeWindows(slots: const [], week: 1);
      expect(windows.length, 15);
      expect(windows.where((w) => w.weekday == 1).map((w) => w.periods), [5, 4, 3]);
      expect(windows.every((w) => w.week == 1), isTrue);
    });

    test('一门课占周一 3-4 节 → 上午裂成两段，且不跨午休', () {
      final windows = findFreeWindows(
        slots: [slot(1, 3, 4)],
        week: 1,
      ).where((w) => w.weekday == 1).toList();
      expect(windows.map((w) => '${w.startPeriod}-${w.endPeriod}'), [
        '1-2',
        '5-5',
        '6-9',
        '10-12',
      ]);
    });

    test('多班占用合并：A 占 1-2、B 占 3-4 → 周一上午整段作废', () {
      final windows = findFreeWindows(
        slots: [slot(1, 1, 2, owner: 'A'), slot(1, 3, 4, owner: 'B')],
        week: 1,
      ).where((w) => w.weekday == 1).toList();
      expect(windows.map((w) => w.label), ['周一 5-5 节', '周一 6-9 节', '周一 10-12 节']);
    });

    test('周次范围之外的占用不算数（第 2 周起才上的课不影响第 1 周）', () {
      final windows = findFreeWindows(
        slots: [slot(1, 1, 5, startWeek: 2, endWeek: 18)],
        week: 1,
      ).where((w) => w.weekday == 1).toList();
      expect(windows.map((w) => w.periods), [5, 4, 3]);

      final week2 = findFreeWindows(
        slots: [slot(1, 1, 5, startWeek: 2, endWeek: 18)],
        week: 2,
      ).where((w) => w.weekday == 1).toList();
      expect(week2.map((w) => w.label), ['周一 6-9 节', '周一 10-12 节']);
    });

    test('minPeriods 过滤掉过短的窗口', () {
      final slots = [slot(1, 3, 4), slot(1, 9, 9)];
      final all = findFreeWindows(slots: slots, week: 1);
      expect(all.where((w) => w.weekday == 1).length, 4);
      final big = findFreeWindows(slots: slots, week: 1, minPeriods: 2);
      expect(
        big.where((w) => w.weekday == 1).map((w) => w.label),
        ['周一 1-2 节', '周一 6-8 节', '周一 10-12 节'],
      );
    });

    test('weekdays 决定是否纳入周末', () {
      expect(
        findFreeWindows(slots: const [], week: 1, weekdays: {6, 7}).length,
        6,
      );
      expect(
        findFreeWindows(slots: const [], week: 1, weekdays: {1, 2, 3, 4, 5, 6, 7})
            .length,
        21,
      );
    });

    test('占用超出 maxPeriod 的部分被裁掉，不抛异常', () {
      // 11-14 节只保留 11-12 → 晚上块只剩 10 节空
      final windows = findFreeWindows(
        slots: [slot(1, 11, 14)],
        week: 1,
        maxPeriod: 12,
      ).where((w) => w.weekday == 1).toList();
      expect(windows.map((w) => w.label), ['周一 1-5 节', '周一 6-9 节', '周一 10-10 节']);
    });

    test('占用完全在 maxPeriod 之外 → 不影响任何窗口', () {
      final windows = findFreeWindows(
        slots: [slot(1, 13, 15)],
        week: 1,
        maxPeriod: 12,
      ).where((w) => w.weekday == 1).toList();
      expect(windows.length, 3);
    });

    test('单节窗口的 compactLabel 不带范围', () {
      final windows = findFreeWindows(slots: [slot(1, 3, 4)], week: 1);
      final single = windows.firstWhere((w) => w.weekday == 1 && w.periods == 1);
      expect(single.label, '周一 5-5 节');
      expect(single.compactLabel, '周一 5 节');
    });
  });

  group('buildOccupancyGrid', () {
    test('不同对象占同一格累加，同一对象重复占同一格只算一次', () {
      final grid = buildOccupancyGrid(
        slots: [
          slot(2, 3, 4, owner: 'A', course: '高数'),
          slot(2, 4, 5, owner: 'A', course: '英语'), // A 自己重叠：4 节仍算 1
          slot(2, 5, 5, owner: 'B', course: '体育'),
        ],
        week: 1,
      );
      expect(grid[2][3], 1);
      expect(grid[2][4], 1);
      expect(grid[2][5], 2);
      expect(grid[1][3], 0);
    });

    test('owner 为空时退化为用课程名去重', () {
      final grid = buildOccupancyGrid(
        slots: [
          const ScheduleSlot(weekday: 3, startPeriod: 1, endPeriod: 2, courseName: 'X'),
          const ScheduleSlot(weekday: 3, startPeriod: 1, endPeriod: 2, courseName: 'X'),
        ],
        week: 1,
      );
      expect(grid[3][1], 1);
    });

    test('越界星期被忽略', () {
      final grid = buildOccupancyGrid(
        slots: [slot(0, 1, 2), slot(8, 1, 2)],
        week: 1,
      );
      for (var d = 1; d <= 7; d++) {
        for (var p = 1; p <= 12; p++) {
          expect(grid[d][p], 0);
        }
      }
    });
  });

  group('rankFreeWindows', () {
    test('按 节数多 → 星期前 → 节次前 排序', () {
      final windows = [
        const FreeWindow(weekday: 3, startPeriod: 1, endPeriod: 5, week: 1),
        const FreeWindow(weekday: 1, startPeriod: 6, endPeriod: 9, week: 1),
        const FreeWindow(weekday: 1, startPeriod: 1, endPeriod: 5, week: 1),
        const FreeWindow(weekday: 1, startPeriod: 10, endPeriod: 12, week: 1),
      ];
      final ranked = rankFreeWindows(windows);
      // 5 节的两条并列 → 星期靠前者在前；随后 4 节、3 节
      expect(ranked.map((w) => w.label), [
        '周一 1-5 节',
        '周三 1-5 节',
        '周一 6-9 节',
        '周一 10-12 节',
      ]);
    });
  });

  group('commonFreeWindows', () {
    test('取所有周次都成立的同一窗口', () {
      // 第 3 周有额外一门课占周一 1-2，故周一 1-2 不是「每周都空」
      final slots = [
        slot(1, 1, 2, startWeek: 3, endWeek: 3, owner: 'B'),
      ];
      final common = commonFreeWindows(slots: slots, weeks: [1, 2, 3]);
      // 第 1、2 周周一上午是全空（1-5 一整段），第 3 周裂成 3-5 → 交集里没有「周一 1-5」；
      // 周二~周五三周都一样，各留 3 段 → 2 + 4×3 = 14
      expect(common.map((w) => w.label), isNot(contains('周一 1-5 节')));
      expect(
        common.where((w) => w.weekday == 1).map((w) => w.label),
        ['周一 6-9 节', '周一 10-12 节'],
      );
      expect(common.length, 14);
    });

    test('周次为空 → 空结果', () {
      expect(commonFreeWindows(slots: const [], weeks: const []), isEmpty);
    });
  });

  group('单双周与 ClassTime 适配', () {
    test('单周课在第 2 周不算占用、第 3 周算占用', () {
      final odd = ScheduleSlot(
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        startWeek: 1,
        endWeek: 16,
        parity: WeekParity.odd,
        owner: 'A',
      );
      expect(odd.coversWeek(2), isFalse);
      expect(odd.coversWeek(3), isTrue);
      final w2 = findFreeWindows(slots: [odd], week: 2)
          .where((w) => w.weekday == 1)
          .toList();
      expect(w2.map((w) => w.label), ['周一 1-5 节', '周一 6-9 节', '周一 10-12 节']);
      final w3 = findFreeWindows(slots: [odd], week: 3)
          .where((w) => w.weekday == 1)
          .toList();
      expect(w3.map((w) => w.label), ['周一 3-5 节', '周一 6-9 节', '周一 10-12 节']);
    });

    test('双周课在第 4 周占用、第 3 周不占用', () {
      final even = ScheduleSlot(
        weekday: 2,
        startPeriod: 6,
        endPeriod: 9,
        startWeek: 2,
        endWeek: 16,
        parity: WeekParity.even,
        owner: 'B',
      );
      expect(even.coversWeek(4), isTrue);
      expect(even.coversWeek(3), isFalse);
      expect(
        findFreeWindows(slots: [even], week: 3)
            .where((w) => w.weekday == 2)
            .map((w) => w.label),
        ['周二 1-5 节', '周二 6-9 节', '周二 10-12 节'],
      );
    });

    test('ScheduleSlot.fromClassTime 逐字段映射', () {
      const t = ClassTime(
        startWeek: 2,
        endWeek: 17,
        weekParity: WeekParity.odd,
        dayOfWeek: DayOfWeek.wednesday,
        startPeriod: 3,
        endPeriod: 4,
        classroom: '蛟桥园3111',
        capacity: 70,
        campus: '蛟桥园校区',
      );
      final slot = ScheduleSlot.fromClassTime(t, owner: '软件231', courseName: '数据结构');
      expect(slot.weekday, 3);
      expect(slot.startPeriod, 3);
      expect(slot.endPeriod, 4);
      expect(slot.startWeek, 2);
      expect(slot.endWeek, 17);
      expect(slot.parity, WeekParity.odd);
      expect(slot.owner, '软件231');
      expect(slot.courseName, '数据结构');
    });

    test('slotsFromClassTimes 批量转换', () {
      const times = [
        ClassTime(
          startWeek: 1,
          endWeek: 16,
          weekParity: WeekParity.every,
          dayOfWeek: DayOfWeek.monday,
          startPeriod: 1,
          endPeriod: 2,
          classroom: 'A101',
        ),
        ClassTime(
          startWeek: 1,
          endWeek: 16,
          weekParity: WeekParity.every,
          dayOfWeek: DayOfWeek.friday,
          startPeriod: 6,
          endPeriod: 7,
          classroom: 'A102',
        ),
      ];
      final slots = slotsFromClassTimes(times, owner: '软件231', courseName: '高数');
      expect(slots.length, 2);
      expect(slots.map((s) => s.weekday), [1, 5]);
      expect(slots.every((s) => s.owner == '软件231'), isTrue);
    });
  });

  group('freePeriodsByOwner', () {
    test('统计每个对象在指定周的空闲节数', () {
      final slots = [
        slot(1, 1, 2, owner: 'A'),
        slot(1, 1, 5, owner: 'B'),
        slot(2, 6, 9, owner: 'B'),
      ];
      final free = freePeriodsByOwner(slots: slots, week: 1);
      // 周一~周五 × 12 节 = 60 节
      expect(free['A'], 60 - 2);
      expect(free['B'], 60 - 9);
    });
  });
}
