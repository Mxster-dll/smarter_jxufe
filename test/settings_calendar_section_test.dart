import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/school_calendar/data/calendar_prefs.dart';
import 'package:smarter_jxufe/features/school_calendar/data/providers/calendar_prefs_providers.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';

/// 设置页「校历」节 + 「平台标识」节：渲染正确、改动即时落到偏好 store。
///
/// 偏好入口按项目约定统一收拢在 `settings_screen.dart`（校历页只留跳转）。
///
/// ⚠️ 必须 `Hive.init`：设置页的偏好 store（校历 / 我的校区 / 平台标识 GUID）
/// 都会 `Hive.openBox`，未初始化时 `HiveImpl._openBox` 会把错误 complete 到一条
/// 无人监听的 future → zone 级未处理异常直接把测试判失败（2026-09-11 实测）。
void main() {
  late CalendarPrefsStore prefsStore;

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('settings_section_test');
    Hive.init(dir.path);
    await Hive.openBox<String>('schoolCalendarPrefs');
    await Hive.openBox<String>('myCampusPrefs');
    await Hive.openBox<String>('wxPlatform');
  });

  tearDownAll(() async {
    await Hive.close();
  });

  Widget app() {
    prefsStore = CalendarPrefsStore();
    return ProviderScope(
      overrides: [
        myCampusStoreProvider.overrideWith((ref) => MyCampusStore()),
        calendarPrefsStoreProvider.overrideWith((ref) => prefsStore),
        calendarViewerProvider.overrideWith(
          (ref) async =>
              const CalendarViewer(enrollYear: 2026, trainLevel: '本科'),
        ),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    );
  }

  /// 拉高视口：设置页内容超出默认 600px，屏幕外的开关点不到。
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  testWidgets('渲染「校区」「生效范围」「校历」三节', (tester) async {
    await pumpSettings(tester);

    expect(find.text('校区'), findsOneWidget);
    expect(find.text('生效范围'), findsOneWidget);
    expect(find.text('校历'), findsOneWidget);
    expect(find.text('角标风格'), findsOneWidget);
    expect(find.text('非新生也显示军训'), findsOneWidget);
    expect(find.text('按我的培养层次过滤'), findsOneWidget);
    // 学籍条件已带出（军训说明里显示「2026 级 · 本科」）
    expect(find.textContaining('2026 级 · 本科'), findsOneWidget);
  });

  testWidgets('切换角标风格写入偏好 store', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('右上角角标'));
    await tester.pumpAndSettle();
    expect(prefsStore.prefs.badgeStyle, CalendarBadgeStyle.cornerTag);

    await tester.tap(find.text('整格淡色底'));
    await tester.pumpAndSettle();
    expect(prefsStore.prefs.badgeStyle, CalendarBadgeStyle.filledCell);
  });

  testWidgets('两个开关写入偏好 store', (tester) async {
    await pumpSettings(tester);

    expect(prefsStore.prefs.alwaysShowMilitary, isFalse);
    expect(prefsStore.prefs.filterByCategory, isTrue);

    await tester.tap(find.text('非新生也显示军训'));
    await tester.pumpAndSettle();
    expect(prefsStore.prefs.alwaysShowMilitary, isTrue);

    await tester.tap(find.text('按我的培养层次过滤'));
    await tester.pumpAndSettle();
    expect(prefsStore.prefs.filterByCategory, isFalse);
  });

  testWidgets('「平台标识」节渲染（GUID 入口已从首页宫格迁到设置页）', (tester) async {
    await pumpSettings(tester);

    expect(find.text('平台标识'), findsOneWidget);
    expect(find.text('微信平台标识（GUID）'), findsOneWidget);
    // 未配置（测试环境 wxPlatform box 为空）→ 胶囊显示「未配置」+ 按钮「去获取」。
    expect(find.text('未配置'), findsOneWidget);
    expect(find.text('去获取'), findsOneWidget);
    expect(find.textContaining('GUID 由微信授权'), findsOneWidget);
  });
}
