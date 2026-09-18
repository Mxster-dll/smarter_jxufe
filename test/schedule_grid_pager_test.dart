import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_paged_board.dart';

/// 竖版课表**分页模式**的集成守卫（用户 2026-09-16）：
/// ① 顶部表头只有一份、滑动时不动（从前表头在每一页里 → 会跟着滑/出现多份）；
/// ② 左侧节数列只有一份且会随拖动淡出；
/// ③ 整表仍然铺满屏宽、铺满屏高（用户：「移动端竖排课表高度与屏幕同高」）；
/// ④ 主体（课程格）随手指位移、松手落位。
void main() {
  ScheduleEntry entry() => ScheduleEntry(
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

  DateTime mondayOf(int week) =>
      DateTime(2026, 9, 7).add(Duration(days: (week - 1) * 7));

  Future<void> pumpGrid(
    WidgetTester tester, {
    int week = 2,
    ValueChanged<int>? onWeekChanged,
    int weekCount = 20,
    double height = 740,
    double bottomInset = 0,
  }) async {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    if (bottomInset > 0) {
      // 真机导航栏同时体现在 viewPadding 与 padding 上；`Scaffold` 用 padding
      // 决定 body 的底边（只设 viewPadding 它不会让位，测试会与真机不符）。
      tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
      tester.view.padding = FakeViewPadding(bottom: bottomInset);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleGridView(
            entries: [entry()],
            week: week,
            weekMonday: mondayOf(week),
            showToggle: false,
            pagerWeekCount: weekCount,
            pagerEnabled: true,
            onPagerWeekChanged: onWeekChanged,
            mondayOfWeek: mondayOf,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double leadingOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(find.byKey(const Key('scheduleLeadingColumn')))
      .opacity;

  testWidgets('整表铺满屏宽与屏高（无溢出、无纵向滚动）', (tester) async {
    await pumpGrid(tester);

    final grid = tester.getRect(find.byType(ScheduleGridView));
    expect(grid.left, 0, reason: '手机端左右无边距');
    expect(grid.width, 360);
    expect(grid.height, 740, reason: '竖排课表高度与屏幕同高');
    expect(tester.takeException(), isNull);

    // 真的铺满屏高：**第 12 节的底边就在网格底边**（= 没有纵向滚动）。
    // 旧的最小行高 64 会算出 12×64+34+6 = 808 > 740 → 第 12 节被推到屏幕外
    // （`ScheduleGridView` 自身的 rect 仍是 740，只量它测不出这个问题）。
    final lastPeriod = tester.getRect(
      find.byKey(const Key('schedulePeriodCell-12')),
    );
    expect(
      lastPeriod.bottom,
      closeTo(grid.bottom, 1),
      reason: '12 节应恰好铺满屏高，不该有最小行高把它顶出屏幕',
    );

    // 12 个节次格 + 7 个列头各只有一份（表头 / 节数列都在分页器外面）。
    for (int period = 1; period <= 12; period++) {
      expect(find.byKey(Key('schedulePeriodCell-$period')), findsOneWidget);
    }
    for (final name in const ['周一', '周二', '周三', '周四', '周五', '周六', '周日']) {
      expect(find.text(name), findsOneWidget, reason: '$name 列头只有一份');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拖动中：表头不动、节数列淡出、课程格随手指位移', (tester) async {
    await pumpGrid(tester);

    final headerBefore = tester.getTopLeft(find.text('周一'));
    final leadingBefore = tester.getTopLeft(find.text('1'));
    final rowBefore = tester.getTopLeft(
      find.byKey(const Key('scheduleWeekRow-2')),
    );

    final gesture = await tester.startGesture(const Offset(240, 300));
    // ⚠️ 第一段位移用于「起手」（含 touch slop），必须分两次移动才会跟手位移。
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();

    expect(tester.getTopLeft(find.text('周一')), headerBefore, reason: '表头不动');
    expect(
      tester.getTopLeft(find.text('1')).dx,
      closeTo(leadingBefore.dx, 0.5),
      reason: '节数列淡出但不移动（占位不变）',
    );
    expect(leadingOpacity(tester), SchedulePagedBoard.leadingHiddenOpacity);
    final rowAfter = tester
        .getTopLeft(find.byKey(const Key('scheduleWeekRow-2')))
        .dx;
    expect(
      rowAfter,
      lessThan(rowBefore.dx - 20),
      reason: '主体随手指位移：before=${rowBefore.dx} after=$rowAfter',
    );
    // 主体已越过节数列右边缘 → 节数列那一栏此刻露出的是滑动中的课表
    // （用户 2026-09-16：「节数列隐藏后，原节数列位置可以显示被滑动的课表」）。
    expect(
      tester.getTopLeft(find.byKey(const Key('scheduleWeekRow-2'))).dx,
      lessThan(
        tester.getRect(find.byKey(const Key('schedulePeriodCell-1'))).right,
      ),
      reason: '拖动时课表应滑进原节数列区域（视口 = 整块宽度）',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(leadingOpacity(tester), 1, reason: '松手后节数列出现');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('翻页后：表头与节数列仍在（新周的日期出现在表头）', (tester) async {
    final changed = <int>[];
    await pumpGrid(tester, onWeekChanged: changed.add);

    final gesture = await tester.startGesture(const Offset(240, 300));
    // ⚠️ 位移量按「一页」给：分页视口 = 整块宽度（360），拖 -300×2 = -600 ≈ 1.67 页
    //    → `PageScrollPhysics` 就近落到第 2 页之后（changed = [3, 4]）。
    //    本用例只需证明「翻过一页后表头与节数列还在」，故两段各 -110（≈0.55 页）。
    await gesture.moveBy(const Offset(-110, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-110, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(changed, [3]);
    expect(find.text('周一'), findsOneWidget);
    expect(find.byKey(const Key('schedulePeriodCell-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // 用户 2026-09-16 二轮：「移动端依旧没有适应高度，内容还是超出屏幕范围」。
  // 上一版的下限 52dp 对「内容区偏矮」的机型仍然太高（12×52+34+6 = 664dp）。
  testWidgets('矮屏 + 系统导航栏：12 节恰好铺满拿到的内容区', (tester) async {
    // 视口 520dp、导航栏 48dp。Scaffold 会用 `MediaQuery.padding.bottom` 给 body
    // 让位（`flutter/lib/src/material/scaffold.dart:1087-1093`），但测试环境下
    // FakeViewPadding 的生效时机不稳定（同一用例不同轮次拿到 472 / 520 两种 body 高）
    // → 这里只断言**真正要保证的事**：课表把拿到的内容区铺满、不滚动、不溢出
    // （自适应的行高必须跟着 body 高度走）。
    await pumpGrid(tester, height: 520, bottomInset: 48);

    final grid = tester.getRect(find.byType(ScheduleGridView));
    expect(grid.bottom, inInclusiveRange(472, 520));
    final lastPeriod = tester.getRect(
      find.byKey(const Key('schedulePeriodCell-12')),
    );
    expect(
      lastPeriod.bottom,
      closeTo(grid.bottom, 2),
      reason: '12 节要恰好铺满内容区（不能有最小行高把它顶出屏幕）',
    );
    expect(tester.takeException(), isNull, reason: '单元格内部不许溢出');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('极矮屏（400dp）：行高继续压缩 + 少画内容行，仍不纵向滚动', (tester) async {
    await pumpGrid(tester, height: 400);

    final grid = tester.getRect(find.byType(ScheduleGridView));
    final lastPeriod = tester.getRect(
      find.byKey(const Key('schedulePeriodCell-12')),
    );
    // (400 − 6 − 34) / 12 ≈ 30dp/行 —— 旧下限 52 会算出 664dp 内容高度
    // （`ScheduleGridView` 自身 rect 仍是 400，只有量内容才看得出溢出）。
    expect(lastPeriod.bottom, closeTo(grid.bottom, 2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
