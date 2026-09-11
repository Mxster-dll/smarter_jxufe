import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/campus_address/domain/campus_address.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/campus_address/presentation/campus_map_screen.dart';

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
}
