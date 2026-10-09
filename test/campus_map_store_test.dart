import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/campus_address/data/campus_map_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_style.dart';

/// 校区地图风格偏好的落盘 / 恢复口径。
///
/// ⚠ **为什么单独一个文件**：这一组要的是**真实异步 IO**，而
/// `test/campus_map_test.dart` 里有 `testWidgets`（widget 绑定会把整个文件
/// 罩在假时钟里）→ 那边的 `await store.ensureLoaded()` 永不返回，
/// 每例各挂 30s 超时（实测踩过）。本文件**没有 `testWidgets`**，纯 `test()`，
/// 真实 IO 正常完成。
///
/// 页面级行为（点按钮立刻变风格、文案跟着改）由 `campus_map_test.dart` 覆盖；
/// 这里只管 store 自己的契约。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = Directory.systemTemp.createTempSync('campus_map_store_test_');
    Hive.init(hiveDir.path);
    await Hive.openBox<String>(campusMapPrefsBoxName);
  });
  tearDownAll(() {
    try {
      hiveDir.deleteSync(recursive: true);
    } catch (_) {
      // 清不掉不影响结论。
    }
  });
  setUp(() async {
    await Hive.box<String>(campusMapPrefsBoxName).clear();
  });

  test('默认跟随主题（键不存在）', () async {
    final store = CampusMapStore();
    await store.ensureLoaded();
    expect(store.style, isNull);
    expect(store.followsTheme, isTrue);
    store.dispose();
  });

  test('★ save 后立刻生效（内存先改），落盘在后台补', () async {
    final store = CampusMapStore();
    await store.ensureLoaded();
    final saving = store.save(CampusMapStyleKind.dark);
    // **不 await 落盘**，值就该已经变了 —— 界面因此「点一下立刻变」。
    expect(store.style, CampusMapStyleKind.dark);
    expect(store.followsTheme, isFalse);
    await saving;
    expect(Hive.box<String>(campusMapPrefsBoxName).get('style'), 'dark');
    store.dispose();
  });

  test('★ 新实例能把落盘的值读回来（同步恢复，不闪旧值）', () async {
    final first = CampusMapStore();
    await first.ensureLoaded();
    await first.save(CampusMapStyleKind.dark);
    first.dispose();

    final second = CampusMapStore();
    await second.ensureLoaded();
    expect(second.style, CampusMapStyleKind.dark);
    second.dispose();
  });

  test('toggle 在两种风格之间来回切', () async {
    final store = CampusMapStore();
    await store.ensureLoaded();
    expect(await store.toggle(CampusMapStyleKind.light),
        CampusMapStyleKind.dark);
    expect(store.style, CampusMapStyleKind.dark);
    expect(await store.toggle(CampusMapStyleKind.dark),
        CampusMapStyleKind.light);
    expect(store.style, CampusMapStyleKind.light);
    store.dispose();
  });

  test('save(null) 恢复跟随主题（删键）', () async {
    final store = CampusMapStore();
    await store.ensureLoaded();
    await store.save(CampusMapStyleKind.dark);
    await store.save(null);
    expect(store.style, isNull);
    expect(store.followsTheme, isTrue);
    expect(Hive.box<String>(campusMapPrefsBoxName).get('style'), isNull);
    store.dispose();
  });

  test('★ 存档里是垃圾值时视作未设置，不抛异常', () async {
    await Hive.box<String>(campusMapPrefsBoxName).put('style', '乱写的值');
    final store = CampusMapStore();
    await store.ensureLoaded();
    expect(store.style, isNull);
    expect(store.followsTheme, isTrue);
    store.dispose();
  });

  test('★ 重复 save 同一个值不重复通知', () async {
    final store = CampusMapStore();
    await store.ensureLoaded();
    var notified = 0;
    store.addListener(() => notified++);
    await store.save(CampusMapStyleKind.light);
    expect(notified, 1);
    await store.save(CampusMapStyleKind.light);
    expect(notified, 1, reason: '值没变就不该再通知（Hive watch 也会走同一条路）');
    store.dispose();
  });

  test('风格枚举：other 双向、fromName 容错', () {
    expect(CampusMapStyleKind.light.other, CampusMapStyleKind.dark);
    expect(CampusMapStyleKind.dark.other, CampusMapStyleKind.light);
    expect(CampusMapStyleKind.fromName('light'), CampusMapStyleKind.light);
    expect(CampusMapStyleKind.fromName('乱写'), isNull);
    expect(CampusMapStyleKind.fromName(null), isNull);
  });
}
