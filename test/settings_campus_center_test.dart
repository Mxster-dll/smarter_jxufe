/// 设置页「校区」卡 · 值的来源标注。
///
/// 用户 2026-09-20 原话：「现在『设置』页的校区设置，改成直接用数据中心的数据，
/// 如果获取失败，再手动设置」。裁定口径 = **手动优先、数据中心只补空**
/// → 卡片必须把「这个值是谁给的」说清楚，否则用户看到一个自己没选过的校区会以为出错：
/// - 数据中心补的 → 「麦庐园校区 · 数据中心」；
/// - 手选的 → 「蛟桥园校区 · 手动设置」；
/// - 手选与数据中心不一致 → 只**附注**一句（不偷偷改掉用户的选择）；
/// - 两边都没有 → 「未设置 · 点击选择」（这就是「获取失败再手动设置」那条路）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/features/campus_address/data/my_campus_prefs.dart';
import 'package:smarter_jxufe/features/campus_address/domain/my_campus.dart';
import 'package:smarter_jxufe/features/data_center/data/providers/data_center_providers.dart';
import 'package:smarter_jxufe/design/settings_section.dart';
import 'package:smarter_jxufe/features/settings/presentation/settings_screen.dart';

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('settings_campus_test');
    Hive.init(dir.path);
    await Hive.openBox<String>(myCampusPrefsBoxName);
  });

  setUp(() async {
    await Hive.box<String>(myCampusPrefsBoxName).clear();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  /// 只渲染「校区」一节；[mine] 按 [source] 的方式写进 store（模拟手选 / 数据中心补空）。
  ///
  /// ⚠ 写盘（`save` / `fillIfEmpty`）必须包在 `tester.runAsync` 里：`testWidgets` 的
  /// 假异步区推不动真 I/O，直接 await 会静默挂死到 10 分钟超时（2026-09-20 实测）。
  Future<void> pumpCampus(
    WidgetTester tester, {
    MyCampus? mine,
    MyCampusSource? source,
    MyCampus? center,
  }) async {
    final store = MyCampusStore();
    await tester.runAsync(() async {
      if (mine == null) {
        // 就算不预置值也要在真异步区里载入完：`ensureLoaded()` 里那次 `Hive.openBox`
        // 在 `testWidgets` 的假异步区推不动 → 会在 pump 期间永远停在 null，
        // 界面显示成「正在采用数据中心的值…」（2026-09-20 实测踩过）。
        await store.ensureLoaded();
      } else if (source == MyCampusSource.center) {
        await store.fillIfEmpty(mine);
      } else {
        await store.save(mine);
      }
    });
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myCampusStoreProvider.overrideWith((ref) => store),
          dzjBasicInfoProvider.overrideWith(
            (ref) async => center == null
                ? const <String, String>{}
                : <String, String>{'所属校区': center.label},
          ),
        ],
        child: const MaterialApp(
          home: SettingsScreen(sections: [SettingsSection.campus]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('两边都没有 → 「未设置 · 点击选择」（手动设置兜底）', (tester) async {
    await pumpCampus(tester);
    expect(find.text('未设置 · 点击选择'), findsOneWidget);
  });

  testWidgets('数据中心补空 → 校区名后面标「数据中心」', (tester) async {
    await pumpCampus(
      tester,
      mine: MyCampus.mailu,
      source: MyCampusSource.center,
      center: MyCampus.mailu,
    );
    expect(find.text('麦庐园校区 · 数据中心'), findsOneWidget);
  });

  testWidgets('手选过 → 标「手动设置」', (tester) async {
    await pumpCampus(
      tester,
      mine: MyCampus.jiaoqiao,
      source: MyCampusSource.manual,
      center: MyCampus.jiaoqiao,
    );
    expect(find.text('蛟桥园校区 · 手动设置'), findsOneWidget);
  });

  testWidgets('手选与数据中心不一致 → 附注一句，不偷偷改掉手选值', (tester) async {
    await pumpCampus(
      tester,
      mine: MyCampus.jiaoqiao,
      source: MyCampusSource.manual,
      center: MyCampus.mailu,
    );
    expect(
      find.text('蛟桥园校区 · 手动设置（数据中心显示：麦庐园校区）'),
      findsOneWidget,
    );
  });

  testWidgets('老存档没记来源 → 照样标「手动设置」（那时候只可能是手选的）', (tester) async {
    // 老版本只写了 `campus` 一个键，没有 `campusSource`（写盘同样要 runAsync）。
    await tester.runAsync(() async {
      await Hive.box<String>(
        myCampusPrefsBoxName,
      ).put('campus', MyCampus.fenglin.name);
    });
    await pumpCampus(tester, center: MyCampus.fenglin);
    expect(find.text('枫林园校区 · 手动设置'), findsOneWidget);
  });
}
