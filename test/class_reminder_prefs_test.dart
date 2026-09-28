/// 课前提醒偏好（开关 + 提前量）的守卫测试。
///
/// 口径：Hive `schedulePrefs` 单 key JSON（与课表显示偏好同一 box、不同 key），
/// 脏存档一律回落默认值并把提前量夹进 1–120 分钟。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/schedule/data/class_reminder_prefs.dart';
import 'package:smarter_jxufe/features/ims/schedule/data/schedule_display_prefs.dart';
import 'package:smarter_jxufe/features/ims/schedule/domain/class_start_reminder.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('class_reminder_prefs');
    Hive.init(dir.path);
    await Hive.openBox<String>(schedulePrefsBoxName);
  });

  setUp(() async {
    final box = await Hive.openBox<String>(schedulePrefsBoxName);
    await box.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('ClassReminderPrefs 模型', () {
    test('默认：开启 + 提前 30 分钟', () {
      const p = ClassReminderPrefs();
      expect(p.enabled, isTrue);
      expect(p.leadMinutes, classReminderDefaultLeadMinutes);
      expect(p.lead, const Duration(minutes: 30));
    });

    test('fromJson 容错：脏类型走默认、越界夹紧', () {
      expect(
        ClassReminderPrefs.fromJson(const <String, dynamic>{}).leadMinutes,
        30,
      );
      // 脏 bool：字符串当成默认 true，不抛
      expect(
        ClassReminderPrefs.fromJson(const {'enabled': 'no'}).enabled,
        isTrue,
      );
      expect(
        ClassReminderPrefs.fromJson(const {'enabled': false}).enabled,
        isFalse,
      );
      // 数字型提前量（JSON 解出来可能是 int / double）
      expect(
        ClassReminderPrefs.fromJson(const {'leadMinutes': 15}).leadMinutes,
        15,
      );
      expect(
        ClassReminderPrefs.fromJson(const {'leadMinutes': 15.0}).leadMinutes,
        15,
      );
      expect(
        ClassReminderPrefs.fromJson(const {'leadMinutes': 0}).leadMinutes,
        classReminderMinLeadMinutes,
      );
      expect(
        ClassReminderPrefs.fromJson(const {'leadMinutes': 9999}).leadMinutes,
        classReminderMaxLeadMinutes,
      );
      expect(
        ClassReminderPrefs.fromJson(const {'leadMinutes': 'junk'}).leadMinutes,
        30,
      );
    });

    test('toJson 往返 + copyWith', () {
      const p = ClassReminderPrefs(enabled: false, leadMinutes: 45);
      final round = ClassReminderPrefs.fromJson(p.toJson());
      expect(round, p);
      expect(p.copyWith(enabled: true).leadMinutes, 45);
      expect(p.copyWith(leadMinutes: 5).enabled, isFalse);
      expect(p.copyWith(), p);
    });
  });

  group('ClassReminderPrefsStore', () {
    test('首次读到空 box → 默认值；save 后另一个实例能读回', () async {
      final store = ClassReminderPrefsStore();
      await store.ensureLoaded();
      expect(store.prefs, const ClassReminderPrefs());

      await store.save(const ClassReminderPrefs(enabled: false, leadMinutes: 10));
      expect(store.prefs.leadMinutes, 10);

      final again = ClassReminderPrefsStore();
      await again.ensureLoaded();
      expect(again.prefs, const ClassReminderPrefs(enabled: false, leadMinutes: 10));
    });

    test('存档损坏（不是 JSON / 不是 Map）→ 回落默认值，不抛', () async {
      final box = await Hive.openBox<String>(schedulePrefsBoxName);
      await box.put(classReminderPrefsKey, '{not json');
      final store = ClassReminderPrefsStore();
      await store.ensureLoaded();
      expect(store.prefs, const ClassReminderPrefs());

      await box.put(classReminderPrefsKey, '"just a string"');
      final store2 = ClassReminderPrefsStore();
      await store2.ensureLoaded();
      expect(store2.prefs, const ClassReminderPrefs());
    });

    test('与课表显示偏好共用 box 但互不覆盖', () async {
      final displayStore = ScheduleDisplayPrefsStore();
      await displayStore.ensureLoaded();
      await displayStore.save(
        const ScheduleDisplayPrefs(showSaturday: false, showSunday: false),
      );

      final reminderStore = ClassReminderPrefsStore();
      await reminderStore.ensureLoaded();
      await reminderStore.save(const ClassReminderPrefs(leadMinutes: 20));

      // 各写各的 key：再读一遍两份都在
      final displayAgain = ScheduleDisplayPrefsStore();
      await displayAgain.ensureLoaded();
      expect(displayAgain.prefs.showSaturday, isFalse);
      expect(displayAgain.prefs.showSunday, isFalse);

      final reminderAgain = ClassReminderPrefsStore();
      await reminderAgain.ensureLoaded();
      expect(reminderAgain.prefs.leadMinutes, 20);

      final box = await Hive.openBox<String>(schedulePrefsBoxName);
      expect(jsonDecode(box.get('display')!), isA<Map<dynamic, dynamic>>());
      expect(box.get(classReminderPrefsKey), isNotNull);
    });

    test('注入 initial 时不读 Hive（isLoaded 立即为真、也不落盘）', () async {
      const injected = ClassReminderPrefs(enabled: false, leadMinutes: 5);
      final store = ClassReminderPrefsStore(initial: injected);
      expect(store.isLoaded, isTrue);
      await store.ensureLoaded();
      expect(store.prefs, injected);

      await store.save(const ClassReminderPrefs(enabled: false, leadMinutes: 15));
      expect(store.prefs.leadMinutes, 15);
      final box = await Hive.openBox<String>(schedulePrefsBoxName);
      expect(box.get(classReminderPrefsKey), isNull, reason: '注入实例不落盘');
    });

    test('相同值 save 是空操作（不重复通知监听者）', () async {
      final store = ClassReminderPrefsStore(initial: const ClassReminderPrefs());
      var notified = 0;
      store.addListener(() => notified++);
      await store.save(const ClassReminderPrefs());
      expect(notified, 0);
    });

    test('落盘值能被新 store 读到（Hive 往返）', () async {
      final store = ClassReminderPrefsStore();
      await store.ensureLoaded();
      await store.save(const ClassReminderPrefs(enabled: true, leadMinutes: 60));
      final box = await Hive.openBox<String>(schedulePrefsBoxName);
      final raw = box.get(classReminderPrefsKey);
      expect(raw, isNotNull);
      final decoded = ClassReminderPrefs.fromJson(
        (jsonDecode(raw!) as Map).map((k, v) => MapEntry('$k', v)),
      );
      expect(decoded.leadMinutes, 60);
      expect(decoded.enabled, isTrue);
    });
  });
}
