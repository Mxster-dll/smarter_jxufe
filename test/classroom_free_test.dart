/// 「找空闲教室」（公共查询 SB11 / SB12）领域层的守卫测试。
///
/// 数据来源口径见 `lib/features/ims/public_query/domain/classroom_free.dart` 文件头：
/// **不打原网页那两个端点**，只用教室课表报表在客户端算。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/public_query/domain/classroom_free.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/free_time.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_timetable.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_gap_rows.dart';

/// fixture 是 2026-09-14 从教务真实抓下来的教室课表（已转 UTF-8 存盘）。
String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

List<PublicTimetable> _rooms() => parsePublicTimetableReport(
  _fixture('public_jsikb_rooms.html'),
  ownerPrefixes: const ['教室'],
);

/// 教室下拉清单里会用到的三个校区教室（名称格式与教务一致）。
const _dropdown = <PublicQueryOption>[
  PublicQueryOption(code: '1000752', name: '蛟北区G301[69][公共实验室]'),
  PublicQueryOption(code: '1000753', name: '蛟北区G302[63][公共实验室]'),
  PublicQueryOption(code: '1000754', name: '蛟北区G303[63][公共实验室]'),
  PublicQueryOption(code: '1009999', name: '蛟三教3101[40][一般教室]'),
];

/// 手工构造的占用槽（模式 A/B 的算法测试用）。
ScheduleSlot _slot({
  required int weekday,
  required int startPeriod,
  required int endPeriod,
  int startWeek = 1,
  int endWeek = 20,
  WeekParity parity = WeekParity.every,
  String courseName = '某课',
}) => ScheduleSlot(
  weekday: weekday,
  startPeriod: startPeriod,
  endPeriod: endPeriod,
  startWeek: startWeek,
  endWeek: endWeek,
  parity: parity,
  courseName: courseName,
  owner: '测试教室',
);

void main() {
  group('教室名解析（教务下拉格式）', () {
    test('三段式：名称 + 容量 + 类型', () {
      final r = parseClassroomName('蛟三教3101[40][一般教室]');
      expect(r.name, '蛟三教3101');
      expect(r.capacity, 40);
      expect(r.kind, '一般教室');
    });

    test('只有容量', () {
      final r = parseClassroomName('博雅艺术中心B01[30]');
      expect(r.name, '博雅艺术中心B01');
      expect(r.capacity, 30);
      expect(r.kind, '');
    });

    test('只有类型（没有容量）→ 不能把类型当容量', () {
      final r = parseClassroomName('报告厅[学术报告厅]');
      expect(r.name, '报告厅');
      expect(r.capacity, 0);
      expect(r.kind, '学术报告厅');
    });

    test('没有方括号 → 原样当名称', () {
      final r = parseClassroomName('蛟北区G301');
      expect(r.name, '蛟北区G301');
      expect(r.capacity, 0);
      expect(r.kind, '');
    });
  });

  group('教室清单', () {
    test('解析 + 去重 + 跳过空名', () {
      final infos = parseClassroomInfos([
        ..._dropdown,
        const PublicQueryOption(code: 'x', name: '蛟北区G301[69][公共实验室]'),
        const PublicQueryOption(code: 'y', name: '   '),
      ]);
      expect(infos.length, 4);
      expect(infos.first.code, '1000752');
      expect(infos.first.label, '蛟北区G301 · 69 座 · 公共实验室');
      expect(infos.last.name, '蛟三教3101');
    });

    test('matchKey 与报表 owner 同口径（去空白 / 全角括号 / 大小写）', () {
      final info = parseClassroomInfo(
        const PublicQueryOption(code: '1', name: '蛟北区G301[69][公共实验室]'),
      );
      expect(info!.matchKey, '蛟北区g301');
    });

    test('非实体教室（线上教学 / 不排教室）不进候选', () {
      const options = <PublicQueryOption>[
        PublicQueryOption(code: 'v', name: '线上教学[1000][不排教室]'),
        PublicQueryOption(code: 'r', name: '蛟三教3101[40][一般教室]'),
      ];
      final infos = parseClassroomInfos(options);
      expect(infos.length, 2, reason: '清单本身保留（解析层不管语义）');
      expect(isPhysicalClassroom(infos.first), isFalse);
      expect(isPhysicalClassroom(infos.last), isTrue);
      final rooms = classroomOccupanciesOf(
        timetables: const [],
        rooms: infos,
      );
      expect(rooms.map((r) => r.name).toList(), ['蛟三教3101']);
    });

    test('按名字找同一间教室：全等优先，退化到包含；找不到给 null', () {
      final infos = parseClassroomInfos(_dropdown);
      expect(
        classroomInfoNamed(infos, '蛟北区G301')?.code,
        '1000752',
        reason: '报表里只有名字（无 [69][公共实验室] 后缀）',
      );
      expect(classroomInfoNamed(infos, '不存在的教室'), isNull);
      expect(classroomInfoNamed(infos, ''), isNull);
    });
  });

  group('占用构建（真实 fixture：3 间教室）', () {
    test('报表里的教室带楼房 / 类型，槽数与真实数据一致', () {
      final rooms = classroomOccupanciesOf(timetables: _rooms());
      expect(rooms.length, 3);
      // 刺绣入门 [2-9]周 周五 1-2 节 + 3-4 节 → 两条槽
      final b01 = rooms.firstWhere((r) => r.name == '博雅艺术中心B01');
      expect(b01.slots.length, 2);
      expect(b01.building, '博雅艺术中心');
      expect(b01.kind, '设计室');
      final g301 = rooms.firstWhere((r) => r.name == '蛟北区G301');
      expect(g301.slots.length, 10);
      expect(g301.building, '计算机实践教学中心（北区）');
      expect(g301.kind, '公共实验室');
    });

    test('教室下拉清单里的教室会被补齐（报表里没有 = 整学期空闲）', () {
      final rooms = classroomOccupanciesOf(
        timetables: _rooms(),
        rooms: parseClassroomInfos(_dropdown),
      );
      // 3 间在报表里 + G303 / 蛟三教3101 只在清单里
      expect(rooms.length, 5);
      final extra = rooms.firstWhere((r) => r.name == '蛟三教3101');
      expect(extra.slots, isEmpty, reason: '报表里没有它 → 整学期空闲');
      expect(extra.capacity, 40);
      expect(extra.kind, '一般教室');
      final g301 = rooms.firstWhere((r) => r.name == '蛟北区G301');
      expect(g301.code, '1000752', reason: '报表与清单按下标合并');
      expect(g301.capacity, 69, reason: '容量只有清单里有');
    });
  });

  group('模式 A：按时间找空闲教室', () {
    List<ClassroomOccupancy> rooms() =>
        classroomOccupanciesOf(timetables: _rooms());

    test('第 1 周（课程还没开始）整层都是空的', () {
      final hits = freeClassroomsAt(
        rooms: rooms(),
        week: 1,
        weekdays: const [5],
        startPeriod: 1,
        endPeriod: 2,
      );
      expect(hits.map((h) => h.room.name), contains('博雅艺术中心B01'));
      expect(hits.every((h) => h.allFree), isTrue);
    });

    test('第 2 周 周五 1-2 节：B01 有刺绣入门 → 不计入', () {
      final hits = freeClassroomsAt(
        rooms: rooms(),
        week: 2,
        weekdays: const [5],
        startPeriod: 1,
        endPeriod: 2,
      );
      expect(hits.map((h) => h.room.name), isNot(contains('博雅艺术中心B01')));
      expect(hits.map((h) => h.room.name), contains('蛟北区G301'));
    });

    test('被占的星期要给出课程名（解释为什么这间不行）', () {
      // G302：周一 6-8 节有「Excel高级数据处理与分析」[2-17]周；周三 6-7 节空着。
      final hits = freeClassroomsAt(
        rooms: rooms(),
        week: 2,
        weekdays: const [1, 3],
        startPeriod: 6,
        endPeriod: 7,
      );
      final g302 = hits.firstWhere((h) => h.room.name == '蛟北区G302');
      expect(g302.allFree, isFalse);
      expect(g302.freeWeekdays, [3]);
      expect(g302.busyWeekdays, [1]);
      expect(g302.busyCourses[1], 'Excel高级数据处理与分析');
      expect(g302.detail, contains('有课'));
    });

    test('单双周：双周的课在第 3 周是空的、第 4 周才占', () {
      // G301：数据处理技术基础 [2-17]周(**双周**) 周一 6-7 节。
      List<ClassroomFreeHit> at(int week) => freeClassroomsAt(
        rooms: rooms(),
        week: week,
        weekdays: const [1],
        startPeriod: 6,
        endPeriod: 7,
      );
      expect(
        at(3).map((h) => h.room.name),
        contains('蛟北区G301'),
        reason: '双周的课在第 3 周（单周）不生效 → 应该空着',
      );
      expect(at(4).map((h) => h.room.name), isNot(contains('蛟北区G301')));
    });

    test('跨节次区间：只要有一节被占就算占用', () {
      final room = ClassroomOccupancy(
        name: '测试教室',
        slots: [_slot(weekday: 3, startPeriod: 4, endPeriod: 5)],
      );
      expect(
        room.freeIn(week: 1, weekday: 3, startPeriod: 1, endPeriod: 3),
        isTrue,
      );
      expect(
        room.freeIn(week: 1, weekday: 3, startPeriod: 3, endPeriod: 5),
        isFalse,
        reason: '3-5 节里 4-5 节被占 → 整段不算空',
      );
      expect(
        room.freeIn(week: 1, weekday: 4, startPeriod: 3, endPeriod: 5),
        isTrue,
      );
    });

    test('排序：全空的在前，其次空的天数多，同输入顺序确定', () {
      final rooms = [
        ClassroomOccupancy(code: 'a', name: 'B教室', capacity: 10, slots: [
          _slot(weekday: 1, startPeriod: 1, endPeriod: 2),
        ]),
        ClassroomOccupancy(
          code: 'b',
          name: 'A教室',
          capacity: 20,
          slots: const [],
        ),
      ];
      final hits = freeClassroomsAt(
        rooms: rooms,
        week: 1,
        weekdays: const [1, 2],
        startPeriod: 1,
        endPeriod: 2,
      );
      expect(hits.map((h) => h.room.name).toList(), ['A教室', 'B教室']);
      expect(hits.first.allFree, isTrue);
      expect(hits.first.detail, '周一、周二 都空');
      expect(hits.last.detail, contains('周一'));
    });

    test('没有选星期 / 节次区间倒挂 → 空结果（不抛）', () {
      expect(
        freeClassroomsAt(
          rooms: rooms(),
          week: 1,
          weekdays: const [],
          startPeriod: 1,
          endPeriod: 2,
        ),
        isEmpty,
      );
      expect(
        freeClassroomsAt(
          rooms: rooms(),
          week: 1,
          weekdays: const [1],
          startPeriod: 5,
          endPeriod: 3,
        ),
        isEmpty,
      );
    });
  });

  group('模式 B：按教室查空闲', () {
    ClassroomOccupancy g301() => classroomOccupanciesOf(
      timetables: _rooms(),
    ).firstWhere((r) => r.name == '蛟北区G301');

    test('第 2 周 G301：周一 3-9 节被占，上午只剩 1-2 节', () {
      final windows = roomFreeWindows(room: g301(), week: 2);
      final monday = windows.where((w) => w.weekday == 1).toList();
      expect(monday.map((w) => '${w.startPeriod}-${w.endPeriod}').toList(), [
        '1-2',
        '10-12',
      ]);
      expect(
        windows.where((w) => w.weekday == 5).map((w) => w.startPeriod),
        contains(1),
        reason: 'G301 周五一条排课都没有 → 整天全空',
      );
    });

    test('第 1 周（课程未开始）上午整段是空的', () {
      final windows = roomFreeWindows(room: g301(), week: 1);
      expect(
        windows.any(
          (w) => w.weekday == 1 && w.startPeriod == 1 && w.endPeriod == 5,
        ),
        isTrue,
      );
    });

    test('整学期每周都空：周一 3-5 节被 2-17 周占用 → 不进固定空闲', () {
      final common = roomCommonFreeWindows(
        room: g301(),
        weeks: [for (var w = 1; w <= 20; w++) w],
      );
      expect(
        common.any((w) => w.weekday == 1 && w.startPeriod == 3),
        isFalse,
        reason: '周一 3-5 节 2-17 周都有课',
      );
      expect(
        common.any(
          (w) => w.weekday == 1 && w.startPeriod == 1 && w.endPeriod == 2,
        ),
        isTrue,
        reason: '周一 1-2 节整学期都没课 → 固定空闲',
      );
      expect(
        common.any(
          (w) => w.weekday == 5 && w.startPeriod == 1 && w.endPeriod == 5,
        ),
        isTrue,
        reason: 'G301 周五整学期都没课',
      );
    });

    test('整学期没排课的教室：所有周都空', () {
      const room = ClassroomOccupancy(name: '蛟三教3101', capacity: 40);
      final windows = roomFreeWindows(room: room, week: 7);
      expect(windows.length, 3 * 7, reason: '三个半日块 × 七天');
      expect(
        windows.every((w) => w.startPeriod >= 1 && w.endPeriod <= 12),
        isTrue,
      );
    });

    test('minPeriods 能过滤掉零碎空档', () {
      final room = ClassroomOccupancy(
        name: '测试教室',
        slots: [
          _slot(weekday: 1, startPeriod: 1, endPeriod: 4),
          _slot(weekday: 1, startPeriod: 6, endPeriod: 12),
        ],
      );
      final single = roomFreeWindows(room: room, week: 1, minPeriods: 1);
      expect(
        single.any((w) => w.weekday == 1 && w.startPeriod == 5),
        isTrue,
      );
      final wide = roomFreeWindows(room: room, week: 1, minPeriods: 2);
      expect(wide.any((w) => w.weekday == 1), isFalse);
    });
  });

  group('教学周数推断', () {
    test('取槽里的最大 endWeek；解析不出（30）的不算', () {
      expect(
        classroomTermWeeksOf([
          ClassroomOccupancy(
            name: 'a',
            slots: [_slot(weekday: 1, startPeriod: 1, endPeriod: 2, endWeek: 17)],
          ),
          ClassroomOccupancy(
            name: 'b',
            slots: [_slot(weekday: 1, startPeriod: 1, endPeriod: 2, endWeek: 30)],
          ),
        ]),
        17,
      );
    });

    test('没有可用信息时回落 20（与多班对照的周次下拉同口径）', () {
      expect(classroomTermWeeksOf(const []), kClassroomFreeWeeks);
      expect(kClassroomFreeWeeks, 20);
    });
  });

  group('大节档与口径常数', () {
    test('五档 = 教务课表行标签（1-2 / 3-5 / 6-7 / 8-9 / 10-12）'
        '—— 2026-09-19 二轮起页面不再用它（节次 1-12 每节独立）', () {
      expect(
        kClassroomFreePeriodPresets.map((e) => '${e.$2}-${e.$3}').toList(),
        ['1-2', '3-5', '6-7', '8-9', '10-12'],
      );
    });
  });

  group('节次 1-12 独立 + 按现在自动选段（用户 2026-09-19 二轮）', () {
    const table = PeriodTable.builtin;

    test('节次段 = 被「间隔 > 1h」的节点切开的三段（与课表矮行同一判据）', () {
      expect(scheduleGapThresholdMinutes, 60);
      expect(classroomPeriodSegments(table), [(1, 5), (6, 9), (10, 12)]);
      expect(classroomPeriodSegments(null), isEmpty);
    });

    test('自动选段 = 从当前节数到「下一个节点前的最后一节课」', () {
      expect(
        classroomAutoPeriodRange(table: table, now: DateTime(2026, 9, 16, 9, 40)),
        (start: 3, end: 5),
        reason: '09:40 在第 2 节下课之后 → 从下节课（第 3 节 09:55）到午休前的第 5 节',
      );
      expect(
        classroomAutoPeriodRange(table: table, now: DateTime(2026, 9, 16, 9, 0)),
        (start: 2, end: 5),
        reason: '09:00 正在上第 2 节（08:50-09:35）→ 从当前节数开始',
      );
      expect(
        classroomAutoPeriodRange(table: table, now: DateTime(2026, 9, 16, 14, 5)),
        (start: 6, end: 9),
        reason: '14:05 正在上第 6 节 → 下午段',
      );
      expect(
        classroomAutoPeriodRange(table: table, now: DateTime(2026, 9, 16, 18, 0)),
        (start: 10, end: 12),
        reason: '17:30-18:40 之间不在上课 → 从第 10 节（晚饭后那一段）开始',
      );
    });

    test('早于第一节 / 晚于最后一节 / 没有作息表', () {
      expect(
        classroomAutoPeriodRange(table: table, now: DateTime(2026, 9, 16, 7, 0)),
        (start: 1, end: 5),
        reason: '还没到第一节课 → 从第 1 节开始',
      );
      expect(
        classroomAutoPeriodRange(table: table, now: DateTime(2026, 9, 16, 23, 30)),
        (start: 10, end: 12),
        reason: '当天节次已全部结束 → 退回最后一段',
      );
      expect(
        classroomAutoPeriodRange(table: null, now: DateTime(2026, 9, 16, 9, 0)),
        isNull,
      );
    });

    test('勾中的节次并成连续区间（摘要不出现「1 节 + 2 节 + 3 节」）', () {
      expect(classroomPeriodRanges(const [1, 2, 3, 4, 5]), [(1, 5)]);
      expect(classroomPeriodRanges(const [1, 3]), [(1, 1), (3, 3)]);
      expect(classroomPeriodRanges(const [5, 4, 3]), [(3, 5)]);
      expect(classroomPeriodRanges(const [0, 13, 2]), [(2, 2)]);
      expect(classroomPeriodRanges(const []), isEmpty);
      expect(
        classroomPeriodBlocksLabel(classroomPeriodRanges(const [1, 2, 3, 4, 5])),
        '1-5 节',
      );
      expect(
        classroomPeriodBlocksLabel(classroomPeriodRanges(const [1, 3])),
        '1 节 + 3 节',
      );
    });

    test('自动选出的那一段直接喂给 freeClassroomsAt（段内每节都要空）', () {
      final room = ClassroomOccupancy(
        name: '测试楼301',
        slots: [
          _slot(weekday: 3, startPeriod: 3, endPeriod: 5, courseName: '数据库'),
        ],
      );
      final auto = classroomAutoPeriodRange(
        table: table,
        now: DateTime(2026, 9, 16, 9, 40),
      )!;
      final blocks = classroomPeriodRanges([
        for (var p = auto.start; p <= auto.end; p++) p,
      ]);
      expect(blocks, [(3, 5)]);
      expect(
        freeClassroomsAt(
          rooms: [room],
          week: 2,
          weekdays: const [3],
          startPeriod: 3,
          endPeriod: 5,
          periodBlocks: blocks,
        ),
        isEmpty,
        reason: '周三 3-5 被「数据库」占用',
      );
      expect(
        freeClassroomsAt(
          rooms: [room],
          week: 2,
          weekdays: const [5],
          startPeriod: 3,
          endPeriod: 5,
          periodBlocks: blocks,
        ).map((h) => h.room.name).toList(),
        ['测试楼301'],
        reason: '周五同段空着',
      );
    });
  });

  group('节次绘画单元 classroomPeriodRuns（连续选中合并成一段）', () {
    test('没勾中的各自独立，连续勾中的合成一段', () {
      final runs = classroomPeriodRuns(const {3, 4, 5});
      expect(runs.first, const <int>[1]);
      expect(runs[1], const <int>[2]);
      expect(runs[2], const <int>[3, 4, 5]);
      expect(runs[3], const <int>[6]);
      expect(runs.last, const <int>[schedulePeriodCount]);
      // 1、2 两格 + 一段 + 6..12 七格 = 10 段。
      expect(runs.length, 10);
      expect(runs.expand((r) => r).toList(), [
        for (var p = 1; p <= schedulePeriodCount; p++) p,
      ]);
    });

    test('空集合 = 12 个独立格；全选 = 一整段', () {
      expect(classroomPeriodRuns(const {}).length, schedulePeriodCount);
      expect(classroomPeriodRuns(const {}).every((r) => r.length == 1), isTrue);
      final all = classroomPeriodRuns({
        for (var p = 1; p <= schedulePeriodCount; p++) p,
      });
      expect(all.length, 1);
      expect(all.single.length, schedulePeriodCount);
    });

    test('越界值与 count 覆盖都容错', () {
      expect(classroomPeriodRuns(const {0, 13, -1}), classroomPeriodRuns(const {}));
      expect(classroomPeriodRuns(const {1, 2, 3}, count: 3).length, 1);
      expect(classroomPeriodRuns(const {2}, count: 3), const [
        <int>[1],
        <int>[2],
        <int>[3],
      ]);
    });
  });

  group('节次「连接 / 断开」过渡（用户 2026-09-20 九轮要的动画）', () {
    /// 两条**端点恒等式**：过渡分段在 t=0 / t=1 必须分别等于两态的稳态分段。
    /// 否则动画的第一帧与最后一帧都会跟稳态差一点点 —— 肉眼就是「跳一下」。
    void expectEndpoints(Set<int> from, Set<int> to) {
      expect(
        classroomPeriodJointSegments(from, from),
        classroomPeriodRuns(from),
        reason: 't=0 必须等于「按下前」的稳态分段',
      );
      expect(
        classroomPeriodJointSegments(to, to),
        classroomPeriodRuns(to),
        reason: 't=1 必须等于「按下后」的稳态分段',
      );
    }

    test('端点恒等式：任意两态都对得上（含空集 / 全集 / 完全换一套）', () {
      const cases = <(Set<int>, Set<int>)>[
        ({1, 2, 3, 4, 5}, {1, 2, 3, 4, 5}),
        (<int>{}, {1}),
        ({1, 2, 4, 5}, {1, 2, 3, 4, 5}),
        ({1, 2, 3, 4, 5}, {1, 2, 4, 5}),
        ({1, 3, 5}, {2, 4, 6}),
        ({1, 2, 3, 4, 5}, {1, 2, 3, 4, 5, 7, 8, 9, 10}),
        ({1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}, <int>{}),
      ];
      for (final (from, to) in cases) {
        expectEndpoints(from, to);
      }
    });

    test('两段被接上 / 一段被拆开：分段都是 [1,2] + [3] + [4,5] + 每格独立', () {
      const merge = <int>{1, 2, 4, 5};
      const merged = <int>{1, 2, 3, 4, 5};
      for (final (from, to) in [(merge, merged), (merged, merge)]) {
        final segments = classroomPeriodJointSegments(from, to);
        expect(segments.take(3).toList(), const [
          <int>[1, 2],
          <int>[3],
          <int>[4, 5],
        ]);
        expect(segments.length, 10, reason: '3 段 + 6..12 七格各自独立');
        expect(
          segments.expand((s) => s),
          [for (var p = 1; p <= schedulePeriodCount; p++) p],
          reason: '每格都要有归属、且不重不漏',
        );
      }
    });

    test('缝：接上时 0→1、拆开时 1→0；两态一样的缝不返回', () {
      const merge = <int>{1, 2, 4, 5};
      const merged = <int>{1, 2, 3, 4, 5};

      final growing = classroomPeriodJoints(
        merge,
        merged,
        classroomPeriodJointSegments(merge, merged),
      );
      expect(growing.map((j) => (j.left, j.right)).toList(), const [
        (2, 3),
        (3, 4),
      ]);
      expect(growing.every((j) => j.fromRed == 0 && j.toRed == 1), isTrue);

      final shrinking = classroomPeriodJoints(
        merged,
        merge,
        classroomPeriodJointSegments(merged, merge),
      );
      expect(shrinking.map((j) => (j.left, j.right)).toList(), const [
        (2, 3),
        (3, 4),
      ]);
      expect(shrinking.every((j) => j.fromRed == 1 && j.toRed == 0), isTrue);
      // 第 5 节两态都选中、且和第 6 节两态都没连上 → 5|6 那条缝没有动画可做。
      expect(shrinking.any((j) => j.left == 5 && j.right == 6), isFalse);
    });

    test('整体换一套（点「按现在时间」）：只有真正变了态的缝才动', () {
      final segments = classroomPeriodJointSegments(
        const {1, 2, 3, 4, 5},
        const {3, 4, 5},
      );
      expect(segments.take(3).toList(), const [
        <int>[1],
        <int>[2],
        <int>[3, 4, 5],
      ]);
      final joints = classroomPeriodJoints(
        const {1, 2, 3, 4, 5},
        const {3, 4, 5},
        segments,
      );
      // 1 和 2 一起退掉 → 两条缝都在收：1|2（本来连着）与 2|3（本来连着）。
      expect(joints.map((j) => (j.left, j.right)).toList(), const [
        (1, 2),
        (2, 3),
      ]);
      expect(joints.every((j) => j.fromRed == 1 && j.toRed == 0), isTrue);
      // 段内（3|4、4|5）与 5|6 都不返回。
      expect(joints.length, 2);
    });

    test('拖动一次选中好几格：新段内部的缝一起长出来', () {
      const from = <int>{1, 2, 3, 4, 5};
      const to = <int>{1, 2, 3, 4, 5, 7, 8, 9, 10};
      final joints = classroomPeriodJoints(
        from,
        to,
        classroomPeriodJointSegments(from, to),
      );
      expect(joints.map((j) => (j.left, j.right)).toList(), const [
        (7, 8),
        (8, 9),
        (9, 10),
      ]);
      expect(joints.every((j) => j.fromRed == 0 && j.toRed == 1), isTrue);
      // 6 号格两态都没选中 → 5|6 与 6|7 都不是「红连过去」。
      expect(joints.any((j) => j.left == 5 || j.right == 6), isFalse);
    });

    test('越界值与 count 覆盖都容错', () {
      expect(
        classroomPeriodJointSegments(const {0, 13}, const {0, 13}),
        classroomPeriodRuns(const {}),
      );
      expect(classroomPeriodJointSegments(const {1, 2}, const {1, 2}, count: 3), const [
        <int>[1, 2],
        <int>[3],
      ]);
      expect(classroomPeriodJoints(const {}, const {}, const []), isEmpty);
      expect(
        classroomPeriodJoints(const {}, const {1}, classroomPeriodRuns(const {})),
        isEmpty,
        reason: '没有相邻段就没有缝',
      );
    });
  });
  group('源码守卫：不许回去打原网页那两个端点', () {
    String read(String path) => File(path).readAsStringSync();

    test('页面与领域层都不提 SB11 / SB12 的 data.jsp', () {
      for (final path in [
        'lib/features/ims/public_query/presentation/classroom_free_screen.dart',
        'lib/features/ims/public_query/presentation/classroom_free_view.dart',
        'lib/features/ims/public_query/domain/classroom_free.dart',
      ]) {
        final code = read(path)
            .split('\n')
            .map((l) => l.split('//').first)
            .join('\n');
        expect(code.contains('fzcjcckkxjsi'), isFalse, reason: path);
        expect(code.contains('fjsickkxzcjc'), isFalse, reason: path);
      }
    });

    test('选了楼房时只信报表（不能把整校区清单灌进来）', () {
      final code = read(
        'lib/features/ims/public_query/presentation/classroom_free_screen.dart',
      );
      expect(
        code.contains('rooms: _building.isEmpty ? infos : const <ClassroomInfo>[]'),
        isTrue,
      );
    });

    test('公共查询页有两个入口，且都 push 到找教室页', () {
      final code = read(
        'lib/features/ims/public_query/presentation/public_query_screen.dart',
      );
      expect(code.contains("Key('publicQueryFindClassroomByTime')"), isTrue);
      expect(code.contains("Key('publicQueryFindClassroomByRoom')"), isTrue);
      expect(code.contains('ClassroomFreeScreen('), isTrue);
      expect(
        RegExp(r'ClassroomFreeMode\.(byTime|byRoom)').allMatches(code).length,
        2,
      );
    });
  });

  group('节次多选（用户 2026-09-19：「时间我希望可以多选」）', () {
    /// 手工造一间教室：周三 3-5 有课、周五整天空。
    final room = ClassroomOccupancy(
      name: '测试楼301',
      slots: [_slot(weekday: 3, startPeriod: 3, endPeriod: 5, courseName: '数据库')],
    );

    List<String> namesAt({
      required List<int> weekdays,
      required List<(int, int)> blocks,
      ClassroomOccupancy? target,
    }) => freeClassroomsAt(
      rooms: [target ?? room],
      week: 2,
      weekdays: weekdays,
      startPeriod: 1,
      endPeriod: 2,
      periodBlocks: blocks,
    ).map((h) => h.room.name).toList();

    test('多档之间是「都要空」的交集（与星期多选同义）', () {
      expect(
        namesAt(weekdays: const [5], blocks: const [(1, 2)]),
        ['测试楼301'],
        reason: '只选 1-2 节：周五整天空 → 命中',
      );
      expect(
        namesAt(weekdays: const [5], blocks: const [(1, 2), (3, 5)]),
        ['测试楼301'],
        reason: '周五两个档位都空',
      );
      expect(
        namesAt(weekdays: const [3], blocks: const [(1, 2), (3, 5)]),
        isEmpty,
        reason: '周三 3-5 被占 → 不算「都空」',
      );
    });

    test('多档时被占原因取第一个占住它的档位', () {
      final hits = freeClassroomsAt(
        rooms: [room],
        week: 2,
        weekdays: const [3, 5],
        startPeriod: 1,
        endPeriod: 2,
        periodBlocks: const [(1, 2), (3, 5)],
      );
      final hit = hits.single;
      expect(hit.freeWeekdays, [5], reason: '周五两个档位都空');
      expect(hit.busyWeekdays, [3], reason: '周三 3-5 被占');
      expect(hit.busyCourses[3], '数据库');
    });

    test('periodBlocks 为空 → 回落 startPeriod/endPeriod（旧口径逐值不变）', () {
      final byRange = freeClassroomsAt(
        rooms: [room],
        week: 2,
        weekdays: const [5],
        startPeriod: 1,
        endPeriod: 2,
      );
      final byBlocks = freeClassroomsAt(
        rooms: [room],
        week: 2,
        weekdays: const [5],
        startPeriod: 1,
        endPeriod: 2,
        periodBlocks: const [(1, 2)],
      );
      expect(
        byBlocks.map((h) => h.room.name).toList(),
        byRange.map((h) => h.room.name).toList(),
      );
    });

    test('档位文案：单档 / 多档 / 单节 / 空', () {
      expect(classroomPeriodBlocksLabel(const [(1, 2)]), '1-2 节');
      expect(
        classroomPeriodBlocksLabel(const [(1, 2), (3, 5)]),
        '1-2 节 + 3-5 节',
      );
      expect(classroomPeriodBlocksLabel(const [(4, 4)]), '4 节');
      expect(classroomPeriodBlocksLabel(const []), '—');
    });
  });

  group('楼层（用户 2026-09-19：「教室应该分楼层显示」）', () {
    test('房号首位 = 楼层（楼名里的「一/二/三」不算数）', () {
      expect(classroomFloorOf('麦一教1101'), 1);
      expect(classroomFloorOf('麦一教1302'), 1, reason: '楼名「一教」但房号 1302 在 1 楼');
      expect(classroomFloorOf('麦二教2402'), 2);
      expect(classroomFloorOf('蛟三教3101'), 3);
      expect(classroomFloorOf('麦群庐Q202'), 2);
      expect(classroomFloorOf('蛟北区G301'), 3);
      expect(classroomFloorOf('麦萃庐C222'), 2);
    });

    test('房号不足 3 位 / 没有数字 → 楼层未知，不猜', () {
      expect(classroomFloorOf('博雅艺术中心B01'), isNull);
      expect(classroomFloorOf('报告厅'), isNull);
      expect(classroomFloorOf('A01'), isNull);
      expect(classroomFloorOf(''), isNull);
      expect(classroomFloorLabel(null), '其它');
      expect(classroomFloorLabel(3), '3 楼');
    });

    test('楼名前缀取房号之前那一段', () {
      expect(classroomBuildingOf('麦一教1101'), '麦一教');
      expect(classroomBuildingOf('蛟北区G301'), '蛟北区');
      expect(classroomBuildingOf('博雅艺术中心B01'), '博雅艺术中心');
      expect(classroomBuildingOf('报告厅'), '');
    });

    test('分组：楼名升序 → 楼层升序，「其它」排最后，且不丢条目', () {
      const names = [
        '蛟北区G301',
        '麦一教1101',
        '麦一教1302',
        '博雅艺术中心B01',
        '麦一教1102',
        '蛟三教3101',
      ];
      final rooms = [
        for (final n in names) ClassroomInfo(code: n, name: n),
      ];
      final groups = groupClassroomsByFloor(rooms);
      expect(groups.map((g) => g.label).toList(), [
        '博雅艺术中心 · 其它',
        '蛟三教 · 3 楼',
        '蛟北区 · 3 楼',
        '麦一教 · 1 楼',
      ]);
      expect(groups.map((g) => g.count).toList(), [1, 1, 1, 3]);
      expect(
        groups.fold<int>(0, (sum, g) => sum + g.count),
        names.length,
        reason: '每条恰好落进一个组',
      );
    });

    test('命中结果按同一口径分组（楼房 + 楼层）', () {
      final hits = freeClassroomsAt(
        rooms: classroomOccupanciesOf(timetables: _rooms()),
        week: 1,
        weekdays: const [5],
        startPeriod: 1,
        endPeriod: 2,
      );
      final groups = groupFreeHitsByFloor(hits);
      expect(groups, isNotEmpty);
      expect(
        groups.fold<int>(0, (sum, g) => sum + g.count),
        hits.length,
      );
      for (final g in groups) {
        for (final hit in g.items) {
          expect(classroomBuildingOf(hit.room.name), g.building);
          expect(classroomFloorOf(hit.room.name), g.floor);
        }
      }
    });
  });
}
