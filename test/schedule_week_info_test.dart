import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_horizontal_view.dart';

/// 用户 2026-09-15 裁定：
/// 「课表里每个课程，只有在『整学期』视图下，才显示周数信息（包括范围与单双周），
///   而在周视图下，就不显示周数信息了」。
///
/// 判定口径 = 视图的 [ScheduleGridView.week] / [ScheduleHorizontalView.week]
/// 是否为 null（null = 整学期模板，非 null = 周视图）。
void main() {
  ScheduleEntry entry({
    String courseCode = 'C1',
    String courseName = '高等数学',
    required WeekParity parity,
    String classroom = '麦三教101',
    DayOfWeek day = DayOfWeek.monday,
    int startPeriod = 1,
    int endPeriod = 2,
    int startWeek = 1,
    int endWeek = 16,
  }) {
    return ScheduleEntry(
      classCode: '$courseCode-01',
      className: '$courseName(01)',
      courseCode: courseCode,
      courseName: courseName,
      totalHours: 48,
      credits: 3,
      studyNature: '必修',
      teacherCode: 'T1',
      teacherName: '张三',
      selectionStatus: '已选',
      isCrossMajor: false,
      hasTextbook: true,
      classTimes: [
        ClassTime(
          startWeek: startWeek,
          endWeek: endWeek,
          weekParity: parity,
          dayOfWeek: day,
          startPeriod: startPeriod,
          endPeriod: endPeriod,
          classroom: classroom,
        ),
      ],
    );
  }

  /// 课程格子里的周次文本（形如 `1-16周`、`1-16周 (单)`），
  /// 刻意不匹配表头的「周一…周日」。
  Finder weekTexts() => find.byWidgetPredicate(
    (w) =>
        w is Text && w.data != null && RegExp(r'^\d+-\d+周').hasMatch(w.data!),
    description: '课程格子里的周次文本',
  );

  Future<void> pumpGrid(
    WidgetTester tester, {
    required int? week,
    required List<ScheduleEntry> entries,
  }) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleGridView(
            entries: entries,
            week: week,
            weekMonday: DateTime(2026, 9, 14),
          ),
        ),
      ),
    );
  }

  Future<void> pumpHorizontal(
    WidgetTester tester, {
    required int? week,
    required List<ScheduleEntry> entries,
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleHorizontalView(
            entries: entries,
            week: week,
            weekMonday: DateTime(2026, 9, 14),
          ),
        ),
      ),
    );
  }

  group('网格视图（竖版）', () {
    testWidgets('整学期视图：显示周次区间', (tester) async {
      await pumpGrid(
        tester,
        week: null,
        entries: [entry(parity: WeekParity.every)],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('1-16周'), findsOneWidget, reason: '整学期视图必须显示周次区间');
    });

    testWidgets('周视图：不显示周次区间', (tester) async {
      await pumpGrid(
        tester,
        week: 2,
        entries: [entry(parity: WeekParity.every)],
      );

      expect(tester.takeException(), isNull);
      expect(weekTexts(), findsNothing, reason: '周视图已按周过滤，不应再出现周次字样');
      // 课程仍照常渲染（教师 / 教室不受影响）
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('麦三教101'), findsOneWidget);
    });

    testWidgets('单双周：整学期显示「(单)」，周视图不显示', (tester) async {
      await pumpGrid(
        tester,
        week: null,
        entries: [entry(parity: WeekParity.odd)],
      );
      expect(find.text('1-16周 (单周)'), findsOneWidget);

      // 第 3 周是单周 → 该课照常出现，但周次与单双周字样都不显示
      await pumpGrid(tester, week: 3, entries: [entry(parity: WeekParity.odd)]);
      expect(weekTexts(), findsNothing);
      expect(find.textContaining('单周'), findsNothing, reason: '周视图不显示单双周');
      expect(find.text('高等数学'), findsOneWidget);
    });

    testWidgets('同格单双周两门课：整学期显示「单/双周: 教室」，周视图只留教室', (tester) async {
      final entries = [
        entry(
          courseCode: 'C1',
          courseName: '高等数学',
          parity: WeekParity.odd,
          classroom: '麦三教101',
        ),
        entry(
          courseCode: 'C2',
          courseName: '大学英语',
          parity: WeekParity.even,
          classroom: '麦三教202',
        ),
      ];

      await pumpGrid(tester, week: null, entries: entries);
      // 首格显示周次区间（含单双周），同格另一门课的行带「单周/双周: 教室」标注
      // （哪一门排在前面由 effectiveClasses 的顺序决定，断言不依赖顺序）。
      expect(
        find.textContaining(RegExp(r'^1-16周 \((单|双)周\)$')),
        findsOneWidget,
        reason: '整学期视图显示周次区间 + 单双周',
      );
      expect(
        find.textContaining(RegExp(r'^(单|双)周: 麦三教\d+$')),
        findsOneWidget,
        reason: '整学期视图下同格另一门课带单双周标注',
      );

      // 第 3 周（单周）：只剩单周的课，且行内不再标注单双周
      await pumpGrid(tester, week: 3, entries: entries);
      expect(weekTexts(), findsNothing);
      expect(
        find.textContaining(RegExp(r'^(单|双)周:')),
        findsNothing,
        reason: '周视图不显示单双周标注',
      );
      expect(find.text('麦三教101'), findsWidgets);
      expect(find.text('麦三教202'), findsNothing, reason: '第 3 周只有单周那门课');
    });
  });

  group('横版视图（整学期专用布局）', () {
    testWidgets('整学期视图：显示周次区间', (tester) async {
      await pumpHorizontal(
        tester,
        week: null,
        entries: [entry(parity: WeekParity.every)],
      );

      expect(tester.takeException(), isNull);
      expect(find.text('1-16周'), findsOneWidget);
    });

    testWidgets('周视图：不显示周次区间', (tester) async {
      // 第 3 周 = 单周，该课照常出现，但周次与单双周字样都不显示
      await pumpHorizontal(
        tester,
        week: 3,
        entries: [entry(parity: WeekParity.odd)],
      );

      expect(tester.takeException(), isNull);
      expect(weekTexts(), findsNothing);
      expect(find.textContaining('单周'), findsNothing);
      expect(find.text('高等数学'), findsOneWidget);
    });
  });

  group('课程教室放不下就换行（用户 2026-09-15 追加）', () {
    /// 「任何时候，课表中的课程教室不能在一行显示时，自动换行」——
    /// 判定 = 教室 `Text.maxLines ≥ 2`（>1 才可能换行；恒 1 就是单行省略）。
    ///
    /// 用 `textContaining`：整学期视图下同格第二门课的教室会带前缀
    /// （`单周: 麦三教101`），精确匹配会找不到。
    int classroomLines(WidgetTester tester, String classroom) =>
        tester.widget<Text>(find.textContaining(classroom).first).maxLines ?? 1;

    testWidgets('网格视图：单节格的教室允许换行（两行）', (tester) async {
      await pumpGrid(
        tester,
        week: 3,
        entries: [
          entry(
            parity: WeekParity.every,
            classroom: '麦庐园第三教学楼101',
            startPeriod: 1,
            endPeriod: 1,
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(
        classroomLines(tester, '麦庐园第三教学楼101'),
        2,
        reason: '放不下时换行，而不是单行省略',
      );
    });

    testWidgets('网格视图：跨节格同样允许换行', (tester) async {
      await pumpGrid(
        tester,
        week: 3,
        entries: [
          entry(
            parity: WeekParity.every,
            classroom: '麦庐园第三教学楼101',
            startPeriod: 1,
            endPeriod: 2,
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(classroomLines(tester, '麦庐园第三教学楼101'), 2);
    });

    testWidgets('网格视图：同格两门课时教室仍限一行（高度留给分隔行与第二门课）', (tester) async {
      await pumpGrid(
        tester,
        week: null,
        entries: [
          entry(
            courseCode: 'C1',
            courseName: '高等数学',
            parity: WeekParity.odd,
            classroom: '麦三教101',
            startPeriod: 1,
            endPeriod: 1,
          ),
          entry(
            courseCode: 'C2',
            courseName: '线性代数',
            parity: WeekParity.even,
            classroom: '麦三教202',
            startPeriod: 1,
            endPeriod: 1,
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(classroomLines(tester, '麦三教101'), 1);
      expect(classroomLines(tester, '麦三教202'), 1);
    });

    testWidgets('横版视图：行高充足时教室允许换行', (tester) async {
      await pumpHorizontal(
        tester,
        week: 3,
        entries: [entry(parity: WeekParity.every, classroom: '麦庐园第三教学楼101')],
      );

      expect(tester.takeException(), isNull);
      expect(classroomLines(tester, '麦庐园第三教学楼101'), 2);
    });
  });
}
