/// 课表「显示周六 / 显示周日」开关的守卫测试。
///
/// 用户 2026-09-17 要求：「课表加两个设置，是否显示周六、是否显示周日；当周六/周日
/// 有课时，关闭对应显示要弹出确认框提示用户」——偏好按工作区铁律收拢在设置页
/// 「课表」节。本文件覆盖：可见天推导、该学期某天课程数、偏好落盘、两视图按可见天
/// 渲染、设置页渲染与确认框文案，以及「视图不得再硬编码 7 天」的源码守卫。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/schedule_display_prefs.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_time.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/reschedule.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_display_days.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/schedule_entry.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_grid_view.dart';
import 'package:smarter_jxufe/features/ims/schedule/presentation/schedule_horizontal_view.dart';
import 'package:smarter_jxufe/features/settings/domain/settings_section.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';

/// 一条课（默认周一第 1-2 节，1-16 周）。
ScheduleEntry _entry({
  String courseCode = 'C1',
  String courseName = '高等数学',
  DayOfWeek day = DayOfWeek.monday,
  int startPeriod = 1,
  int endPeriod = 2,
}) => ScheduleEntry(
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
      startWeek: 1,
      endWeek: 16,
      weekParity: WeekParity.every,
      dayOfWeek: day,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      classroom: '麦三教101',
    ),
  ],
);

/// 把周一的课调到周六 3-4 节（第 2 周起长期生效）。
Reschedule _moveToSaturday() {
  final stamp = DateTime(2026, 9, 7);
  return Reschedule(
    id: 'r1',
    kind: RescheduleKind.move,
    scope: RescheduleScope.recurring,
    week: 2,
    courseCode: 'C1',
    courseName: '高等数学',
    originDay: DayOfWeek.monday,
    originStartPeriod: 1,
    originEndPeriod: 2,
    targetDay: DayOfWeek.saturday,
    targetStartPeriod: 3,
    targetEndPeriod: 4,
    createdAt: stamp,
    updatedAt: stamp,
  );
}

DateTime mondayOf(int week) =>
    DateTime(2026, 9, 7).add(Duration(days: (week - 1) * 7));

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('schedule_display_test').path);
  });

  // ⚠ 刻意不在 tearDownAll 里 `Hive.close()`：设置页那次 widget 测试会由
  // `themeModeStoreProvider` 等发起真实的 `openBox`，在 widget 测试的假异步区里
  // 永远完不成 → `close()` 挂住（实测跑完 147 例后卡在 tearDownAll 十分钟）。
  // 临时目录随进程结束即回收，不需要显式关。

  group('可见天推导', () {
    test('默认整周 7 天，下标 0 = 周一', () {
      expect(scheduleVisibleDays(), [0, 1, 2, 3, 4, 5, 6]);
      expect(scheduleDayNames.length, 7);
      expect(scheduleDayNames.first, '周一');
      expect(scheduleDayNames.last, '周日');
    });

    test('关周六 / 关周日 / 都关', () {
      expect(scheduleVisibleDays(showSaturday: false), [0, 1, 2, 3, 4, 6]);
      expect(scheduleVisibleDays(showSunday: false), [0, 1, 2, 3, 4, 5]);
      expect(scheduleVisibleDays(showSaturday: false, showSunday: false), [
        0,
        1,
        2,
        3,
        4,
      ]);
      expect(scheduleSaturdayIndex, 5);
      expect(scheduleSundayIndex, 6);
    });
  });

  group('该学期某天的课程数（设置页确认框的依据）', () {
    test('按课程名去重，同日多时段只算一门', () {
      final entries = [
        _entry(
          courseCode: 'C1',
          day: DayOfWeek.saturday,
          startPeriod: 1,
          endPeriod: 2,
        ),
        // 同一门课的另一个时段（课程代码相同）→ 仍只算一门。
        _entry(
          courseCode: 'C1',
          day: DayOfWeek.saturday,
          startPeriod: 3,
          endPeriod: 4,
        ),
        _entry(
          courseCode: 'C2',
          courseName: '大学英语',
          day: DayOfWeek.saturday,
          startPeriod: 5,
          endPeriod: 6,
        ),
      ];
      expect(scheduleDayCourseCount(entries, scheduleSaturdayIndex), 2);
      expect(scheduleDayCourseCount(entries, scheduleSundayIndex), 0);
    });

    test('调课搬到周六也要算进去', () {
      final entries = [_entry()];
      expect(scheduleDayCourseCount(entries, scheduleSaturdayIndex), 0);
      expect(
        scheduleDayCourseCount(
          entries,
          scheduleSaturdayIndex,
          reschedules: [_moveToSaturday()],
        ),
        1,
        reason: '调课与课表显示同源，周六确实有课',
      );
    });

    test('越界下标返回 0（不抛异常）', () {
      final entries = [_entry()];
      expect(scheduleDayCourseCount(entries, 9), 0);
      expect(scheduleDayCourseCount(entries, -1), 0);
      expect(scheduleDayCourseCount(const [], 0), 0);
    });
  });

  group('偏好存储', () {
    test('默认都显示 / 显示表格线；copyWith / JSON 往返；脏值回落', () {
      const prefs = ScheduleDisplayPrefs();
      expect(prefs.showSaturday, isTrue);
      expect(prefs.showSunday, isTrue);
      // 表格线默认开 = 改动前的观感（用户 2026-09-17 第 3 条：「我希望课表可以
      // 设置是否显示表格线」——是「可关」而不是「改默认」）。
      expect(prefs.showGridLines, isTrue);
      expect(ScheduleDisplayPrefs.fromJson(const {}), prefs);
      expect(
        ScheduleDisplayPrefs.fromJson(const {
          'showSaturday': false,
          'showSunday': true,
        }),
        const ScheduleDisplayPrefs(showSaturday: false),
      );
      expect(
        ScheduleDisplayPrefs.fromJson(const {
          'showSaturday': 'no',
          'showSunday': null,
        }),
        prefs,
      );
      // 旧存档（没有 showGridLines 键）→ 回落 true，老用户观感不变。
      expect(
        ScheduleDisplayPrefs.fromJson(const {
          'showSaturday': true,
          'showSunday': true,
        }).showGridLines,
        isTrue,
      );
      // 关表格线能往返（toJson → fromJson）
      final offJson = const ScheduleDisplayPrefs(showGridLines: false).toJson();
      expect(offJson['showGridLines'], isFalse);
      expect(
        ScheduleDisplayPrefs.fromJson(offJson),
        const ScheduleDisplayPrefs(showGridLines: false),
      );
      expect(prefs.copyWith(showSunday: false).toJson(), {
        'showSaturday': true,
        'showSunday': false,
        'showGridLines': true,
      });
      expect(
        prefs.copyWith(showGridLines: false),
        isNot(prefs),
        reason: 'showGridLines 必须参与 ==（否则 save 会被同值短路掉）',
      );
    });

    test('save 立即通知并落盘；同值不重复通知', () async {
      final store = ScheduleDisplayPrefsStore(
        initial: const ScheduleDisplayPrefs(),
      );
      var notified = 0;
      store.addListener(() => notified++);

      await store.save(const ScheduleDisplayPrefs(showSaturday: false));
      expect(store.prefs.showSaturday, isFalse);
      expect(notified, 1);

      await store.save(const ScheduleDisplayPrefs(showSaturday: false));
      expect(notified, 1, reason: '同值不应再通知');

      await store.save(
        const ScheduleDisplayPrefs(showSaturday: false, showSunday: false),
      );
      expect(notified, 2);

      // 真落盘（走 Hive box）时可被新实例读回。
      final persistent = ScheduleDisplayPrefsStore();
      await persistent.ensureLoaded();
      await persistent.save(
        const ScheduleDisplayPrefs(showSaturday: false, showSunday: false),
      );
      final again = ScheduleDisplayPrefsStore();
      await again.ensureLoaded();
      expect(again.prefs.showSaturday, isFalse);
      expect(again.prefs.showSunday, isFalse);
    });
  });

  group('表格线开关（用户 2026-09-17 第 3 条）', () {
    Widget harness(Widget child) => MaterialApp(
      theme: appLightTheme,
      home: Scaffold(body: SizedBox(width: 900, height: 900, child: child)),
    );

    /// 收集一棵子树里所有 `BoxDecoration` 的非空 `Border` 宽度之和。
    double lineWidthOf(WidgetTester tester, Finder root) {
      var total = 0.0;
      for (final element in find
          .descendant(of: root, matching: find.byType(Container))
          .evaluate()) {
        final decoration =
            (element.widget as Container).decoration;
        if (decoration is! BoxDecoration) continue;
        final border = decoration.border;
        if (border is! Border) continue;
        for (final side in [border.top, border.right, border.bottom, border.left]) {
          total += side.width;
        }
      }
      return total;
    }

    testWidgets('竖版：默认画线；关掉后分隔线全部消失（语义标记线除外）', (tester) async {
      for (final on in [true, false]) {
        await tester.pumpWidget(
          harness(
            ScheduleGridView(
              entries: [_entry()],
              week: 2,
              weekMonday: mondayOf(2),
              showToggle: false,
              showGridLines: on,
            ),
          ),
        );
        final total = lineWidthOf(tester, find.byType(ScheduleGridView));
        if (on) {
          expect(total, greaterThan(0), reason: '默认必须画表格线');
        } else {
          expect(total, 0, reason: '关掉表格线后仍有 ${total}px 的边框');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('横版：同样的开关', (tester) async {
      for (final on in [true, false]) {
        await tester.pumpWidget(
          harness(
            ScheduleHorizontalView(
              entries: [_entry()],
              week: 2,
              weekMonday: mondayOf(2),
              showToggle: false,
              showGridLines: on,
            ),
          ),
        );
        final total = lineWidthOf(tester, find.byType(ScheduleHorizontalView));
        if (on) {
          expect(total, greaterThan(0));
        } else {
          expect(total, 0, reason: '关掉表格线后仍有 ${total}px 的边框');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('表格线关掉也不影响课格底色与周日 / 周末分区色', (tester) async {
      await tester.pumpWidget(
        harness(
          ScheduleGridView(
            entries: [_entry()],
            week: 2,
            weekMonday: mondayOf(2),
            showToggle: false,
            showGridLines: false,
          ),
        ),
      );
      // 课名还在、课格仍有底色（靠底色而不是线来区分列）
      final name = tester.widget<Text>(find.text('高等数学'));
      expect(name.style?.color, isNotNull);
      final card = tester.widget<Container>(
        find
            .ancestor(of: find.text('高等数学'), matching: find.byType(Container))
            .first,
      );
      expect((card.decoration as BoxDecoration?)?.color, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    test('源码守卫：设置页有开关，且课表页把偏好喂给两个视图', () {
      final settings = File(
        'lib/features/settings/presentation/settings_screen.dart',
      ).readAsStringSync();
      expect(settings.contains('scheduleGridLinesSwitch'), isTrue);
      expect(settings.contains('showGridLines: v'), isTrue);

      final screen = File(
        'lib/features/ims/schedule/presentation/schedule_screen.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'showGridLines:\s*display\.showGridLines').allMatches(screen).length,
        2,
        reason: '竖版与横版两个调用点都要传 showGridLines',
      );
    });
  });

  group('两个视图按可见天渲染', () {
    Widget harness(Widget child) => MaterialApp(
      theme: appLightTheme,
      home: Scaffold(body: SizedBox(width: 360, height: 740, child: child)),
    );

    testWidgets('默认 7 天：周六 / 周日表头都在', (tester) async {
      await tester.pumpWidget(
        harness(
          ScheduleGridView(
            entries: [_entry()],
            week: 2,
            weekMonday: mondayOf(2),
            showToggle: false,
          ),
        ),
      );
      expect(find.text('周六'), findsOneWidget);
      expect(find.text('周日'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('关周六：表头少一列、整表仍铺满屏宽', (tester) async {
      await tester.pumpWidget(
        harness(
          ScheduleGridView(
            entries: [_entry()],
            week: 2,
            weekMonday: mondayOf(2),
            showToggle: false,
            showSaturday: false,
          ),
        ),
      );
      expect(find.text('周六'), findsNothing);
      expect(find.text('周日'), findsOneWidget);
      expect(find.text('周一'), findsOneWidget);
      expect(tester.getRect(find.byType(ScheduleGridView)).width,
          closeTo(360, 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('都关：只剩周一至周五', (tester) async {
      await tester.pumpWidget(
        harness(
          ScheduleGridView(
            entries: [_entry()],
            week: 2,
            weekMonday: mondayOf(2),
            showToggle: false,
            showSaturday: false,
            showSunday: false,
          ),
        ),
      );
      for (final name in const ['周一', '周二', '周三', '周四', '周五']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('周六'), findsNothing);
      expect(find.text('周日'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('横版同样生效（关周日 → 那一行不再出现）', (tester) async {
      await tester.pumpWidget(
        harness(
          ScheduleHorizontalView(
            entries: [_entry()],
            week: 2,
            weekMonday: mondayOf(2),
            showToggle: false,
            showSunday: false,
          ),
        ),
      );
      expect(find.text('周六'), findsOneWidget);
      expect(find.text('周日'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('设置页「课表」节', () {
    // 上面的「偏好存储」组会往同一个 box 写值；这里每个用例前清空，
    // 让初始状态稳定为默认（都显示）。
    setUp(() async {
      final box = await Hive.openBox<String>('schedulePrefs');
      await box.clear();
    });

    Widget app(SettingsSection section) => ProviderScope(
      child: MaterialApp(
        theme: appLightTheme,
        home: SettingsScreen(sections: [section]),
      ),
    );

    testWidgets('只显示本节：标题 = 课表，两个开关与说明都在', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app(SettingsSection.schedule));
      await tester.pumpAndSettle();

      expect(find.text('课表'), findsWidgets, reason: 'AppBar 标题 = 节名');
      expect(find.text('显示周六'), findsOneWidget);
      expect(find.text('显示周日'), findsOneWidget);
      expect(find.textContaining('是否显示周六 / 周日'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('没有缓存课表时不弹确认框，直接切换', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app(SettingsSection.schedule));
      await tester.pumpAndSettle();

      expect(find.textContaining('这一天没有课'), findsWidgets);

      /// 开关当前值（按标题定位到所属 `SwitchListTile`）。
      bool switchOf(String label) => tester
          .widget<SwitchListTile>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(SwitchListTile),
            ),
          )
          .value;

      expect(switchOf('显示周六'), isTrue);
      await tester.tap(find.text('显示周六'));
      await tester.pumpAndSettle();

      expect(find.text('隐藏周六？'), findsNothing, reason: '没有课时不该弹确认框');
      expect(switchOf('显示周六'), isFalse, reason: '无课时直接切换');
      expect(switchOf('显示周日'), isTrue, reason: '只动被点的那一个');
      // 落盘由上面「偏好存储」组用真异步覆盖（widget 测试在假异步区里
      // Hive 的 openBox 完不成，这里只看会话内行为）。
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('源码守卫', () {
    String read(String path) => File(path).readAsStringSync();

    test('两个视图不再硬编码 7 天，列数 / 行数走可见天', () {
      final grid = read(
        'lib/features/ims/schedule/presentation/schedule_grid_view.dart',
      );
      final horizontal = read(
        'lib/features/ims/schedule/presentation/schedule_horizontal_view.dart',
      );
      for (final src in [grid, horizontal]) {
        expect(src.contains('scheduleVisibleDays('), isTrue);
        expect(src.contains('schedule_display_days.dart'), isTrue);
        expect(src.contains('showSaturday'), isTrue);
      }
      expect(
        horizontal.contains('/ dayCount'),
        isTrue,
        reason: '横版行高按可见天数铺满屏高',
      );
    });

    test('课表页把偏好喂给两个视图，并把「课表」节声明给设置按钮', () {
      final screen = read(
        'lib/features/ims/schedule/presentation/schedule_screen.dart',
      );
      expect(screen.contains('scheduleDisplayPrefsStoreProvider'), isTrue);
      expect(screen.contains('showSaturday: display.showSaturday'), isTrue);
      expect(screen.contains('showSunday: display.showSunday'), isTrue);
      expect(screen.contains('SettingsSection.schedule'), isTrue);
    });

    test('设置页的开关读该学期课表缓存（不联网）+ 确认框文案', () {
      final settings = read(
        'lib/features/settings/presentation/settings_screen.dart',
      );
      expect(settings.contains('class _ScheduleDisplayCard'), isTrue);
      expect(settings.contains('scheduleCachedEntriesProvider'), isTrue);
      expect(settings.contains('scheduleDayCourseCount('), isTrue);
      expect(settings.contains('仍然隐藏'), isTrue);
      final section = read(
        'lib/features/settings/domain/settings_section.dart',
      );
      expect(section.contains("schedule('课表')"), isTrue);
    });
  });
}
