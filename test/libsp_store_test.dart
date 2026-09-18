// 图书馆订阅词云同步 · 本机存储（Hive）守卫。
//
// 守住三件事：
// - **写入白名单**：云端载荷里出现非白名单 box（例如伪造一份带 `imsAuth` 的载荷），
//   一律不写 —— 同步通道不能变成任意写入口；
// - **不整箱清空**：只覆盖载荷里出现的 key，本机新增的其它 key 保留；
// - **账号隔离**：分数估计/综测走账号级 box，A 账号的数据不会被 B 账号读到；
// - **写坏数据要 fail-closed**：云端的脏字段让真实模型解析失败时，宁可什么都不写。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:smarter_jxufe/features/library_sync/data/libsp_local_store.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('libsp_store_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('偏好读取', () {
    test('只读白名单 box，非白名单（如 imsAuth）一条都不碰', () async {
      await (await Hive.openBox<String>('themePrefs')).put('themeMode', 'dark');
      await (await Hive.openBox<String>('electricityBinding'))
          .put('room', 'B12-305');
      await (await Hive.openBox<String>('imsAuth'))
          .put('JSESSIONID|2000000000', 'secret-session');
      await (await Hive.openBox<String>('wxPlatform')).put('guid', 'abc');

      final store = const HiveLibspLocalStore(account: '2000000000');
      final prefs = await store.readPrefs();
      expect(prefs.keys, containsAll(['themePrefs', 'electricityBinding']));
      expect(prefs.containsKey('imsAuth'), isFalse, reason: '会话令牌绝不上云');
      expect(prefs.containsKey('wxPlatform'), isFalse, reason: '设备标识绝不上云');
      expect(prefs['themePrefs']!['themeMode'], 'dark');
    });
  });

  group('偏好写入（白名单守卫）', () {
    test('非白名单 box 一律不写（云端塞什么都不能落到本机）', () async {
      final store = const HiveLibspLocalStore(account: '2000000000');
      await store.writePrefs({
        'imsAuth': {'JSESSIONID|2000000000': '伪造的会话'},
        'wxPlatform': {'guid': '伪造的 GUID'},
        'auth': {'TGC|2000000000': '伪造的票'},
      });
      // 这三个 box 都不应该被创建 / 写入
      for (final name in ['imsAuth', 'wxPlatform', 'auth']) {
        expect(await Hive.boxExists(name), isFalse, reason: '$name 不该被写入');
      }
    });

    test('只覆盖载荷里出现的 key，本机其它 key 保留', () async {
      final box = await Hive.openBox<String>('homePrefs');
      await box.put('layout', 'grid');
      await box.put('density', 'compact');

      final store = const HiveLibspLocalStore(account: '2000000000');
      await store.writePrefs({
        'homePrefs': {'layout': 'sidebar'},
      });
      expect(box.get('layout'), 'sidebar');
      expect(box.get('density'), 'compact', reason: '不能整箱清空');
    });
  });

  group('账号隔离', () {
    test('分数估计按账号分 box：A 写的 B 读不到', () async {
      final a = const HiveLibspLocalStore(account: '2000000000');
      await a.writeCourses([
        {
          'id': 'uuid-1',
          'name': '计算机网络',
          'courseCode': '1004606732',
          'dailyPercent': 30,
          'credits': 2,
          'parts': <dynamic>[],
          'finalScore': null,
          'note': '',
          'memo': {'text': '', 'images': <dynamic>[]},
          'deadlines': <dynamic>[],
          'createdAt': 1,
        },
      ]);
      expect((await a.readCourses()).length, 1);
      expect((await a.readCourses()).first['name'], '计算机网络');

      final b = const HiveLibspLocalStore(account: '2000000002');
      expect(await b.readCourses(), isEmpty, reason: 'B 账号不该看到 A 的数据');
    });

    test('综测条目按账号分 box 往返', () async {
      final store = const HiveLibspLocalStore(account: '2000000000');
      await store.writeZongceEntries({'manual-2026': '{"tScore":88}'});
      final back = await store.readZongceEntries();
      expect(back['manual-2026'], '{"tScore":88}');
    });
  });

  group('写坏数据 fail-closed', () {
    test('云端脏字段让真实模型解析失败 → 什么都不写、也不抛', () async {
      final store = const HiveLibspLocalStore(account: '2000000000');
      await store.writeCourses([
        {'id': 'ok', 'name': '好数据', 'dailyPercent': 30, 'credits': 1},
      ]);
      // 第二份带脏类型（dailyPercent 是字符串）→ GeCourse.fromJson 会抛
      await store.writeCourses([
        {'id': 'bad', 'name': '脏数据', 'dailyPercent': '三成', 'credits': 1},
      ]);
      final after = await store.readCourses();
      expect(after.length, 1, reason: '失败必须不落盘，保住上一份');
      expect(after.first['name'], '好数据');
    });
  });
}
