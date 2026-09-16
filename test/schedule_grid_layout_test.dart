import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';

/// 用户 2026-09-15 的课表排版三条要求：
/// 1. 移动端左右无边距；2. 移动端课表适应屏宽（不横向滚动）；
/// 3. 电脑端在一定范围内适应屏宽，范围之外不再拉伸但**居中**。
void main() {
  final entry = ScheduleEntry(
    classCode: 'C1-01',
    className: '高等数学(01)',
    courseCode: 'C1',
    courseName: '高等数学',
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
        startWeek: 1,
        endWeek: 16,
        weekParity: WeekParity.every,
        dayOfWeek: DayOfWeek.monday,
        startPeriod: 1,
        endPeriod: 2,
        classroom: '麦三教101',
      ),
    ],
  );

  Future<void> pumpGrid(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleGridView(
            entries: [entry],
            week: 2,
            weekMonday: DateTime(2026, 9, 14),
          ),
        ),
      ),
    );
  }

  testWidgets('手机竖屏：左右无边距且整表铺满屏宽（无横向滚动）', (tester) async {
    await pumpGrid(tester, 360);

    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byType(IntrinsicHeight));
    expect(rect.left, 0, reason: '移动端课表不应有左右边距');
    expect(rect.width, closeTo(360, 0.5), reason: '列宽按可用宽度等分 → 整表适应屏宽');
    // 只有一个纵向滚动视图：内容不再横向溢出（否则会多一层横向 SingleChildScrollView）
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('桌面中等宽度：仍适应屏宽（左右各留 12 边距）', (tester) async {
    await pumpGrid(tester, 900);

    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byType(IntrinsicHeight));
    expect(rect.left, 12);
    expect(rect.width, closeTo(876, 0.5));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('桌面超宽：不再拉伸（列宽封顶 160）并整表居中', (tester) async {
    await pumpGrid(tester, 1600);

    expect(tester.takeException(), isNull);
    final rect = tester.getRect(find.byType(IntrinsicHeight));
    const labelWidth = 36.0;
    const maxColWidth = 160.0;
    const contentWidth = labelWidth + 7 * maxColWidth; // 1156
    expect(rect.width, closeTo(contentWidth, 0.5), reason: '超过上限后不再拉伸');
    expect(
      rect.left,
      closeTo((1600 - contentWidth) / 2, 0.5),
      reason: '超宽时整表居中，而不是贴左',
    );
    // 左右留白相等 = 居中
    final rightGap = 1600 - rect.right;
    expect(rect.left, closeTo(rightGap, 0.5));
  });
}
