import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_horizontal_view.dart';

/// 用户 2026-09-16：「我希望在显示节数的格子里显示上课下课的时间，上课时间
/// 显示在节数上方，下课时间在下方」——作息取自教务公开页 SchoolTimetable.jsp
/// （免登录，`PeriodTableRepository`：实时 → 按学期缓存 → 内置兜底）。
///
/// 这里只守卫**渲染口径**（三行的存在、上下位置、缺数据时退回旧样式），
/// 作息表的抓取/解析在 `test/live_session_test.dart` 与
/// `test/public_free_time_test.dart` 已有覆盖。
void main() {
  /// 前两节的真实作息（与 `PeriodTable.builtin` 一致：1 节 08:00-08:45）。
  const table = PeriodTable(
    label: '江西财经大学2026-2027学年第一学期作息时间',
    termCode: '2026-0',
    periods: [
      ClassPeriod(index: 1, start: '08:00', end: '08:45'),
      ClassPeriod(index: 2, start: '08:50', end: '09:35'),
    ],
  );

  /// 一门周一的课，让视图有内容可渲染。
  final entry = ScheduleEntry(
    classCode: '000160-016',
    className: '25计算机2班',
    courseCode: '1004501303',
    courseName: '高等数学',
    totalHours: 48,
    credits: 3.0,
    studyNature: '必修课',
    teacherCode: 'T001',
    teacherName: '张三',
    selectionStatus: '已选',
    isCrossMajor: false,
    hasTextbook: true,
    classTimes: const [
      ClassTime(
        dayOfWeek: DayOfWeek.monday,
        startPeriod: 1,
        endPeriod: 2,
        startWeek: 2,
        endWeek: 17,
        weekParity: WeekParity.every,
        classroom: '麦三教3213',
      ),
    ],
  );

  Future<void> pumpGrid(WidgetTester tester, {PeriodTable? periods}) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleGridView(
            entries: [entry],
            periods: periods,
            showToggle: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpHorizontal(
    WidgetTester tester, {
    PeriodTable? periods,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleHorizontalView(
            entries: [entry],
            periods: periods,
            showToggle: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('竖版课表节次格', () {
    testWidgets('上课时间贴格子上端、下课时间贴下端，节数居中', (tester) async {
      await pumpGrid(tester, periods: table);

      expect(find.text('08:00'), findsOneWidget, reason: '第 1 节的上课时间');
      expect(find.text('08:45'), findsOneWidget, reason: '第 1 节的下课时间');
      expect(find.text('08:50'), findsOneWidget, reason: '第 2 节的上课时间');
      expect(find.text('09:35'), findsOneWidget, reason: '第 2 节的下课时间');

      // 用户 2026-09-16：「时间显示在格子两端，而不是紧贴节数号」
      // 量**文字矩形边缘**（不是中心）：测试字体行盒很高，用中心会虚高。
      final cell = tester.getRect(
        find.byKey(const Key('schedulePeriodCell-1')),
      );
      final start = tester.getRect(find.text('08:00'));
      final index = tester.getRect(find.text('1'));
      final end = tester.getRect(find.text('08:45'));

      expect(
        start.top - cell.top,
        lessThanOrEqualTo(8),
        reason: '上课时间要贴格子上端（实测 ${start.top - cell.top}）',
      );
      expect(
        cell.bottom - end.bottom,
        lessThanOrEqualTo(8),
        reason: '下课时间要贴格子下端（实测 ${cell.bottom - end.bottom}）',
      );
      expect(start.center.dy, lessThan(index.center.dy), reason: '上课时间在节数上方');
      expect(index.center.dy, lessThan(end.center.dy), reason: '下课时间在节数下方');
      // 节数居中，且与两端时间留出间距（不是三行挤在中间）
      expect(
        (index.center.dy - cell.center.dy).abs(),
        lessThan(4),
        reason: '节数应在格子竖直中点（实测偏差 ${(index.center.dy - cell.center.dy).abs()}）',
      );
      expect(
        index.center.dy - start.center.dy,
        greaterThan(6),
        reason: '别紧贴上课时间',
      );
      expect(
        end.center.dy - index.center.dy,
        greaterThan(6),
        reason: '别紧贴下课时间',
      );
    });

    testWidgets('作息表缺失的节次退回只显示节数（不显示错误时间）', (tester) async {
      await pumpGrid(tester, periods: table);

      expect(find.text('08:00'), findsOneWidget);
      // 第 3 节没有作息 → 只有节数，没有时间文本
      expect(find.text('3'), findsOneWidget);
      expect(find.text('09:55'), findsNothing);
      expect(find.text('10:40'), findsNothing);
    });

    testWidgets('完全不传作息表时与旧样式一致（只有节数）', (tester) async {
      await pumpGrid(tester);

      expect(find.text('08:00'), findsNothing);
      expect(find.text('08:45'), findsNothing);
      for (final p in [1, 2, 3, 12]) {
        expect(find.text('$p'), findsOneWidget);
      }
    });
  });

  group('横版课表节次表头', () {
    testWidgets('表头格里同样是「上课时间 / 节次 / 下课时间」', (tester) async {
      await pumpHorizontal(tester, periods: table);

      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('08:45'), findsOneWidget);
      final start = tester.getCenter(find.text('08:00')).dy;
      final index = tester.getCenter(find.text('1')).dy;
      final end = tester.getCenter(find.text('08:45')).dy;
      expect(start, lessThan(index));
      expect(index, lessThan(end));
    });

    testWidgets('无作息表时表头只有节次', (tester) async {
      await pumpHorizontal(tester);
      expect(find.text('08:00'), findsNothing);
      expect(find.text('08:45'), findsNothing);
    });
  });

  group('12 行底色一致（用户 2026-09-16：「课表第五行的颜色和其他行不一样」）', () {
    /// 取节次格的底色（`Container.decoration` 的 `color`）。
    Color? periodCellColor(WidgetTester tester, int period) {
      final container = tester.widget<Container>(
        find.byKey(Key('schedulePeriodCell-$period')),
      );
      return (container.decoration as BoxDecoration?)?.color;
    }

    testWidgets('节次列第 5 节不再有专属底色', (tester) async {
      await pumpGrid(tester, periods: table);

      final first = periodCellColor(tester, 1);
      for (final period in [2, 3, 4, 5, 6, 11, 12]) {
        expect(
          periodCellColor(tester, period),
          first,
          reason: '第 $period 节格子的底色应与第 1 节一致（从前第 5 节被涂成 grey.shade100）',
        );
      }
      expect(first, isNull, reason: '节次列不带任何底色');
      expect(tester.takeException(), isNull);
    });

    test('源码里不再有第 5 节专属底色（含空格子那一层）', () {
      final src = File(
        'lib/features/ims/schedule/presentation/schedule_grid_view.dart',
      ).readAsStringSync();
      expect(src.contains('period == 5 ? Colors.grey'), isFalse);
      expect(src.contains('isBeforeNoon'), isFalse);
    });
  });
}
