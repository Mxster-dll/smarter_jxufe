/// 首页「今日课程」卡的校历部分（用户 2026-10-08 需求）：
/// 今日事件 + 无课原因 + 假期 / 补课小字 + 调课角标。
///
/// 用户原话：「首页的今日课程，也要显示今日的事件；并且，如果无课，要显示无课的原因
/// （周末 / 暑假 / 寒假 / 国庆假期）这些」。
///
/// ⚠ 本文件**只 pump 今日课程卡本身**（`dashboardTodayCourses(context, ref)`），
/// 不 pump 整个 `DashboardPanel`：那张卡的数据全靠 override 注入，
/// 版式另外由 `test/home_dashboard_layout_test.dart` 守。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/home/data/providers/dashboard_providers.dart';
import 'package:smarter_jxufe/features/home/presentation/dashboard_today_courses.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/live_class_providers.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/period_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule_engine.dart';

TodayCourse _course({
  String name = '高等数学',
  int start = 1,
  int end = 2,
  String classroom = '麦三教101',
  EffectiveMark mark = EffectiveMark.normal,
}) => TodayCourse(
  courseName: name,
  startPeriod: start,
  endPeriod: end,
  classroom: classroom,
  mark: mark,
);

/// 只渲染今日课程卡；[courses] 与 [info] 都直接注入（不碰课表缓存 / Hive / 网络）。
Widget _card({
  List<TodayCourse> courses = const [],
  TodayCalendarInfo info = const TodayCalendarInfo(),
}) => ProviderScope(
  overrides: [
    dashboardTodayCoursesProvider.overrideWith((ref) async => courses),
    dashboardTodayCalendarProvider.overrideWithValue(info),
    // 作息表两个 provider 都要 override：卡片取值链是
    // `current.valueOrNull ?? cached.valueOrNull`，而 cached 会开 Hive box。
    currentPeriodTableProvider.overrideWith((ref) async => PeriodTable.builtin),
    cachedPeriodTableProvider.overrideWith((ref) async => PeriodTable.builtin),
  ],
  child: MaterialApp(
    theme: appLightTheme,
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 700,
        child: Consumer(
          builder: (context, ref, _) => dashboardTodayCourses(context, ref),
        ),
      ),
    ),
  ),
);

void main() {
  group('无课原因', () {
    testWidgets('假期 / 周末 → 「今天没有课 · 国庆节假期」', (tester) async {
      await tester.pumpWidget(
        _card(info: const TodayCalendarInfo(noClassReason: '国庆节假期')),
      );
      await tester.pumpAndSettle();
      expect(find.text('今天没有课 · 国庆节假期'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('说不出原因 → 保留原来那句', (tester) async {
      await tester.pumpWidget(_card());
      await tester.pumpAndSettle();
      expect(find.text('今天没有课，好好休息吧'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('今日事件', () {
    testWidgets('有事件就列出来（哪怕今天有课）', (tester) async {
      await tester.pumpWidget(
        _card(
          courses: [_course()],
          info: const TodayCalendarInfo(
            events: ['国庆节放假', '学生课程结束（当天上课）'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('国庆节放假'), findsOneWidget);
      expect(find.text('学生课程结束（当天上课）'), findsOneWidget);
      expect(find.text('高等数学'), findsOneWidget, reason: '事件不该顶掉课块');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('没有事件就不占位（版式与从前逐像素一致）', (tester) async {
      await tester.pumpWidget(_card(courses: [_course()]));
      await tester.pumpAndSettle();
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.byKey(const Key('dashTodayCourse-1')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('卡头小字与角标', () {
    testWidgets('假期 / 补课日缀在日期后面', (tester) async {
      await tester.pumpWidget(
        _card(info: const TodayCalendarInfo(effectLabel: '补第4周周五')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('· 补第4周周五'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('补课 / 停课角标与课表页同源（`rescheduleBadge`）', (tester) async {
      await tester.pumpWidget(
        _card(
          courses: [
            _course(mark: EffectiveMark.extra, name: '补课课程'),
            _course(mark: EffectiveMark.cancelled, name: '停课课程', start: 3, end: 4),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('补'), findsOneWidget);
      expect(find.text('停'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
