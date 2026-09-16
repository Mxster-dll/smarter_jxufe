import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_view_mode.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_horizontal_view.dart';

/// 用户 2026-09-15 的六条课表要求里与本文件相关的两条：
/// ① 「横板课表永远适应宽度和高度」；
/// ② 「移动端取消切换横置/竖置按钮，而是适应屏幕是横屏还是竖屏」。
void main() {
  group('视图选型真值表（用户 2026-09-15）', () {
    test('手机端：按横竖屏自动选视图，手动偏好被忽略', () {
      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        expect(
          scheduleViewModeFor(
            platform: platform,
            width: 360,
            height: 740,
            manualHorizontal: false,
          ),
          ScheduleViewMode.grid,
          reason: '$platform 竖屏 → 竖版课表',
        );
        expect(
          scheduleViewModeFor(
            platform: platform,
            width: 740,
            height: 360,
            manualHorizontal: false,
          ),
          ScheduleViewMode.horizontal,
          reason: '$platform 横屏 → 横版课表（不需要按钮）',
        );
        // 手动开关在手机端不再起作用（按钮已取消）
        expect(
          scheduleViewModeFor(
            platform: platform,
            width: 360,
            height: 740,
            manualHorizontal: true,
          ),
          ScheduleViewMode.grid,
        );
      }
    });

    test('桌面端：听手动开关，窗口横竖比例不参与决定', () {
      expect(
        scheduleViewModeFor(
          platform: TargetPlatform.windows,
          width: 1400,
          height: 900,
          manualHorizontal: true,
        ),
        ScheduleViewMode.horizontal,
      );
      expect(
        scheduleViewModeFor(
          platform: TargetPlatform.windows,
          width: 1400,
          height: 900,
          manualHorizontal: false,
        ),
        ScheduleViewMode.grid,
      );
      // 窄高窗口（宽 < 高）也不会自动切横版 —— 桌面端永远听按钮
      expect(
        scheduleViewModeFor(
          platform: TargetPlatform.windows,
          width: 500,
          height: 900,
          manualHorizontal: false,
        ),
        ScheduleViewMode.grid,
      );
    });

    test('排版松紧：手机平台恒收紧；桌面平台按窗口宽度（620 为界）', () {
      expect(
        scheduleCompactLayout(platform: TargetPlatform.android, width: 1400),
        isTrue,
        reason: '手机横屏宽度很大，但仍要按手机排版',
      );
      expect(
        scheduleCompactLayout(platform: TargetPlatform.windows, width: 1400),
        isFalse,
      );
      expect(
        scheduleCompactLayout(platform: TargetPlatform.windows, width: 600),
        isTrue,
      );
      expect(
        scheduleCompactLayout(platform: TargetPlatform.windows, width: 620),
        isFalse,
        reason: '断点处不收紧（与从前 width < 620 的行为一致）',
      );
    });

    test('滑动切周的手势开关', () {
      expect(
        scheduleMobileInput(
          platform: TargetPlatform.android,
          width: 1400,
          height: 400,
        ),
        isTrue,
      );
      expect(
        scheduleMobileInput(
          platform: TargetPlatform.windows,
          width: 1400,
          height: 900,
        ),
        isFalse,
      );
      expect(
        scheduleMobileInput(
          platform: TargetPlatform.windows,
          width: 1400,
          height: 500,
        ),
        isTrue,
        reason: '窄高桌面把窗口也允许滑动切周（短边 < 620）',
      );
    });

    test('断点常量只有一份定义', () {
      expect(ScheduleGridView.compactBreakpoint, scheduleCompactBreakpoint);
      expect(scheduleCompactBreakpoint, 620.0);
    });
  });

  group('横版课表恒适应宽度与高度（用户 2026-09-15）', () {
    Future<void> pumpHorizontal(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleHorizontalView(entries: const [], week: 3),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('12 列铺满宽度、7 行铺满高度，且一个滚动容器都没有', (tester) async {
      for (final size in const [
        Size(1200, 600),
        Size(1600, 900),
        Size(740, 300), // 手机横屏：行高被压到 ~35 也必须装下
        Size(360, 740), // 极窄（手机竖屏不会走横版，但组件自身不能崩）
      ]) {
        await pumpHorizontal(tester, size);
        final shortest = size.width < size.height ? size.width : size.height;
        final compact = shortest < scheduleCompactBreakpoint;
        final hPadding = compact ? 0.0 : 12.0;
        final vPadding = compact ? 6.0 : 12.0;

        expect(
          find.byType(Scrollable),
          findsNothing,
          reason: '$size：横版课表吃满可用空间，不该有滚动容器',
        );
        final content = tester.getSize(find.byType(Column).first);
        expect(
          content.width,
          closeTo(size.width - hPadding * 2, 1.5),
          reason: '$size：内容宽度应等于可用宽度',
        );
        expect(
          content.height,
          closeTo(size.height - vPadding * 2, 1.5),
          reason: '$size：内容高度应等于可用高度',
        );
        expect(tester.takeException(), isNull, reason: '$size：不应溢出');
      }
    });
  });

  group('横/竖切换按钮只在桌面端（用户 2026-09-15）', () {
    testWidgets('showToggle=false 时两个视图都不渲染切换图标', (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final view in const ['grid', 'horizontal']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: view == 'grid'
                  ? const ScheduleGridView(entries: [], showToggle: false)
                  : const ScheduleHorizontalView(
                      entries: [],
                      showToggle: false,
                    ),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byIcon(Icons.view_week),
          findsNothing,
          reason: '$view：手机端没有切换按钮',
        );
        expect(find.byIcon(Icons.view_day), findsNothing, reason: view);
      }
    });

    testWidgets('桌面端（默认）仍渲染切换图标', (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ScheduleGridView(entries: [])),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.view_week), findsOneWidget);
    });
  });
}
