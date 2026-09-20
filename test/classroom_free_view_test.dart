/// 「找空闲教室」两个结果视图的 widget 测试（纯展示层，喂假数据）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/public_query/domain/classroom_free.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/free_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/public_query/presentation/classroom_free_view.dart';

ClassroomOccupancy _room(String name, {List<ScheduleSlot> slots = const []}) =>
    ClassroomOccupancy(
      code: 'c-$name',
      name: name,
      building: '三教楼',
      kind: '一般教室',
      capacity: 60,
      slots: slots,
    );

ScheduleSlot _slot({
  int weekday = 1,
  int startPeriod = 3,
  int endPeriod = 5,
  int startWeek = 2,
  int endWeek = 17,
  WeekParity parity = WeekParity.every,
  String courseName = '高等数学',
}) => ScheduleSlot(
  weekday: weekday,
  startPeriod: startPeriod,
  endPeriod: endPeriod,
  startWeek: startWeek,
  endWeek: endWeek,
  parity: parity,
  courseName: courseName,
);

/// 胶囊表面（Key 挂在 Tooltip 上，可点的 Material 在它下面第一节）。
Material _pill(WidgetTester tester, String name) => tester.widget<Material>(
  find
      .descendant(
        of: find.byKey(Key('classroomFreeRow-$name')),
        matching: find.byType(Material),
      )
      .first,
);

String _pillTip(WidgetTester tester, String name) =>
    tester.widget<Tooltip>(find.byKey(Key('classroomFreeRow-$name'))).message!;

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1100, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

void main() {
  group('模式 A 清单', () {
    final busy = _room('A301', slots: [_slot()]);
    final free = _room('A302');

    testWidgets('汇总行写清周次 / 星期 / 节次 / 命中数', (tester) async {
      final hits = freeClassroomsAt(
        rooms: [busy, free],
        week: 3,
        weekdays: const [3],
        startPeriod: 1,
        endPeriod: 2,
      );
      await _pump(
        tester,
        ClassroomFreeListView(
          hits: hits,
          totalRooms: 2,
          week: 3,
          weekdays: const [3],
          periodLabel: '1-2 节',
        ),
      );
      final text = tester
          .widget<Text>(find.byKey(const Key('classroomFreeSummary')))
          .data;
      expect(text, '第 3 周 · 周三 · 1-2 节 · 2 间空（共 2 间）');
      expect(find.byKey(const Key('classroomFreeRow-A302')), findsOneWidget);
      // 用户 2026-09-20：教室列表 = 一枚枚**胶囊**（圆角 999），不再是整行按钮。
      for (final name in const ['A301', 'A302']) {
        final surface = _pill(tester, name);
        expect(
          (surface.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(999),
          reason: '$name 必须是胶囊',
        );
        expect(
          surface.color,
          isNot(Colors.transparent),
          reason: '$name 在所选的每一天都空 → 实心胶囊',
        );
      }
      // 原来的「全空」小标与两行说明搬进了悬停：胶囊里只留名字 + 座位数。
      expect(_pillTip(tester, 'A302'), contains('所选的每一天都空'));
      expect(_pillTip(tester, 'A302'), contains('三教楼 · 60 座 · 一般教室'));
      expect(find.text('60 座'), findsNWidgets(2));
    });

    testWidgets('部分空闲的行写明哪几天有课', (tester) async {
      final hits = freeClassroomsAt(
        rooms: [busy, free],
        week: 3,
        weekdays: const [1, 3],
        startPeriod: 3,
        endPeriod: 5,
      );
      await _pump(
        tester,
        ClassroomFreeListView(
          hits: hits,
          totalRooms: 2,
          week: 3,
          weekdays: const [1, 3],
          periodLabel: '3-5 节',
        ),
      );
      expect(
        _pillTip(tester, 'A301'),
        contains('周三 空 · 周一（高等数学）有课'),
        reason: 'A301 周一 3-5 被占、周三空 —— 详情进悬停',
      );
      expect(
        _pill(tester, 'A301').color,
        Colors.transparent,
        reason: '只空了一部分 → 描边胶囊',
      );
      expect(
        _pill(tester, 'A302').color,
        isNot(Colors.transparent),
        reason: '只有 A302 每一天都空 → 实心胶囊',
      );
    });

    testWidgets('没有命中 → 空态文案', (tester) async {
      final hits = freeClassroomsAt(
        rooms: [busy],
        week: 3,
        weekdays: const [1],
        startPeriod: 3,
        endPeriod: 5,
      );
      await _pump(
        tester,
        ClassroomFreeListView(
          hits: hits,
          totalRooms: 1,
          week: 3,
          weekdays: const [1],
          periodLabel: '3-5 节',
        ),
      );
      expect(hits, isEmpty);
      expect(
        tester.widget<Text>(find.byKey(const Key('classroomFreeSummary'))).data,
        '这个时段没有空闲教室',
      );
      expect(find.textContaining('换一个周次或节次'), findsOneWidget);
    });

    testWidgets('点某一行回调出这间教室', (tester) async {
      ClassroomOccupancy? picked;
      final hits = freeClassroomsAt(
        rooms: [free],
        week: 1,
        weekdays: const [1],
        startPeriod: 1,
        endPeriod: 2,
      );
      await _pump(
        tester,
        ClassroomFreeListView(
          hits: hits,
          totalRooms: 1,
          week: 1,
          weekdays: const [1],
          periodLabel: '1-2 节',
          onPick: (r) => picked = r,
        ),
      );
      await tester.tap(find.byKey(const Key('classroomFreeRow-A302')));
      expect(picked?.name, 'A302');
    });

    testWidgets('按楼层分组：每个楼层一块卡，卡内是胶囊流（Wrap）', (tester) async {
      final hits = freeClassroomsAt(
        rooms: [
          _room('麦一教1101'),
          _room('麦一教1102'),
          _room('麦二教2401'),
        ],
        week: 1,
        weekdays: const [1],
        startPeriod: 1,
        endPeriod: 2,
      );
      await _pump(
        tester,
        ClassroomFreeListView(
          hits: hits,
          totalRooms: 3,
          week: 1,
          weekdays: const [1],
          periodLabel: '1-2 节',
        ),
      );
      // 组标题（楼层）按楼房 → 楼层升序，胶囊落在各自组标题**下面**。
      final one = find.byKey(const Key('classroomFloorHeader-麦一教 · 1 楼'));
      final two = find.byKey(const Key('classroomFloorHeader-麦二教 · 2 楼'));
      expect(one, findsOneWidget);
      expect(two, findsOneWidget);
      expect(
        tester.getTopLeft(one).dy,
        lessThan(tester.getTopLeft(two).dy),
        reason: '1 楼在前',
      );
      for (final name in const ['麦一教1101', '麦一教1102']) {
        expect(
          tester.getTopLeft(find.byKey(Key('classroomFreeRow-$name'))).dy,
          greaterThan(tester.getTopLeft(one).dy),
        );
      }
      expect(
        tester.getTopLeft(find.byKey(const Key('classroomFreeRow-麦二教2401'))).dy,
        greaterThan(tester.getTopLeft(two).dy),
      );
      // 胶囊流：每层一个 Wrap（外加汇总卡里没有 Wrap）。
      expect(find.byType(Wrap), findsNWidgets(2));
    });

    testWidgets('超过 maxShown 先折叠，点按钮全展开', (tester) async {
      final rooms = [for (var i = 0; i < 5; i++) _room('B30$i')];
      final hits = freeClassroomsAt(
        rooms: rooms,
        week: 1,
        weekdays: const [1],
        startPeriod: 1,
        endPeriod: 2,
      );
      expect(hits.length, 5);
      await _pump(
        tester,
        ClassroomFreeListView(
          hits: hits,
          totalRooms: 5,
          week: 1,
          weekdays: const [1],
          periodLabel: '1-2 节',
          maxShown: 2,
        ),
      );
      expect(find.byKey(const Key('classroomFreeRow-B300')), findsOneWidget);
      expect(find.byKey(const Key('classroomFreeRow-B302')), findsNothing);
      await tester.tap(find.byKey(const Key('classroomFreeShowAll')));
      await tester.pump();
      expect(find.byKey(const Key('classroomFreeRow-B304')), findsOneWidget);
      expect(find.byKey(const Key('classroomFreeShowAll')), findsNothing);
    });
  });

  group('模式 B 教室空闲视图', () {
    testWidgets('表头写教室名与排课条数，周次胶囊可点', (tester) async {
      var tapped = 0;
      final room = _room('A301', slots: [_slot()]);
      await _pump(
        tester,
        ClassroomRoomFreeView(
          room: room,
          week: 3,
          lastWeek: 5,
          commonWindows: const [
            FreeWindow(weekday: 3, startPeriod: 1, endPeriod: 2, week: 0),
          ],
          onWeekChanged: (w) => tapped = w,
        ),
      );
      expect(find.text('A301'), findsWidgets);
      expect(find.textContaining('本学期 1 条排课安排'), findsOneWidget);
      expect(find.byKey(const Key('classroomRoomWeek-1')), findsOneWidget);
      expect(find.byKey(const Key('classroomRoomWeek-5')), findsOneWidget);
      expect(find.byKey(const Key('classroomRoomWeek-6')), findsNothing);
      await tester.tap(find.byKey(const Key('classroomRoomWeek-5')));
      expect(tapped, 5);
      expect(find.byKey(const Key('classroomRoomCommon')), findsOneWidget);
      expect(find.text('周三 1-2 节'), findsOneWidget);
    });

    testWidgets('整学期没排课 → 说明 + 固定空闲空态', (tester) async {
      await _pump(
        tester,
        const ClassroomRoomFreeView(
          room: ClassroomOccupancy(name: 'A999'),
          week: 1,
          lastWeek: 3,
          commonWindows: [],
        ),
      );
      expect(find.textContaining('整学期都空着'), findsOneWidget);
      expect(find.byKey(const Key('classroomRoomCommonEmpty')), findsOneWidget);
      expect(find.textContaining('周一到周日、1-12 节随时可用'), findsOneWidget);
    });
  });

  group('小件', () {
    test('节次标签：单节不带范围', () {
      expect(
        classroomSlotLabel(
          const FreeWindow(weekday: 5, startPeriod: 5, endPeriod: 5, week: 2),
        ),
        '周五 5 节',
      );
      expect(
        classroomSlotLabel(
          const FreeWindow(weekday: 1, startPeriod: 1, endPeriod: 5, week: 2),
        ),
        '周一 1-5 节',
      );
    });
  });
}
