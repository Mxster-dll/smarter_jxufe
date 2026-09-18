import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/comprehensive_service/domain/volunteer_hours_stats.dart';
import 'package:smarter_jxufe/features/home/presentation/dashboard_panel.dart';
import 'package:smarter_jxufe/features/ims/grades/data/providers/weighted_grade_repository_provider.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';

/// 主页宫格视图的仪表盘版式（用户 2026-09-18 四轮裁定）：
/// ① 去掉「数据一览」「全部服务」两个小标题；
/// ② 其他卡片在左、今日课程在右，**恒为 2 : 1 —— 移动端也不堆叠**；
/// ③ 今日课程**按节次合并成块**（无课格子不画但**按节数占位**），每块只写
///    「名称 + 教室」，相邻两门课若按作息表算出的间隔**超过 1 小时**，
///    中间插一条**贴着后一门课**的分隔线（分隔带 14dp、线 2dp）。
void main() {
  const panelPath = 'lib/features/home/presentation/dashboard_panel.dart';
  const homePath = 'lib/features/home/presentation/home_screen.dart';

  group('源码守卫', () {
    test('两个小标题已删；今日课程 = 合并块 + 大间隔分隔线', () {
      final panel = File(panelPath).readAsStringSync();
      final home = File(homePath).readAsStringSync();

      expect(panel.contains("'数据一览'"), isFalse, reason: '仪表盘小标题已删');
      expect(home.contains("'全部服务'"), isFalse, reason: '宫格小标题已删');
      expect(
        home.contains('_buildSectionHeader'),
        isFalse,
        reason: '小标题删掉后该函数已无调用点，应一并删除（否则 unused_element）',
      );

      expect(
        panel.contains('dashboardSplitBreakpoint'),
        isFalse,
        reason: '用户 2026-09-18 四轮裁定：移动端也要左右 2 : 1，堆叠分支已删',
      );
      expect(
        panel.contains('Expanded(flex: 2, child: metrics)'),
        isTrue,
        reason: '恒为 Row 且左 : 右 ≈ 2 : 1',
      );
      expect(
        panel.contains('dashboardBreakBandHeight'),
        isTrue,
        reason: '分隔带占位高度（四轮裁定「增大分割线的占位高度」）',
      );
      expect(
        panel.contains('dashboardBreakLineGap = 8'),
        isTrue,
        reason: '线到下方课块要留空隙（五轮裁定「分割线距离卡片太近」）',
      );
      expect(
        panel.contains('todayCourseCardNarrowBreakpoint'),
        isTrue,
        reason: '窄栏（手机 2:1 的右栏）要收一档内边距与字号',
      );
      expect(
        panel.contains('static const double todayCourseSlotHeight = 30;'),
        isTrue,
        reason: '块高按节数 × 这个单位',
      );
      expect(panel.contains('todayCourseSlotGap'), isTrue);
      expect(
        panel.contains('dashboardCourseBreakMinutes = 60'),
        isTrue,
        reason: '大间隔阈值 = 1 小时',
      );
      expect(panel.contains("Key('dashTodayCourse-"), isTrue);
      expect(panel.contains("Key('dashTodayBreak-"), isTrue);
      expect(
        panel.contains('currentPeriodTableProvider') &&
            panel.contains('cachedPeriodTableProvider'),
        isTrue,
        reason: '钟点取自作息表（实时优先、缓存/内置兜底）',
      );
      expect(
        panel.contains('todayCourseSlotCount'),
        isFalse,
        reason: '旧的「12 个固定格子」已按用户二轮裁定撤掉（空节不显示）',
      );
      expect(panel.contains("Key('dashRefresh')"), isTrue);
      expect(panel.contains('今天没有课，好好休息吧'), isTrue);
      expect(
        panel.contains("Key('dashTodayTimeline')"),
        isTrue,
        reason: '七轮：时间轴全天占位，最后一门课之后仍留余量（守卫要量它）',
      );
      expect(
        panel.contains('previousEnd == 0'),
        isFalse,
        reason: '旧的「末尾没课就不再占位」已按七轮裁定删除',
      );
      expect(
        panel.contains('dashboardBreakBandHeight - rawGap'),
        isTrue,
        reason: '七轮：空档不足分隔带高时要撑开（两条线几何一致）',
      );
    });
  });

  group('版式：左卡片 / 右今日课程', () {
    testWidgets('宽屏：两栏顶对齐、今日课程在右；课程合并成块、大间隔插分隔线', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(_courses));
      await tester.pump();
      await tester.pump();

      // 4 门课 → 4 块（无课格子不再显示：旧的第 5、6、9、10 节空格子已不存在）。
      for (final period in const [1, 3, 7, 11]) {
        expect(
          find.byKey(Key('dashTodayCourse-$period')),
          findsOneWidget,
          reason: '$period 节开课的那一块',
        );
      }
      expect(find.byKey(const Key('dashTodaySlot-1')), findsNothing);

      // 跨节合并：1-2 节一块，高度 = 2 × 34 - 4 = 64（旧实现是两格各 30）。
      for (final period in const [1, 3, 7, 11]) {
        expect(
          tester.getSize(find.byKey(Key('dashTodayCourse-$period'))).height,
          closeTo(2 * 34 - 4, 0.01),
          reason: '$period 节那块是 2 节合并',
        );
      }

      // ★ 无课格子不显示**但占位**（用户 2026-09-18 三轮裁定）：第 7 节的块必须
      // 正好在第 3 节的块下方 4 个轨道（4 × 34 = 136）处 —— 中间 4~6 节没课，
      // 不画格子却照样把高度留出来。去掉占位时该距离只剩十几像素。
      final top3 = tester
          .getTopLeft(find.byKey(const Key('dashTodayCourse-3')))
          .dy;
      final top7 = tester
          .getTopLeft(find.byKey(const Key('dashTodayCourse-7')))
          .dy;
      final top11 = tester
          .getTopLeft(find.byKey(const Key('dashTodayCourse-11')))
          .dy;
      expect(top7 - top3, closeTo(4 * 34, 0.01), reason: '空节占位');
      expect(top11 - top7, closeTo(4 * 34, 0.01), reason: '空节占位');

      // 教室在课程名称**下面**（同一块内左对齐、y 更大）。
      final nameTop = tester.getTopLeft(find.text('高等数学'));
      final roomTop = tester.getTopLeft(find.text('麦三教101'));
      expect(roomTop.dy, greaterThan(nameTop.dy + 6), reason: '教室在名称下方');
      expect((roomTop.dx - nameTop.dx).abs(), lessThan(2), reason: '同一块内左对齐');

      // 只写名称 + 教室（不再出现节次号），且合并后不重复。
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('麦三教101'), findsOneWidget);
      expect(find.textContaining('节'), findsNothing);

      // 间隔：2 节末 09:35 → 3 节 09:55 = 20 分钟（不画线）；
      // 4 节末 11:30 → 7 节 14:50 = 200 分钟（画线）；
      // 8 节末 16:40 → 11 节 19:30 = 170 分钟（画线）。
      expect(find.byKey(const Key('dashTodayBreak-3')), findsNothing);
      final brk7 = find.byKey(const Key('dashTodayBreak-7'));
      final brk11 = find.byKey(const Key('dashTodayBreak-11'));
      expect(brk7, findsOneWidget);
      expect(brk11, findsOneWidget);
      // 分隔线在空档**下部**、与下方课块留出 dashboardBreakLineGap 的空隙
      // （用户 2026-09-18 四轮「贴着分割线」→ 五轮「距离卡片太近」两次裁定）。
      final bottom3 = tester
          .getBottomLeft(find.byKey(const Key('dashTodayCourse-3')))
          .dy;
      expect(
        tester.getBottomLeft(brk7).dy,
        closeTo(top7 - DashboardPanel.dashboardBreakLineGap, 0.5),
        reason: '线在下一门课上方留出空隙（不贴死）',
      );
      expect(
        tester.getBottomLeft(brk7).dy,
        greaterThan(bottom3 + 20),
        reason: '线仍在空档下部而非正中',
      );
      expect(tester.getSize(brk7).height, DashboardPanel.dashboardBreakLineHeight);
      // 空档高度 = 空节数 × 轨道 + 4（3、4 节有课 → 5、6 节空 = 2 节）。
      expect(top7 - bottom3, closeTo(2 * 34 + 4, 0.01), reason: '空档按空节数');

      // 左卡片 / 右今日课程，顶边对齐，宽度 ≈ 2 : 1。
      final metrics = tester.getTopLeft(find.byKey(const Key('dashMetrics')));
      final today = tester.getTopLeft(find.byKey(const Key('dashTodayCard')));
      expect(today.dx, greaterThan(metrics.dx), reason: '今日课程在右侧');
      expect((today.dy - metrics.dy).abs(), lessThan(2), reason: '两栏顶对齐');

      final metricsSize = tester.getSize(find.byKey(const Key('dashMetrics')));
      final todaySize = tester.getSize(find.byKey(const Key('dashTodayCard')));
      expect(
        todaySize.width + metricsSize.width,
        closeTo(1352 - DashboardPanel.dashboardColumnGap, 1.5),
        reason: '两栏平分面板宽度（减去栏间距，用户 2026-09-18 六轮缩小为 10）',
      );
      expect(
        today.dx - (metrics.dx + metricsSize.width),
        closeTo(DashboardPanel.dashboardColumnGap, 1.5),
        reason: '栏间距就是 dashboardColumnGap',
      );
      expect(
        metricsSize.width / todaySize.width,
        closeTo(2, 0.12),
        reason: '用户 2026-09-18 三轮裁定：左 : 右 ≈ 2 : 1（原为 2 : 3）',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('窄屏（手机）：仍是左右 2 : 1，不堆叠；没有课时只留提示', (tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(const []));
      await tester.pump();
      await tester.pump();

      final metrics = tester.getTopLeft(find.byKey(const Key('dashMetrics')));
      final today = tester.getTopLeft(find.byKey(const Key('dashTodayCard')));
      expect(today.dx, greaterThan(metrics.dx), reason: '手机端也在右侧（不堆叠）');
      expect((today.dy - metrics.dy).abs(), lessThan(2), reason: '两栏顶对齐');
      final metricsSize = tester.getSize(find.byKey(const Key('dashMetrics')));
      final todaySize = tester.getSize(find.byKey(const Key('dashTodayCard')));
      expect(
        metricsSize.width / todaySize.width,
        closeTo(2, 0.15),
        reason: '用户 2026-09-18 四轮裁定：移动端也左右 2 : 1',
      );
      expect(find.text('今天没有课，好好休息吧'), findsOneWidget);
      expect(find.byKey(const Key('dashTodayCourse-1')), findsNothing);
      // 窄栏头部收档后不得溢出（图标盒已隐藏、刷新按钮已收紧）。
      expect(tester.takeException(), isNull);
    });

    testWidgets('空档高度严格按空节数：一节空 ≠ 两节空（用户 2026-09-18 四轮裁定）', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // ① 1-2 节有课、3 节空 → 4-5 节有课（空 1 节）；② 1-2 节有课、3/4 节空 →
      // 5-6 节有课（空 2 节）。两者的空档高度必须差**整整一个轨道**。
      await tester.pumpWidget(
        _app(const [
          TodayCourse(
            courseName: '高等数学',
            startPeriod: 1,
            endPeriod: 2,
            classroom: '麦三教101',
          ),
          TodayCourse(
            courseName: '大学英语',
            startPeriod: 4,
            endPeriod: 5,
            classroom: '麦三教202',
          ),
        ]),
      );
      await tester.pump();
      await tester.pump();
      final oneEmpty =
          tester.getTopLeft(find.byKey(const Key('dashTodayCourse-4'))).dy -
          tester.getBottomLeft(find.byKey(const Key('dashTodayCourse-1'))).dy;

      // 先卸载再挂新的一棵（否则 ProviderScope 会复用旧 container，第二次的
      // 课表 override 不生效 —— 与 week_pager 那轮踩过的坑同源）。
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(const [
          TodayCourse(
            courseName: '高等数学',
            startPeriod: 1,
            endPeriod: 2,
            classroom: '麦三教101',
          ),
          TodayCourse(
            courseName: '大学英语',
            startPeriod: 5,
            endPeriod: 6,
            classroom: '麦三教202',
          ),
        ]),
      );
      await tester.pump();
      await tester.pump();
      final twoEmpty =
          tester.getTopLeft(find.byKey(const Key('dashTodayCourse-5'))).dy -
          tester.getBottomLeft(find.byKey(const Key('dashTodayCourse-1'))).dy;

      expect(oneEmpty, closeTo(1 * 34 + 4, 0.01), reason: '空 1 节');
      expect(twoEmpty, closeTo(2 * 34 + 4, 0.01), reason: '空 2 节');
      expect(
        twoEmpty - oneEmpty,
        closeTo(DashboardPanel.todayCourseTrackHeight, 0.01),
        reason: '每多空一节就多一个轨道 —— 两者绝不相同',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('作息表拿不到时（provider 不可用）：不画分隔线，课程块照常合并', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(_courses, withPeriodTable: false));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('dashTodayCourse-7')), findsOneWidget);
      expect(find.byKey(const Key('dashTodayBreak-7')), findsNothing);
      expect(find.byKey(const Key('dashTodayBreak-11')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('午休式间隔：两块课只隔 4dp（相邻节）也必须画分割线（用户 2026-09-18 六轮）', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 真实场景：第 2 节 09:35 下课 → 第 3 节 14:00 上课（第 5、6 节那种午休），
      // 两块课在时间轴上相邻 ⇒ 视觉空档只有 4dp，旧实现用 `gap >= 14` 挡掉了，
      // 用户看到的就是「两条分割线只显示了一条」。
      await tester.pumpWidget(
        _app(
          const [
            TodayCourse(
              courseName: '高等数学',
              startPeriod: 1,
              endPeriod: 2,
              classroom: '麦三教101',
            ),
            TodayCourse(
              courseName: '大学英语',
              startPeriod: 3,
              endPeriod: 4,
              classroom: '麦三教202',
            ),
          ],
          periods: _noonBreakPeriods,
        ),
      );
      await tester.pump();
      await tester.pump();

      final brk = find.byKey(const Key('dashTodayBreak-3'));
      expect(brk, findsOneWidget, reason: '相邻节之间的长间隔也要画线');
      final lineBottom = tester.getBottomLeft(brk).dy;
      final nextTop = tester
          .getTopLeft(find.byKey(const Key('dashTodayCourse-3')))
          .dy;
      final prevBottom = tester
          .getBottomLeft(find.byKey(const Key('dashTodayCourse-1')))
          .dy;
      // 七轮起：空档不足一条分隔带就**撑开**，两条线的几何完全一致 ——
      // 线下 8dp、线上 4dp 留白，整段 14dp（不再「上下各 1dp」被挤在两块之间）。
      expect(
        nextTop - prevBottom,
        closeTo(DashboardPanel.dashboardBreakBandHeight, 0.01),
        reason: '窄空档撑到分隔带高（后续课块整体下移）',
      );
      expect(
        lineBottom,
        closeTo(nextTop - DashboardPanel.dashboardBreakLineGap, 0.5),
      );
      expect(
        lineBottom -
            DashboardPanel.dashboardBreakLineHeight -
            prevBottom,
        closeTo(
          DashboardPanel.dashboardBreakBandHeight -
              DashboardPanel.dashboardBreakLineHeight -
              DashboardPanel.dashboardBreakLineGap,
          0.5,
        ),
        reason: '线上留白 = 带高 − 线高 − 线下留白 = 4dp',
      );
      expect(lineBottom, greaterThan(prevBottom), reason: '线仍在空档之内');
      expect(
        tester.getSize(brk).height,
        DashboardPanel.dashboardBreakLineHeight,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('两条分隔线几何完全一致 + 最后一门课之后仍留出全天余量（用户 2026-09-18 七轮）', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 复现用户当天的真实课表（周五）：3-5 节、6-7 节、10-11 节。两处大间隔：
      // 5→6 是**午休**（钟点差 100 分钟，但时间轴上只差 4dp）、7→10 空两节（72dp）。
      await tester.pumpWidget(
        _app(
          const [
            TodayCourse(
              courseName: '计算机网络',
              startPeriod: 3,
              endPeriod: 5,
              classroom: '麦三教3503',
            ),
            TodayCourse(
              courseName: 'Linux操作系统',
              startPeriod: 6,
              endPeriod: 7,
              classroom: '数字经济实训大楼S313',
            ),
            TodayCourse(
              courseName: '计算机网络',
              startPeriod: 10,
              endPeriod: 11,
              classroom: '数字经济实训大楼S313',
            ),
          ],
          periods: _eveningPeriods,
        ),
      );
      await tester.pump();
      await tester.pump();

      final brk6 = find.byKey(const Key('dashTodayBreak-6'));
      final brk10 = find.byKey(const Key('dashTodayBreak-10'));
      expect(brk6, findsOneWidget, reason: '午休那条线必须画出来（六轮口径）');
      expect(brk10, findsOneWidget);

      final bottom35 = tester
          .getBottomLeft(find.byKey(const Key('dashTodayCourse-3')))
          .dy;
      final top6 = tester
          .getTopLeft(find.byKey(const Key('dashTodayCourse-6')))
          .dy;
      final bottom67 = tester
          .getBottomLeft(find.byKey(const Key('dashTodayCourse-6')))
          .dy;
      final top10 = tester
          .getTopLeft(find.byKey(const Key('dashTodayCourse-10')))
          .dy;

      // ① 两条线到**下方课块**的距离完全相同（= dashboardBreakLineGap）——
      //    这正是用户报的「第一条距离上下卡片和第二条不一样」。
      expect(
        top6 - tester.getBottomLeft(brk6).dy,
        closeTo(DashboardPanel.dashboardBreakLineGap, 0.5),
      );
      expect(
        top10 - tester.getBottomLeft(brk10).dy,
        closeTo(DashboardPanel.dashboardBreakLineGap, 0.5),
      );
      // ② 线上留白也完全相同（4dp）→ 两条带一模一样（带高 14 已含线高 2，故线底距
      //    带顶 = 14 − 8 = 6，线上留白 = 6 − 2 = 4）。
      expect(
        tester.getBottomLeft(brk6).dy -
            DashboardPanel.dashboardBreakLineHeight -
            bottom35,
        closeTo(
          DashboardPanel.dashboardBreakBandHeight -
              DashboardPanel.dashboardBreakLineHeight -
              DashboardPanel.dashboardBreakLineGap,
          0.5,
        ),
        reason: '午休那条：线上 4dp 留白（带顶正好压在上一门课的下沿）',
      );
      expect(
        tester.getBottomLeft(brk10).dy -
            DashboardPanel.dashboardBreakLineHeight -
            bottom67,
        closeTo(72 - DashboardPanel.dashboardBreakLineHeight - DashboardPanel.dashboardBreakLineGap, 0.5),
        reason: '宽空档那条：线上留白 = 空档 − 线高 − 线下留白（差别只在带上方多出的空节高度）',
      );
      // ③ 窄空档被撑开、宽空档保持「空节数 × 轨道 + 4」。
      expect(top6 - bottom35, closeTo(DashboardPanel.dashboardBreakBandHeight, 0.5));
      expect(top10 - bottom67, closeTo(2 * 34 + 4, 0.5));

      // ④ 全天 12 节都占位：最后一门课（10-11 节）之后仍有一个节次的余量
      //    —— 用户：「今天没有第三节晚课，但是组件里第二节晚课后没有空间了」。
      final timeline = tester.getRect(find.byKey(const Key('dashTodayTimeline')));
      final lastBottom = tester
          .getBottomLeft(find.byKey(const Key('dashTodayCourse-10')))
          .dy;
      expect(
        timeline.height,
        closeTo(12 * 34 - 4 + 10, 0.01),
        reason: '全天高度 + 午休撑开的 10dp',
      );
      expect(
        timeline.bottom - lastBottom,
        closeTo(DashboardPanel.todayCourseTrackHeight, 0.5),
        reason: '最后一门课之后留出一个节次（第 12 节）的空间',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('名称 / 教室放不下就换行（不再省略号，用户 2026-09-18 六轮裁定）', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const longName = '计算机组成原理与系统结构设计基础教程精讲'; // 21 字
      const longRoom = '麦庐园北区第五教学楼三楼302多媒体大教室（东侧）';
      await tester.pumpWidget(
        _app(const [
          TodayCourse(
            courseName: longName,
            startPeriod: 1,
            endPeriod: 3,
            classroom: longRoom,
          ),
        ]),
      );
      await tester.pump();
      await tester.pump();

      final nameText = tester.widget<Text>(find.text(longName));
      final roomText = tester.widget<Text>(find.text(longRoom));
      expect(nameText.maxLines, 2, reason: '合并块给两行');
      expect(roomText.maxLines, 2);
      expect(nameText.overflow, TextOverflow.ellipsis, reason: '仅作极端兜底');
      // 真的换行了：渲染高度 > 单行高度（12.5 × 1.15 = 14.375）。
      expect(
        tester.getSize(find.text(longName)).height,
        greaterThan(12.5 * 1.15 * 1.5),
        reason: '名称渲染成两行而不是被截断',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('单节块（30dp）仍只放一行 —— 换行不给它，避免溢出', (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const longName = '计算机组成原理与系统结构设计基础教程精讲';
      await tester.pumpWidget(
        _app(const [
          TodayCourse(
            courseName: longName,
            startPeriod: 1,
            endPeriod: 1,
            classroom: '麦三教101',
          ),
        ]),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.widget<Text>(find.text(longName)).maxLines, 1);
      expect(tester.takeException(), isNull);
    });
  });
}

const _courses = [
  TodayCourse(
    courseName: '高等数学',
    startPeriod: 1,
    endPeriod: 2,
    classroom: '麦三教101',
  ),
  TodayCourse(
    courseName: '大学英语',
    startPeriod: 3,
    endPeriod: 4,
    classroom: '麦三教202',
  ),
  TodayCourse(
    courseName: '数据结构',
    startPeriod: 7,
    endPeriod: 8,
    classroom: '麦三教305',
  ),
  TodayCourse(
    courseName: '计算机组成原理',
    startPeriod: 11,
    endPeriod: 12,
    classroom: '麦三教401',
  ),
];

/// 测试用作息表（只列今日用到的节次；钟点刻意造出 20 / 200 / 170 分钟三种间隔）。
const _testPeriods = PeriodTable(
  label: '测试作息',
  source: 'builtin',
  periods: [
    ClassPeriod(index: 1, start: '08:00', end: '08:45'),
    ClassPeriod(index: 2, start: '08:50', end: '09:35'),
    ClassPeriod(index: 3, start: '09:55', end: '10:40'),
    ClassPeriod(index: 4, start: '10:45', end: '11:30'),
    ClassPeriod(index: 7, start: '14:50', end: '15:35'),
    ClassPeriod(index: 8, start: '15:55', end: '16:40'),
    ClassPeriod(index: 11, start: '19:30', end: '20:15'),
    ClassPeriod(index: 12, start: '20:20', end: '21:05'),
  ],
);

/// 午休式作息表：第 2 节 09:35 下课 → 第 3 节 14:00 上课（间隔 265 分钟，但两块
/// 课在时间轴上**相邻**，视觉空档只有 4dp）—— 复现用户报的「分割线少了一条」。
const _noonBreakPeriods = PeriodTable(
  label: '午休测试作息',
  source: 'builtin',
  periods: [
    ClassPeriod(index: 1, start: '08:00', end: '08:45'),
    ClassPeriod(index: 2, start: '08:50', end: '09:35'),
    ClassPeriod(index: 3, start: '14:00', end: '14:45'),
    ClassPeriod(index: 4, start: '14:50', end: '15:35'),
  ],
);

/// 晚课日作息（复现用户 2026-09-18 当天的真实课表）：第 5 节 12:20 下课 → 第 6 节
/// 14:00 上课是**午休**（钟点差 100 分钟、时间轴上只差 4dp），第 7 节 15:35 下课 →
/// 第 10 节 19:00 上课空两节（72dp）—— 一天里两条大间隔、两种空档宽度。
const _eveningPeriods = PeriodTable(
  label: '晚课测试作息',
  source: 'builtin',
  periods: [
    ClassPeriod(index: 3, start: '09:55', end: '10:40'),
    ClassPeriod(index: 4, start: '10:45', end: '11:30'),
    ClassPeriod(index: 5, start: '11:35', end: '12:20'),
    ClassPeriod(index: 6, start: '14:00', end: '14:45'),
    ClassPeriod(index: 7, start: '14:50', end: '15:35'),
    ClassPeriod(index: 10, start: '19:00', end: '19:45'),
    ClassPeriod(index: 11, start: '19:50', end: '20:35'),
  ],
);

Widget _app(
  List<TodayCourse> courses, {
  bool withPeriodTable = true,
  PeriodTable? periods,
}) {
  final table = periods ?? _testPeriods;
  return ProviderScope(
    overrides: [
      dashboardTodayCoursesProvider.overrideWith((ref) async => courses),
      dashboardVolunteerHoursProvider.overrideWith(
        (ref) async => volunteerHoursStats(const [], xn: 2026),
      ),
      weightedGradeRankingProvider(1).overrideWith((ref) async => null),
      // 两个作息表 provider 都要 override：面板的取值链是
      // `current.valueOrNull ?? cached.valueOrNull`，首帧 current 还在加载时
      // 就会去读 cached —— 而 cached 会开 Hive box，未 init 时会抛出
      // 「You need to initialize Hive or provide a path to store the box.」
      // 的未处理异步错误把测试打挂。
      currentPeriodTableProvider.overrideWith(
        (ref) async => withPeriodTable ? table : throw StateError('作息表不可用'),
      ),
      cachedPeriodTableProvider.overrideWith(
        (ref) async => withPeriodTable ? table : throw StateError('作息表不可用'),
      ),
    ],
    child: MaterialApp(
      theme: appLightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: DashboardPanel(),
          ),
        ),
      ),
    ),
  );
}
