/// 入馆教育答题模式偏好守卫测试。
///
/// 用户 2026-09-11 裁定:模式切换**只能出现在设置页**,落盘在 Hive
/// `tsgxsPrefs`(key `answerMode`,存 `TsgxsAnswerMode.name`)。本测试锁住
/// 枚举名 ↔ 持久化串的映射(改枚举名会让老用户的偏好丢失/回退,须同步迁移)。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:smarter_jxufe/features/library_edu/data/tsgxs_prefs.dart';
import 'package:smarter_jxufe/features/library_edu/domain/tsgxs_exam.dart';

void main() {
  group('TsgxsAnswerMode.fromName', () {
    test('两个模式的 name 可往返解析', () {
      for (final m in TsgxsAnswerMode.values) {
        expect(TsgxsAnswerMode.fromName(m.name), m);
      }
      expect(TsgxsAnswerMode.fromName('normal'), TsgxsAnswerMode.normal);
      expect(TsgxsAnswerMode.fromName('backdoor'), TsgxsAnswerMode.backdoor);
    });

    test('未知 / 空 / null 一律回退 null(调用方保持默认)', () {
      expect(TsgxsAnswerMode.fromName(null), isNull);
      expect(TsgxsAnswerMode.fromName(''), isNull);
      expect(TsgxsAnswerMode.fromName('BACKDOOR'), isNull);
      expect(TsgxsAnswerMode.fromName('后门模式'), isNull);
    });

    test('模式标签与文案口径未被改动', () {
      expect(TsgxsAnswerMode.normal.label, '公共模式');
      expect(TsgxsAnswerMode.backdoor.label, '后门模式');
      expect(TsgxsAnswerMode.normal.hint, contains('自己作答'));
      expect(TsgxsAnswerMode.backdoor.hint, contains('题库优先'));
    });
  });

  group('TsgxsExamPrefsStore', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('tsgxs_prefs_test');
      Hive.init(dir.path);
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    setUp(() async {
      await Hive.deleteBoxFromDisk(tsgxsPrefsBoxName);
    });

    test('默认公共模式', () {
      final store = TsgxsExamPrefsStore();
      expect(store.mode, TsgxsAnswerMode.normal);
      expect(store.isBackdoor, isFalse);
      store.dispose();
    });

    test('切换模式立即通知并落盘(设置页一改,答题页同帧跟随)', () async {
      final store = TsgxsExamPrefsStore();
      var notified = 0;
      store.addListener(() => notified++);

      await store.save(TsgxsAnswerMode.backdoor);
      expect(store.mode, TsgxsAnswerMode.backdoor);
      expect(store.isBackdoor, isTrue);
      expect(notified, 1);
      expect(
        (await Hive.openBox<String>(tsgxsPrefsBoxName)).get(tsgxsAnswerModeKey),
        'backdoor',
      );

      // 同值不重复通知(避免无谓重建)。
      await store.save(TsgxsAnswerMode.backdoor);
      expect(notified, 1);

      await store.save(TsgxsAnswerMode.normal);
      expect(store.mode, TsgxsAnswerMode.normal);
      expect(notified, 2);
      expect(
        (await Hive.openBox<String>(tsgxsPrefsBoxName)).get(tsgxsAnswerModeKey),
        'normal',
      );
      store.dispose();
    });

    test('新建实例懒加载读回上次选择(重启后仍是后门模式)', () async {
      await TsgxsExamPrefsStore().save(TsgxsAnswerMode.backdoor);

      final restored = TsgxsExamPrefsStore();
      expect(restored.mode, TsgxsAnswerMode.normal, reason: '懒加载前是默认值');
      var notified = 0;
      restored.addListener(() => notified++);
      await restored.ensureLoaded();
      expect(restored.mode, TsgxsAnswerMode.backdoor);
      expect(notified, 1);
      restored.dispose();
    });

    test('box 里是坏值时回退公共模式(旧数据不致崩)', () async {
      final box = await Hive.openBox<String>(tsgxsPrefsBoxName);
      await box.put(tsgxsAnswerModeKey, 'who-knows');

      final store = TsgxsExamPrefsStore();
      await store.ensureLoaded();
      expect(store.mode, TsgxsAnswerMode.normal);
      store.dispose();
    });
  });

  test('box 名与 key 是持久化契约(改了就丢老用户偏好)', () {
    expect(tsgxsPrefsBoxName, 'tsgxsPrefs');
    expect(tsgxsAnswerModeKey, 'answerMode');
  });
}
