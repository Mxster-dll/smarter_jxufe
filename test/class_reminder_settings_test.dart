/// 设置页「上课提醒」卡 + 接线守卫。
///
/// 用户 2026-09-22 需求：「我希望在任何一节课上课前x分钟(x可设置，默认30）到上课前，
/// 移动端显示一个常驻通知，下节课的名称和教室」。
///
/// ⚠ 卡里的 `classReminderPrefsStoreProvider` 用 `initial:` 注入的 store 覆盖，
/// 避免 widget 测试里 await 真实 Hive I/O（会静默挂死到超时，本仓踩过多次）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/design/app_theme.dart';
import 'package:smarter_jxufe/design/settings_section.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/class_reminder_prefs.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/providers/class_reminder_providers.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';
import 'package:smarter_jxufe/features/settings/presentation/widgets/settings_cards.dart';

/// ⚠️ 必须 `Hive.init`：设置页的偏好 store（我的校区 / 课表 / 平台标识 GUID）会在
/// build 期间同步调 `ensureLoaded()`，Hive 没初始化会**同步抛** `HiveError`
/// 把用例打红（`ims_session_card_test.dart` / `settings_entry_test.dart` 同款）。
late Directory _hiveDir;

Widget _app(ClassReminderPrefsStore store) => ProviderScope(
  overrides: [
    classReminderPrefsStoreProvider.overrideWith((ref) => store),
  ],
  child: MaterialApp(
    theme: appLightTheme,
    home: const SettingsScreen(sections: [SettingsSection.classReminder]),
  ),
);

void main() {
  setUpAll(() async {
    _hiveDir = await Directory.systemTemp.createTemp('class_reminder_settings');
    Hive.init(_hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await _hiveDir.delete(recursive: true);
  });
  testWidgets('渲染：开关默认开、提前量显示「提前 30 分钟」、说明写清是 Android 常驻', (tester) async {
    final store = ClassReminderPrefsStore(initial: const ClassReminderPrefs());
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    // 「上课提醒」会出现 3 次：AppBar 标题（只显示本节）+ 节标题 + 卡片标题。
    expect(find.text('上课提醒'), findsWidgets);
    expect(find.byKey(const Key('classReminderSwitch')), findsOneWidget);
    expect(find.byKey(const Key('classReminderLeadRow')), findsOneWidget);
    expect(find.text('提前 30 分钟'), findsOneWidget);
    expect(
      find.textContaining('下节课的课程名与教室'),
      findsOneWidget,
      reason: '说明要讲清通知内容',
    );
    expect(find.textContaining('Android'), findsWidgets);
  });

  testWidgets('关掉开关：偏好落库 + 提示；「提前多久」整行点不动', (tester) async {
    final store = ClassReminderPrefsStore(initial: const ClassReminderPrefs());
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('classReminderSwitch')));
    await tester.pumpAndSettle();

    expect(store.prefs.enabled, isFalse);
    expect(find.text('已关闭上课提醒'), findsOneWidget);

    // 关掉后点「提前多久」不该弹层（整行被 IgnorePointer 挡住）。
    await tester.tap(find.byKey(const Key('classReminderLeadRow')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('classReminderLeadSheet')), findsNothing);

    // 排空 SnackBar 计时器，避免收尾报 pending timer。
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('提前量弹层：7 个选项、当前项有勾、选完立即生效并提示', (tester) async {
    // 弹层比默认 800×600 视口高（本仓的老坑）→ 先把视口开大。
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = ClassReminderPrefsStore(initial: const ClassReminderPrefs());
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('classReminderLeadRow')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('classReminderLeadSheet')), findsOneWidget);
    for (final minutes in const [5, 10, 15, 20, 30, 45, 60]) {
      expect(
        find.byKey(Key('classReminderLead-$minutes')),
        findsOneWidget,
        reason: '应列出提前 $minutes 分钟',
      );
    }
    expect(find.text('提前 1 小时'), findsOneWidget);

    await tester.tap(find.byKey(const Key('classReminderLead-10')));
    await tester.pumpAndSettle();

    expect(store.prefs.leadMinutes, 10);
    expect(store.prefs.enabled, isTrue);
    expect(find.text('提前 10 分钟'), findsOneWidget);
    expect(find.text('已改为提前 10 分钟提醒'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('「发送测试提醒」按钮：点一下会给出排期结果提示', (tester) async {
    final store = ClassReminderPrefsStore(initial: const ClassReminderPrefs());
    await tester.pumpWidget(_app(store));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('classReminderTest')), findsOneWidget);
    await tester.tap(find.byKey(const Key('classReminderTest')));
    await tester.pumpAndSettle();

    // 测试host 上 NotificationService 未必就绪 → 两种文案都含「测试提醒」，只断言这点。
    expect(find.byKey(const Key('classReminderSnack')), findsOneWidget);
    expect(find.textContaining('测试提醒'), findsWidgets);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  group('接线守卫（源码）', () {
    String read(String path) {
      // ⚠ 2026-10-08 第三轮：`settings_cards.dart` 已按类拆成 6 个分册（桶文件 +
      // 5 个 `settings_cards_*.dart`）→ 读桶文件时并上**整族**，否则卡片里的 key /
      // 文案一个都读不到（实测：本文件曾因此红 2 例）。
      final paths = path.endsWith('widgets/settings_cards.dart')
          ? settingsCardsSources()
          : [path];
      return paths
          .map((p) => File(p).readAsStringSync())
          .join('\n')
          .replaceAll('\r\n', '\n');
    }

    test('Android 通知服务：常驻 + 到点自动撤下 + 计时器 + 系统闹钟档 + 逐档降级', () {
      final src = read('lib/shared/services/android_notification_service.dart');
      expect(src.contains('classStartChannelId'), isTrue);
      expect(src.contains("'上课提醒'"), isTrue);
      expect(src.contains('ongoing: true'), isTrue);
      expect(src.contains('timeoutAfter: autoDismissAfter?.inMilliseconds'), isTrue);
      expect(src.contains('usesChronometer: countdown'), isTrue);
      expect(src.contains('canScheduleExactNotifications()'), isTrue);
      expect(
        src.contains('AndroidScheduleMode.alarmClock'),
        isTrue,
        reason: '2026-10-08 起：精确档优先用**系统闹钟**形式注册（setAlarmClock），'
            '国产 ROM 划掉应用后最不容易被丢掉',
      );
      expect(
        src.contains('AndroidScheduleMode.exactAllowWhileIdle'),
        isTrue,
        reason: '系统闹钟档拿不到授权时的次选（Android 14 起默认拒绝精确闹钟）',
      );
      expect(
        src.contains("AndroidScheduleMode.inexactAllowWhileIdle"),
        isTrue,
        reason: '最后一档兜底：绝不因为一档失败就整条不排',
      );
      expect(
        src.contains('Future<List<AndroidScheduleMode>> _scheduleModes'),
        isTrue,
        reason: '档位是一串（逐档 try/catch 降级），不是单个返回值',
      );
      expect(
        src.contains('for (var i = 0; i < modes.length; i++)'),
        isTrue,
        reason: '逐档尝试的循环不能退化掉',
      );
    });

    test('排期同步：常驻形态 + 幂等对账 + 只撤本模块区间', () {
      final src = read('lib/features/ims/schedule/data/class_reminder_sync.dart');
      expect(src.contains('await svc.pendingScheduled()'), isTrue);
      expect(src.contains('classStartScheduleMatches(desired: desired, pending: pending)'), isTrue);
      expect(src.contains('if (classStartIdInRange(p.id)) p.id'), isTrue);
      expect(src.contains('ongoing: true'), isTrue);
      expect(src.contains('autoDismissAfter: r.dismissAfter'), isTrue);
      expect(src.contains('countdown: true'), isTrue);
      expect(src.contains('preferExact: true'), isTrue);
      expect(
        src.contains('if (!Platform.isAndroid) return 0;'),
        isTrue,
        reason: '移动端专属：桌面端不排常驻通知',
      );
      expect(src.contains('if (!prefs.enabled)'), isTrue);
      expect(src.contains('cancelClassStartReminders()'), isTrue);
      expect(
        src.contains('refresh: false'),
        isTrue,
        reason: '回前台不该每次打教务（cache-first）',
      );
    });

    test('驱动挂在小部件同步作用域（首帧 + 回前台）', () {
      final src = read(
        'lib/features/home_widget/presentation/home_widget_sync_scope.dart',
      );
      expect(src.contains('unawaited(_syncClassReminders());'), isTrue);
      expect(src.contains('classReminderSyncProvider).syncNow()'), isTrue);
      expect(src.contains('AppLifecycleState.resumed'), isTrue);
    });

    test('设置页注册了新节，课表页齿轮也能到', () {
      final screen = read('lib/features/settings/presentation/settings_screen.dart');
      expect(screen.contains('section: SettingsSection.classReminder,'), isTrue);
      expect(screen.contains('card: const SettingsClassReminderCard(),'), isTrue);

      final schedule = read(
        'lib/features/ims/schedule/presentation/schedule_screen.dart',
      );
      expect(
        schedule.contains('SettingsSection.classReminder,'),
        isTrue,
        reason: '课表页的齿轮应能直达「上课提醒」节',
      );
    });

    test('枚举与卡片 key 都在（测试与用户可见文案锚点）', () {
      final section = read('lib/design/settings_section.dart');
      expect(section.contains("classReminder('上课提醒')"), isTrue);

      final raw = read(
        'lib/features/settings/presentation/widgets/settings_cards.dart',
      );
      // 负面判据先剥注释：卡片 doc 里逐字引用了「平台门控按 Platform.isAndroid」
      // 这条口径，直接 contains 会把注释判成违规（本仓踩过同款坑）。
      final card = raw
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(card.contains("Key('classReminderSwitch')"), isTrue);
      expect(card.contains("Key('classReminderLeadRow')"), isTrue);
      expect(card.contains("Key('classReminderTest')"), isTrue);
      expect(card.contains('sendTestClassReminder()'), isTrue);
      expect(card.contains('classReminderLeadOptions'), isTrue);
      expect(
        card.contains('syncNow(force: true)'),
        isTrue,
        reason: '改完偏好要立即重排系统通知',
      );
      expect(
        card.contains('Platform.isAndroid'),
        isFalse,
        reason: '平台门控只在 sync 里做，卡片不重复判平台（跳系统设置的门控也在桥里）',
      );
    });

    test('后台保护引导：卡片挂上 + 桥的候选降级链齐全（华为启动管理 → 应用详情 → 电池）', () {
      final card = read(
        'lib/features/settings/presentation/widgets/settings_cards.dart',
      );
      expect(card.contains("Key('classReminderProtectHint')"), isTrue);
      expect(card.contains("Key('classReminderOpenStartup')"), isTrue);
      expect(card.contains("Key('classReminderOpenBattery')"), isTrue);
      expect(
        card.contains('SettingsClassReminderProtectHint('),
        isTrue,
        reason: '引导块由卡片渲染',
      );
      expect(
        card.contains('AppSettingsGuide.isSupported'),
        isTrue,
        reason: '桌面端不显示这套系统设置入口',
      );
      expect(
        card.contains('AppSettingsGuide.openBackgroundSettings()'),
        isTrue,
      );
      expect(card.contains('AppSettingsGuide.openBatterySettings()'), isTrue);

      final bridge = read('lib/core/platform/app_settings.dart');
      expect(
        bridge.contains("MethodChannel(\n    'smarter_jxufe/app_settings',\n  )"),
        isTrue,
        reason: '通道名必须与 AppSettingsBridge.kt 的 CHANNEL 一致',
      );
      expect(bridge.contains("_invoke('openStartupSettings')"), isTrue);
      expect(bridge.contains("_invoke('openAppDetails')"), isTrue);
      expect(bridge.contains("_invoke('openBatteryOptimization')"), isTrue);
      expect(
        bridge.contains('allowAppDetailsFallback'),
        isTrue,
        reason: '原生候选全失败时再用应用详情页兜底',
      );

      final kotlin = read(
        'android/app/src/main/kotlin/com/example/smarter_jxufe/settings/AppSettingsBridge.kt',
      );
      expect(
        kotlin.contains('StartupNormalAppListActivity'),
        isTrue,
        reason: '华为 / 荣耀的「应用启动管理」页是主要落点',
      );
      expect(kotlin.contains('AutoStartManagementActivity'), isTrue);
      expect(
        kotlin.contains('Settings.ACTION_APPLICATION_DETAILS_SETTINGS'),
        isTrue,
        reason: '任何 Android 都有的兜底页',
      );
      expect(
        kotlin.contains('Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS'),
        isTrue,
        reason: '电池优化只用官方设置列表页（避免 REQUEST_IGNORE_BATTERY_OPTIMIZATIONS 政策风险）',
      );
      expect(
        kotlin.contains('intent.resolveActivity('),
        isTrue,
        reason: '每条候选先探存在性再跳，不做品牌判断',
      );
      // 主入口必须挂在组装根，否则通道根本不存在。
      final activity = read(
        'android/app/src/main/kotlin/com/example/smarter_jxufe/MainActivity.kt',
      );
      expect(activity.contains('AppSettingsBridge(this, flutterEngine.dartExecutor.binaryMessenger)'), isTrue);
      expect(activity.contains('appSettingsBridge?.dispose()'), isTrue);
    });
  });

  // 「后台保护」引导块（2026-10-08）：文案随厂商名换一版，两个按钮各自回调。
  // 这是**纯展示组件**，单独 pump 即可验证 —— 卡片里它被 `AppSettingsGuide.isSupported`
  // 包着（Windows/桌面端不显示），所以这里刻意不经过整个设置页。
  group('后台保护引导块', () {
    Future<void> pumpHint(
      WidgetTester tester, {
      String? manufacturer,
      VoidCallback? onStartup,
      VoidCallback? onBattery,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        home: Scaffold(
          body: SettingsClassReminderProtectHint(
            manufacturer: manufacturer,
            onOpenStartup: onStartup ?? () {},
            onOpenBattery: onBattery ?? () {},
          ),
        ),
      ),
    );

    testWidgets('华为机：点名「应用启动管理」+ 讲清两步（开自启动 / 最近任务下拉锁定）', (tester) async {
      await pumpHint(tester, manufacturer: 'HUAWEI');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('classReminderProtectHint')), findsOneWidget);
      expect(find.textContaining('华为 / 荣耀'), findsOneWidget);
      expect(find.textContaining('应用启动管理'), findsWidgets);
      expect(find.textContaining('下拉'), findsOneWidget, reason: '最近任务下拉锁定是华为官方三步之一');
      expect(find.byKey(const Key('classReminderOpenStartup')), findsOneWidget);
      expect(find.byKey(const Key('classReminderOpenBattery')), findsOneWidget);
    });

    testWidgets('其它品牌：走通用文案，不点名华为', (tester) async {
      await pumpHint(tester, manufacturer: 'Xiaomi');
      await tester.pumpAndSettle();

      expect(find.textContaining('华为'), findsNothing);
      expect(find.textContaining('后台保护'), findsWidgets);
      expect(find.byKey(const Key('classReminderOpenStartup')), findsOneWidget);
    });

    testWidgets('取不到厂商名（桌面 / 桥失败）：退回通用文案而不是崩', (tester) async {
      await pumpHint(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('华为'), findsNothing);
      expect(find.byKey(const Key('classReminderProtectHint')), findsOneWidget);
    });

    testWidgets('两个按钮各自触发回调（互不串台）', (tester) async {
      var startup = 0;
      var battery = 0;
      await pumpHint(
        tester,
        manufacturer: 'HONOR',
        onStartup: () => startup++,
        onBattery: () => battery++,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('classReminderOpenStartup')));
      await tester.pumpAndSettle();
      expect(startup, 1);
      expect(battery, 0);

      await tester.tap(find.byKey(const Key('classReminderOpenBattery')));
      await tester.pumpAndSettle();
      expect(startup, 1);
      expect(battery, 1);
    });
  });
}

/// lib/features/settings/presentation/widgets/settings_cards*.dart 全族源码。
///
/// 2026-10-08 第三轮拆分后，卡片实现不在桶文件里了 —— 源码守卫要读整族
/// （与 settings_public_query_card_test.dart 同一口径）。
List<String> settingsCardsSources() => Directory(
  'lib/features/settings/presentation/widgets',
).listSync().whereType<File>().map((f) => f.path).where(
  (p) => p.endsWith('.dart') && p.contains('settings_cards'),
).toList()..sort();
