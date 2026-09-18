// 图书馆订阅词云同步 · 「从云端恢复」的**本机侧落点**守卫。
//
// 用户实测反馈（2026-09-17）：「目前从云端同步似乎设置不会变」。
// 根因：`HiveLibspLocalStore.writePrefs` 走的是直接 `box.put`，而这一批偏好 store
// （外观 / 校区 / 主页布局 / 校历 / 入馆教育）都是「读一次就存内存」
// （`ensureLoaded()` 幂等缓存），且**没有任何人监听 box** → 恢复写了盘，界面一动不动。
// 修法：每个 store 订阅自己的 box（`lib/core/storage/box_reload_watcher.dart` 的
// `BoxReloadWatcher`），于是任何写入路径（含云同步恢复、以后的导入）都会让内存重读并通知。
//
// 本文件守住两件事：
// 1. **写盘 → 内存**：恢复（或任何外部写入）之后 store 的值与通知都要跟上；
// 2. **不产生副作用**：自己 `save()` 不形成通知回环；`dispose()` 之后收到外部写入
//    既不通知也不炸（Hive 的事件可能晚一拍到达）。
//
// ⚠ 与 `libsp_debounce_test.dart` 同款口径：用**真时钟**的 `test()`（链路含真实 Hive
// 文件 I/O，`testWidgets` 的假异步区里真 I/O 回调永远等不到 → 挂死）；整个文件**一个**
// 临时目录 + 每个测试 `deleteFromDisk()` 清箱（每例各 init 一个目录会让上一个测试打开的
// box 留在 Hive 缓存里、断言串味）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/library_edu/data/tsgxs_prefs.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_local_store.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_controller.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_prefs.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_sync_service.dart';
import 'package:smarter_jxufe/features/school_calendar/data/calendar_prefs.dart';
import 'package:smarter_jxufe/features/school_calendar/domain/calendar_day_mark.dart';
import 'package:smarter_jxufe/features/settings/data/theme_prefs.dart';

import 'libsp_sync_test.dart' show FakeRemote, FakeStore;

/// 等 Hive 的 box 事件派发到监听者（广播流是异步投递的）。
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('libsp_live_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// 走**真实恢复写入路径**（`LibspSyncService.restore` 内部就是调它）。
  Future<void> restorePrefs(Map<String, Map<String, String>> prefs) =>
      const HiveLibspLocalStore(account: 'A').writePrefs(prefs);

  group('恢复写盘 → 内存 store 跟上（用户报的「设置不会变」）', () {
    test('外观（深色模式）', () async {
      final store = ThemeModeStore();
      addTearDown(store.dispose);
      await store.ensureLoaded();
      expect(store.mode, ThemeMode.system, reason: '默认跟随系统');

      var notified = 0;
      store.addListener(() => notified++);
      await restorePrefs({
        'themePrefs': {'themeMode': ThemeMode.dark.name},
      });
      await _settle();

      expect(store.mode, ThemeMode.dark, reason: '恢复写了盘，内存必须跟上');
      expect(notified, 1, reason: '界面要知道它变了');
    });

    test('校区', () async {
      final store = MyCampusStore();
      addTearDown(store.dispose);
      await store.ensureLoaded();
      expect(store.campus, isNull, reason: '默认未设置');

      final target = MyCampus.values.last;
      var notified = 0;
      store.addListener(() => notified++);
      await restorePrefs({
        'myCampusPrefs': {'campus': target.name},
      });
      await _settle();

      expect(store.campus, target);
      expect(notified, 1);
    });

    test('主页布局', () async {
      final store = HomeLayoutStore();
      addTearDown(store.dispose);
      await store.ensureLoaded();
      expect(store.layout, HomeLayout.grid);

      final target = HomeLayout.values.firstWhere(
        (l) => l != HomeLayout.grid,
      );
      var notified = 0;
      store.addListener(() => notified++);
      await restorePrefs({
        'homePrefs': {'homeLayout': target.name},
      });
      await _settle();

      expect(store.layout, target);
      expect(notified, 1);
    });

    test('入馆教育答题模式', () async {
      final store = TsgxsExamPrefsStore();
      addTearDown(store.dispose);
      await store.ensureLoaded();
      expect(store.mode, TsgxsAnswerMode.normal);

      final target = TsgxsAnswerMode.values.firstWhere(
        (m) => m != TsgxsAnswerMode.normal,
      );
      var notified = 0;
      store.addListener(() => notified++);
      await restorePrefs({
        tsgxsPrefsBoxName: {tsgxsAnswerModeKey: target.name},
      });
      await _settle();

      expect(store.mode, target);
      expect(notified, 1);
    });

    test('校历三开关（JSON 单 key）', () async {
      final store = CalendarPrefsStore();
      addTearDown(store.dispose);
      await store.ensureLoaded();
      expect(store.prefs.alwaysShowMilitary, isFalse);

      const target = CalendarDisplayPrefs(
        badgeStyle: CalendarBadgeStyle.cornerTag,
        alwaysShowMilitary: true,
        filterByCategory: false,
      );
      var notified = 0;
      store.addListener(() => notified++);
      await restorePrefs({
        calendarPrefsBoxName: {'display': jsonEncode(target.toJson())},
      });
      await _settle();

      expect(store.prefs, target);
      expect(notified, 1);
    });

    test('五个箱一次恢复（真实载荷形态）→ 五个 store 全部跟上', () async {
      final theme = ThemeModeStore();
      final campus = MyCampusStore();
      final layout = HomeLayoutStore();
      final tsgxs = TsgxsExamPrefsStore();
      final calendar = CalendarPrefsStore();
      for (final store in <ChangeNotifier>[theme, campus, layout, tsgxs, calendar]) {
        addTearDown(store.dispose);
      }
      await Future.wait([
        theme.ensureLoaded(),
        campus.ensureLoaded(),
        layout.ensureLoaded(),
        tsgxs.ensureLoaded(),
        calendar.ensureLoaded(),
      ]);

      final wantCampus = MyCampus.values.last;
      final wantLayout = HomeLayout.values.firstWhere(
        (l) => l != HomeLayout.grid,
      );
      const wantCalendar = CalendarDisplayPrefs(alwaysShowMilitary: true);

      await restorePrefs({
        'themePrefs': {'themeMode': ThemeMode.dark.name},
        'myCampusPrefs': {'campus': wantCampus.name},
        'homePrefs': {'homeLayout': wantLayout.name},
        'schoolCalendarPrefs': {'display': jsonEncode(wantCalendar.toJson())},
        tsgxsPrefsBoxName: {tsgxsAnswerModeKey: TsgxsAnswerMode.backdoor.name},
      });
      await _settle();

      expect(theme.mode, ThemeMode.dark);
      expect(campus.campus, wantCampus);
      expect(layout.layout, wantLayout);
      expect(calendar.prefs, wantCalendar);
      expect(tsgxs.mode, TsgxsAnswerMode.backdoor);
    });

    test('云端值与本机一致 → 不产生多余通知（别让界面白抖一下）', () async {
      final store = ThemeModeStore();
      addTearDown(store.dispose);
      await store.ensureLoaded();

      var notified = 0;
      store.addListener(() => notified++);
      await restorePrefs({
        'themePrefs': {'themeMode': ThemeMode.system.name},
      });
      await _settle();

      expect(store.mode, ThemeMode.system);
      expect(notified, 0);
    });
  });

  group('不产生回环 / 生命周期安全', () {
    test('自己 save() 只通知一次（box 事件回来判等相等 → 不再通知）', () async {
      final store = ThemeModeStore();
      addTearDown(store.dispose);
      await store.ensureLoaded();

      var notified = 0;
      store.addListener(() => notified++);
      await store.save(ThemeMode.dark);
      await _settle();

      expect(store.mode, ThemeMode.dark);
      expect(notified, 1, reason: 'save 自己通知一次就够了，不能被自己的写入再唤一次');
    });

    test('dispose 之后收到外部写入：不通知、不抛异常', () async {
      final store = MyCampusStore();
      await store.ensureLoaded();
      var notified = 0;
      store.addListener(() => notified++);
      store.dispose();

      await restorePrefs({
        'myCampusPrefs': {'campus': MyCampus.values.last.name},
      });
      await _settle();

      expect(notified, 0, reason: '已释放的 store 不能 notifyListeners（会抛断言）');
    });

    test('先写盘后 ensureLoaded：首载就能读到外部写入的值', () async {
      // 极端顺序：恢复发生在 store 首次加载之前（App 刚起、页面还没读偏好）。
      await restorePrefs({
        'themePrefs': {'themeMode': ThemeMode.dark.name},
      });
      final store = ThemeModeStore();
      addTearDown(store.dispose);
      await store.ensureLoaded();
      expect(store.mode, ThemeMode.dark);
    });
  });

  group('控制器：恢复成功后叫醒「把数据读进 State」的页面', () {
    // 造控制器（与 `libsp_debounce_test.dart` 同款：FakeRemote + FakeStore）。
    Future<(LibspSyncController, FakeRemote)> build({
      required void Function() onRestored,
    }) async {
      final prefs = LibspSyncPrefsStore();
      await prefs.ensureLoaded();
      await prefs.setEnabled(true);
      final remote = FakeRemote();
      final controller = LibspSyncController(
        service: () async => LibspSyncService(
          remote: remote,
          store: FakeStore(),
          newId: () => 'test-id',
        ),
        prefs: prefs,
        gate: const LibspSyncGate(),
        account: () => '2000000000',
        clock: () => DateTime(2026, 9, 17, 12),
        debounce: const Duration(milliseconds: 50),
        onRestored: onRestored,
      );
      return (controller, remote);
    }

    test('恢复成功 → onRestored 恰好一次', () async {
      var restored = 0;
      final (controller, _) = await build(onRestored: () => restored++);
      addTearDown(controller.dispose);

      await controller.syncNow(); // 先有一版云端快照
      expect(controller.status, LibspSyncStatus.ok);

      expect(await controller.restoreFromCloud(), isTrue);
      expect(restored, 1);
    });

    test('云端没有快照 → 恢复失败且不叫醒页面', () async {
      var restored = 0;
      final (controller, _) = await build(onRestored: () => restored++);
      addTearDown(controller.dispose);

      expect(await controller.restoreFromCloud(), isFalse);
      expect(controller.status, LibspSyncStatus.failed);
      expect(restored, 0, reason: '什么都没恢复，不该让页面重读');
    });
  });
}
