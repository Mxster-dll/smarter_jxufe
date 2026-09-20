/// 设置页「公共查询」节（默认教学楼）的界面守卫。
///
/// **不碰 Hive**：`publicQueryPrefsStoreProvider` 用假 store（只记内存），
/// 「我的校区」也用假 store —— 因此本文件里没有任何真实磁盘 I/O，
/// 不受 `testWidgets` 假异步区里 Hive 永不完成那个坑的影响。
///
/// 只渲染 `SettingsScreen(sections: [SettingsSection.publicQuery])`（过滤档），
/// 免得整页长列表把目标卡片留在视口之外没被 build。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/providers/public_query_providers.dart';
import 'package:smarter_jxufe/features/ims/public_query/data/public_query_prefs.dart';
import 'package:smarter_jxufe/features/ims/public_query/domain/public_query.dart';
import 'package:smarter_jxufe/design/settings_section.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';

/// 内存版偏好 store：只在内存里存/读默认教学楼，不走 Hive。
class _MemoryPrefsStore extends PublicQueryPrefsStore {
  PublicQueryBuilding? _building;

  /// 记录写入次数（守卫「同值不重复写」）。
  int saves = 0;

  @override
  PublicQueryBuilding? get defaultBuilding => _building;

  @override
  Future<void> ensureLoaded() async {}

  @override
  Future<void> saveBuilding(PublicQueryBuilding? next) async {
    _building = next;
    saves++;
    notifyListeners();
  }
}

/// 假的「我的校区」store（预填校区用）。
class _FakeCampusStore extends MyCampusStore {
  _FakeCampusStore(this._value);

  final MyCampus? _value;

  @override
  MyCampus? get campus => _value;
}

const _campuses = <PublicQueryOption>[
  PublicQueryOption(code: '1', name: '蛟桥园校区'),
  PublicQueryOption(code: '3', name: '麦庐园校区'),
];

const _buildings = <PublicQueryOption>[
  PublicQueryOption(code: '32', name: '北区综合楼'),
  PublicQueryOption(code: '35', name: '白云楼'),
];

Future<void> _pump(
  WidgetTester tester, {
  required _MemoryPrefsStore store,
  PublicQueryBuilding? initial,
}) async {
  store._building = initial;
  tester.view.physicalSize = const Size(1100, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        publicQueryPrefsStoreProvider.overrideWith((ref) => store),
        myCampusStoreProvider.overrideWith(
          (ref) => _FakeCampusStore(MyCampus.mailu),
        ),
        publicQueryCampusesProvider.overrideWith((ref) async => _campuses),
        publicQueryBuildingsProvider.overrideWith(
          (ref, campusCode) async => _buildings,
        ),
      ],
      child: const MaterialApp(
        home: SettingsScreen(sections: [SettingsSection.publicQuery]),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('未设置时显示「未设置」；整卡可点', (tester) async {
    final store = _MemoryPrefsStore();
    await _pump(tester, store: store);
    expect(find.text('公共查询'), findsWidgets); // AppBar 标题 + 节标题
    expect(find.byKey(const Key('settingsDefaultBuilding')), findsOneWidget);
    expect(find.text('未设置'), findsOneWidget);
    expect(find.text('默认教学楼'), findsOneWidget);
  });

  testWidgets('点开弹层 → 选校区 → 选楼房 → 保存（不碰 Hive）', (tester) async {
    final store = _MemoryPrefsStore();
    await _pump(tester, store: store);

    await tester.tap(find.byKey(const Key('settingsDefaultBuilding')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settingsBuildingCampusPicker')), findsOneWidget);
    expect(find.byKey(const Key('settingsBuildingPicker')), findsOneWidget);
    // 楼房还没选 → 保存禁用。
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('settingsBuildingSave')))
          .onPressed,
      isNull,
    );

    // 选校区（预选的是「我的校区」= 麦庐园校区，所以先改成蛟桥园再改回来也行；
    // 这里直接确认它已经预选好，然后选楼房）。
    expect(find.text('麦庐园校区'), findsWidgets);
    await tester.tap(find.byKey(const Key('settingsBuildingPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('白云楼').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settingsBuildingSave')));
    await tester.pumpAndSettle();

    expect(store.saves, 1);
    expect(store.defaultBuilding?.campusCode, '3');
    expect(store.defaultBuilding?.campusName, '麦庐园校区');
    expect(store.defaultBuilding?.buildingCode, '35');
    expect(store.defaultBuilding?.buildingName, '白云楼');
    // 卡片即时更新（store 是 ChangeNotifier）。
    expect(find.text('麦庐园校区 · 白云楼'), findsOneWidget);
    expect(find.text('未设置'), findsNothing);
  });

  testWidgets('已设置时两级下拉原样回填，清除后回「未设置」', (tester) async {
    final store = _MemoryPrefsStore();
    await _pump(
      tester,
      store: store,
      initial: const PublicQueryBuilding(
        campusCode: '3',
        campusName: '麦庐园校区',
        buildingCode: '35',
        buildingName: '白云楼',
      ),
    );
    expect(find.text('麦庐园校区 · 白云楼'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settingsDefaultBuilding')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('settingsBuildingSave')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('settingsBuildingClear')));
    await tester.pumpAndSettle();
    expect(store.defaultBuilding, isNull);
    expect(find.text('未设置'), findsOneWidget);
  });

  group('源码守卫', () {
    final section = File('lib/design/settings_section.dart').readAsStringSync();
    final screen = _setSrc();

    test('枚举顺序：publicQuery 紧跟在 imsSession 之后、cloudSync 之前', () {
      final iIms = section.indexOf('imsSession(');
      final iPublic = section.indexOf('publicQuery(');
      final iCloud = section.indexOf('cloudSync(');
      expect(iIms, greaterThan(-1));
      expect(iPublic, greaterThan(iIms));
      expect(iCloud, greaterThan(iPublic));
    });

    test('设置页确实渲染这一节，且卡片挂在 prefs store 上', () {
      expect(screen.contains('SettingsSection.publicQuery'), isTrue);
      expect(screen.contains('SettingsPublicQueryCard()'), isTrue);
      expect(screen.contains("Key('settingsDefaultBuilding')"), isTrue);
      expect(screen.contains("Key('settingsBuildingPicker')"), isTrue);
      expect(screen.contains('publicQueryPrefsStoreProvider'), isTrue);
      expect(screen.contains('saveBuilding('), isTrue);
    });

    test('两个公共查询页都声明了这一节（齿轮只显示本节）', () {
      for (final path in const [
        'lib/features/ims/public_query/presentation/public_query_screen.dart',
        'lib/features/ims/public_query/presentation/classroom_free_screen.dart',
        'lib/features/ims/public_query/presentation/free_time_screen.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(
          src.contains('SettingsSection.publicQuery'),
          isTrue,
          reason: '$path 应声明公共查询节',
        );
      }
    });
  });
}

/// 设置页源码（2026-09-20 架构审查 ⑥：14 个分节卡已外提到 `widgets/settings_cards.dart`）。
///
/// 守卫改读**两文件并集** —— 原意不变（这些形态必须存在于设置页这一族里），
/// 只是不再假设它们住在同一个文件里。
String _setSrc() => const [
  'lib/features/settings/presentation/settings_screen.dart',
  'lib/features/settings/presentation/widgets/settings_cards.dart',
].map((p) => File(p).readAsStringSync()).join('\n');
