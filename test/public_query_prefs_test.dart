/// 公共查询偏好（`publicQueryPrefs` box，目前只有「默认教学楼」）的守卫测试。
///
/// 模型部分是纯函数；落盘往返用**真实 Hive + 临时目录**（本文件是普通 `test()`，
/// 走真实异步区，不受 `testWidgets` 假异步区里 Hive I/O 永不完成那个坑的影响）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/ims/public_query/data/public_query_prefs.dart';

const _building = PublicQueryBuilding(
  campusCode: '3',
  campusName: '麦庐园校区',
  buildingCode: '35',
  buildingName: '白云楼',
);

void main() {
  group('PublicQueryBuilding', () {
    test('label 三段拼接（校区缺失时只给楼名）', () {
      expect(_building.label, '麦庐园校区 · 白云楼');
      expect(
        const PublicQueryBuilding(
          campusCode: '3',
          campusName: '',
          buildingCode: '35',
          buildingName: '白云楼',
        ).label,
        '白云楼',
      );
    });

    test('楼房码为空 → 视为没设过（isUsable=false）', () {
      const b = PublicQueryBuilding(
        campusCode: '3',
        campusName: '麦庐园校区',
        buildingCode: '  ',
        buildingName: '白云楼',
      );
      expect(b.isUsable, isFalse);
      expect(PublicQueryBuilding.fromJson(b.toJson()), isNull);
    });

    test('fromJson 容错：非 Map / 缺字段 → null；多余字段忽略', () {
      expect(PublicQueryBuilding.fromJson(null), isNull);
      expect(PublicQueryBuilding.fromJson('35'), isNull);
      expect(PublicQueryBuilding.fromJson(const <String, Object?>{}), isNull);
      final parsed = PublicQueryBuilding.fromJson(const <String, Object?>{
        'buildingCode': 35,
        'buildingName': ' 白云楼 ',
        'campusCode': '3',
        'campusName': '麦庐园校区',
        'junk': 1,
      });
      expect(parsed, _building);
    });

    test('值语义相等', () {
      expect(
        PublicQueryBuilding.fromJson(_building.toJson()),
        _building,
      );
      expect(_building.hashCode, PublicQueryBuilding.fromJson(_building.toJson()).hashCode);
    });
  });

  group('PublicQueryPrefs', () {
    test('JSON 往返', () {
      final prefs = const PublicQueryPrefs().copyWith(building: _building);
      expect(prefs.building, _building);
      expect(PublicQueryPrefs.fromJson(prefs.toJson()).building, _building);
    });

    test('容错：非 Map / building 坏 → 一律空偏好', () {
      expect(PublicQueryPrefs.fromJson(null), PublicQueryPrefs.empty);
      expect(PublicQueryPrefs.fromJson('x'), PublicQueryPrefs.empty);
      expect(
        PublicQueryPrefs.fromJson(const <String, Object?>{'building': 'x'}),
        PublicQueryPrefs.empty,
      );
    });

    test('copyWith 清除', () {
      final prefs = const PublicQueryPrefs().copyWith(building: _building);
      expect(prefs.copyWith(clearBuilding: true).building, isNull);
      // 不传参数时保持原值。
      expect(prefs.copyWith().building, _building);
    });
  });

  group('store 落盘（真实 Hive + 临时目录）', () {
    late Directory dir;
    late PublicQueryPrefsStore store;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('pq_prefs_test');
      Hive.init(dir.path);
      store = PublicQueryPrefsStore();
      await store.ensureLoaded();
    });

    tearDown(() async {
      await Hive.close();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // 临时目录清不掉不影响断言。
      }
    });

    test('默认没设过 → null；save 之后能读回；清除后回 null', () async {
      expect(store.defaultBuilding, isNull);

      await store.saveBuilding(_building);
      expect(store.defaultBuilding, _building);

      // 另起一个 store 读同一份存档（模拟重启）。
      final reopened = PublicQueryPrefsStore();
      await reopened.ensureLoaded();
      expect(reopened.defaultBuilding, _building);

      await store.saveBuilding(null);
      expect(store.defaultBuilding, isNull);
      final afterClear = PublicQueryPrefsStore();
      await afterClear.ensureLoaded();
      expect(afterClear.defaultBuilding, isNull);
    });

    test('同值重复保存不重复通知；异值会通知', () async {
      var notified = 0;
      store.addListener(() => notified++);
      await store.saveBuilding(_building);
      await store.saveBuilding(_building);
      expect(notified, 1, reason: '同值直接早退');

      await store.saveBuilding(
        const PublicQueryBuilding(
          campusCode: '1',
          campusName: '蛟桥园校区',
          buildingCode: '32',
          buildingName: '北区综合楼',
        ),
      );
      expect(notified, 2);
      expect(store.defaultBuilding?.buildingCode, '32');
    });

    test('存档是脏 JSON 时回落空偏好（不抛）', () async {
      final box = await Hive.openBox<String>(publicQueryPrefsBoxName);
      await box.put('defaults', '{"building": "not-a-map"}');
      final dirty = PublicQueryPrefsStore();
      await dirty.ensureLoaded();
      expect(dirty.defaultBuilding, isNull);
    });
  });
}
