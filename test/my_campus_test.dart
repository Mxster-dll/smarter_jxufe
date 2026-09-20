import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/campus_address/data/my_campus_center.dart';
import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/domain/campus_address.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_screen.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';

void main() {
  group('MyCampus 与上游三套命名的映射（漂移守卫）', () {
    test('每个校区都能在学校地址列表里找到同名条目', () {
      for (final c in MyCampus.values) {
        final info = c.addressInfo;
        expect(info, isNotNull, reason: '${c.label} 在 campuses 中无同名条目');
        expect(info!.name, c.label);
        expect(info.address, isNotEmpty);
        expect(info.postcode, isNotEmpty);
      }
    });

    test('学校地址列表的每个校区都有对应的 MyCampus 取值', () {
      for (final info in campuses) {
        expect(
          MyCampus.values.any((c) => c.matchesAddress(info)),
          isTrue,
          reason: '${info.name} 没有对应的 MyCampus 取值',
        );
      }
    });

    test('每个校区的地图条目名都能在校区地图里找到', () {
      final names = campusMapEntries.map((e) => e.name).toSet();
      for (final c in MyCampus.values) {
        for (final n in c.mapEntryNames) {
          expect(names.contains(n), isTrue, reason: '$n 不在 campusMapEntries 中');
        }
      }
    });

    test('除交通示意图外，校区地图的每个条目都归属且只归属一个校区', () {
      for (final e in campusMapEntries) {
        if (e.name.contains('交通示意图')) continue;
        final owners = MyCampus.values.where((c) => c.matchesMapEntry(e.name));
        expect(
          owners.length,
          1,
          reason: '${e.name} 归属校区数应为 1，实际 ${owners.length}',
        );
      }
    });

    test('电费校区 id 与接口实测一致且互不重复', () {
      expect(MyCampus.jiaoqiao.electricityCampusId, 1);
      expect(MyCampus.mailu.electricityCampusId, 2);
      expect(MyCampus.fenglin.electricityCampusId, 3);
      expect(MyCampus.qingshan.electricityCampusId, isNull,
          reason: 'findCampusList 只返回蛟桥/麦庐/枫林三个校区');
      final ids = [
        for (final c in MyCampus.values)
          if (c.electricityCampusId != null) c.electricityCampusId,
      ];
      expect(ids.toSet().length, ids.length);
    });

    test('蛟桥园 / 麦庐园各含北区与南区两条地图', () {
      expect(MyCampus.jiaoqiao.mapEntryNames, ['蛟桥园北区', '蛟桥园南区']);
      expect(MyCampus.mailu.mapEntryNames, ['麦庐园北区', '麦庐园南区']);
      expect(MyCampus.fenglin.mapEntryNames, ['枫林园校区']);
      expect(MyCampus.qingshan.mapEntryNames, ['青山园校区']);
    });

    test('supportsElectricity 与 electricityCampusId 严格一致', () {
      for (final c in MyCampus.values) {
        expect(c.supportsElectricity, c.electricityCampusId != null);
      }
      expect(MyCampus.qingshan.supportsElectricity, isFalse);
      expect(MyCampus.mailu.supportsElectricity, isTrue);
    });

    test('shortLabel 非空且互不相同', () {
      final shorts = MyCampus.values.map((c) => c.shortLabel).toList();
      expect(shorts.any((s) => s.isEmpty), isFalse);
      expect(shorts.toSet().length, shorts.length);
    });
  });

  group('MyCampus.fromName 容错（存档解析）', () {
    test('全部取值按枚举名与显示名均可往返', () {
      for (final c in MyCampus.values) {
        expect(MyCampus.fromName(c.name), c);
        expect(MyCampus.fromName(c.label), c);
      }
    });

    test('null / 空串 / 未知名一律返回 null（= 未设置），不抛异常', () {
      expect(MyCampus.fromName(null), isNull);
      expect(MyCampus.fromName(''), isNull);
      expect(MyCampus.fromName('不存在校区'), isNull);
      expect(
        MyCampus.fromName('麦庐校区'),
        isNull,
        reason: '电费接口的缩写名不属于统一口径，不应被误解析',
      );
    });
  });

  group('pinMineFirst 稳定置顶', () {
    final list = ['a', 'b', 'c', 'd'];

    test('把匹配项整体提到最前，其余保持原有相对顺序', () {
      expect(
        pinMineFirst(list, (e) => e == 'b' || e == 'c'),
        ['b', 'c', 'a', 'd'],
      );
    });

    test('无匹配时原样返回（返回同一实例，调用可据此跳过重建）', () {
      expect(pinMineFirst(list, (e) => e == 'z'), list);
      expect(identical(pinMineFirst(list, (e) => e == 'z'), list), isTrue);
    });

    test('部分匹配时返回新实例', () {
      expect(identical(pinMineFirst(list, (e) => e == 'b'), list), isFalse);
    });

    test('全部匹配时顺序不变且原样返回', () {
      expect(pinMineFirst(list, (_) => true), list);
    });

    test('空列表与单元素列表直接返回', () {
      expect(pinMineFirst(<String>[], (_) => true), isEmpty);
      expect(pinMineFirst(['a'], (_) => true), ['a']);
    });

    test('置顶校区地图：麦庐园两条一起提到最前，交通示意图后移', () {
      bool isMine(CampusMapEntry e) => MyCampus.mailu.matchesMapEntry(e.name);
      final ordered = pinMineFirst(campusMapEntries, isMine);
      expect(ordered.take(2).map((e) => e.name), ['麦庐园北区', '麦庐园南区']);
      expect(ordered.length, campusMapEntries.length);
      expect(
        ordered.map((e) => e.name).toSet(),
        campusMapEntries.map((e) => e.name).toSet(),
        reason: '置顶不得增删条目',
      );
    });

    test('置顶学校地址：青山园提到最前，其余三校区保持原顺序', () {
      bool isMine(CampusInfo c) => MyCampus.qingshan.matchesAddress(c);
      final ordered = pinMineFirst(campuses, isMine);
      expect(ordered.first.name, '青山园校区');
      expect(
        ordered.skip(1).map((c) => c.name),
        ['蛟桥园校区', '麦庐园校区', '枫林园校区'],
      );
    });
  });

  group('resolveElectricityCampusId 预选优先级', () {
    test('本会话已选最优先（压过绑定与我的校区）', () {
      expect(
        resolveElectricityCampusId(
          currentId: 3,
          boundCampusId: 1,
          mine: MyCampus.mailu,
        ),
        3,
      );
    });

    test('其次沿用已绑定宿舍所在校区（快速换房）', () {
      expect(
        resolveElectricityCampusId(boundCampusId: 1, mine: MyCampus.mailu),
        1,
      );
    });

    test('再次是「我的校区」兜底（首次绑定免手动选校区）', () {
      expect(resolveElectricityCampusId(mine: MyCampus.mailu), 2);
      expect(resolveElectricityCampusId(mine: MyCampus.fenglin), 3);
      expect(resolveElectricityCampusId(mine: MyCampus.jiaoqiao), 1);
    });

    test('青山园无宿舍电费服务 → 不预选', () {
      expect(resolveElectricityCampusId(mine: MyCampus.qingshan), isNull);
      expect(
        resolveElectricityCampusId(boundCampusId: 0, mine: MyCampus.qingshan),
        isNull,
      );
    });

    test('0 / 负数视为无效（绑定记录缺省会写成 0）', () {
      expect(
        resolveElectricityCampusId(
          currentId: 0,
          boundCampusId: 0,
          mine: MyCampus.mailu,
        ),
        2,
      );
      expect(resolveElectricityCampusId(currentId: -1, mine: null), isNull);
    });

    test('全空返回 null（未设置我的校区且无绑定）', () {
      expect(resolveElectricityCampusId(), isNull);
    });
  });

  /// 用户 2026-09-20 原话：「现在『设置』页的校区设置，改成直接用数据中心的数据，
  /// 如果获取失败，再手动设置」；同日追问后裁定**手动优先、数据中心只补空**。
  group('数据中心补空（校区设置接数据中心）', () {
    setUpAll(() async {
      // 照 `settings_calendar_section_test.dart`：偏好 store 会 `Hive.openBox`，
      // 未初始化时错误会 complete 到无人监听的 future → zone 级未处理异常判失败。
      final dir = Directory.systemTemp.createTempSync('my_campus_center_test');
      Hive.init(dir.path);
      await Hive.openBox<String>(myCampusPrefsBoxName);
    });

    setUp(() async {
      await Hive.box<String>(myCampusPrefsBoxName).clear();
    });

    tearDownAll(() async {
      await Hive.close();
    });

    ProviderContainer containerWith(Map<String, String> center) {
      final container = ProviderContainer(
        overrides: [
          dzjBasicInfoProvider.overrideWith((ref) async => center),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// 等数据中心那一份到货，并把补空的**写盘 + Hive 事件**跑完。
    ///
    /// ⚠ 不能只 `await Future.delayed(Duration.zero)`：补空要写 Hive（真 I/O），
    /// 写完还有 `box.watch()` 的事件要再投递几拍 —— 实测一拍不够
    /// （2026-09-20 这里先红过一次：断言时读到的是「写盘写到一半」的状态）。
    Future<void> settle(
      ProviderContainer container, {
      bool Function()? until,
    }) async {
      await container.read(dzjBasicInfoProvider.future);
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (until != null && until()) return;
      }
    }

    test('列名映射：只有认识的名字才认（不认识 / 取不到 → null，宁可让用户手选）', () async {
      final mailu = containerWith({'所属校区': '麦庐园校区'});
      await settle(mailu);
      expect(mailu.read(myCampusHintProvider), MyCampus.mailu);

      final unknown = containerWith({'所属校区': '某某校区'});
      await settle(unknown);
      expect(unknown.read(myCampusHintProvider), isNull);

      final empty = containerWith(const <String, String>{});
      await settle(empty);
      expect(empty.read(myCampusHintProvider), isNull);
    });

    test('从没设过 → 自动采用数据中心的值（来源 = 数据中心）', () async {
      final container = containerWith({'所属校区': '麦庐园校区'});
      final store = container.read(myCampusStoreProvider);
      expect(store.campus, isNull);
      await settle(container, until: () => store.source != null);
      expect(store.campus, MyCampus.mailu);
      expect(store.source, MyCampusSource.center);
    });

    test('手动设过 → 只补空、不覆盖（手动优先）', () async {
      final container = containerWith({'所属校区': '麦庐园校区'});
      final store = container.read(myCampusStoreProvider);
      await store.save(MyCampus.jiaoqiao);
      await settle(container);
      expect(store.campus, MyCampus.jiaoqiao);
      expect(store.source, MyCampusSource.manual);
    });

    test('数据中心取不到 → 什么都不做（设置页照旧让用户手选）', () async {
      final container = containerWith(const <String, String>{});
      final store = container.read(myCampusStoreProvider);
      await settle(container);
      expect(store.campus, isNull);
      expect(store.source, isNull);
    });

    test('存档里已有值也不会被补空冲掉（先落盘再补空）', () async {
      final first = MyCampusStore();
      await first.save(MyCampus.fenglin); // 老用户：手选过枫林园
      final second = MyCampusStore(); // 重开一次 = 下一次启动
      await second.fillIfEmpty(MyCampus.mailu);
      expect(second.campus, MyCampus.fenglin);
      expect(second.source, MyCampusSource.manual);
    });

    test('fillIfEmpty(null) 是空操作；用户清除后可以再补', () async {
      final store = MyCampusStore();
      await store.fillIfEmpty(null);
      expect(store.campus, isNull);

      await store.fillIfEmpty(MyCampus.fenglin);
      expect(store.campus, MyCampus.fenglin);
      expect(store.source, MyCampusSource.center);

      await store.save(null); // 设置页「不设置」
      expect(store.campus, isNull);
      expect(store.source, isNull);

      await store.fillIfEmpty(MyCampus.mailu); // 再补空时又能写进来
      expect(store.campus, MyCampus.mailu);
    });
  });
}
