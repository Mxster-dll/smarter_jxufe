// 侧栏视图里「点一下侧栏条目」时，右栏那张卡片**逐帧**都不许动
// （用户 2026-10-09 二十一轮：「点击切换页面，会导致整个右侧内容卡片出现位置的水平闪动」）。
//
// ⚠ 与 `home_pane_switch_card_test.dart` 的区别：那一条用的是**复刻的装配**；
// 这一条 pump **真实的 `HomeScreen`**（真 `_buildSidebarBody` + 真侧栏点选），
// 所以在真实代码路径上有回归时它会红。
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:smarter_jxufe/core/navigation/service_nav.dart';
import 'package:smarter_jxufe/design/card_frame.dart';
import 'package:smarter_jxufe/features/home/data/home_grid_prefs.dart';
import 'package:smarter_jxufe/features/home/data/home_layout_prefs.dart';
import 'package:smarter_jxufe/features/home/domain/home_card_style.dart';
import 'package:smarter_jxufe/features/home/domain/home_layout.dart';
import 'package:smarter_jxufe/features/home/presentation/home_screen.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('tmp_pane_frame');
    Hive.init(dir.path);
    await Hive.openBox<String>(homePrefsBoxName);
    await Hive.openBox<String>(homeGridPrefsBoxName);
  });
  tearDownAll(() {
    unawaited(Hive.close());
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(clearServiceScreens);
  tearDown(clearServiceScreens);

  testWidgets('★ 真实 HomeScreen：点侧栏条目，内容卡逐帧不动', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = HomeLayoutStore();
    await tester.runAsync(() async {
      await store.ensureLoaded();
      await store.save(HomeLayout.sidebar); // 侧栏视图
      // ⚠ **必须把卡片形态打开**：默认是 `none`（= 逐像素的改造前），那种档位下
      // 根本没有 `CardFrame`，「卡片闪不闪」无从谈起（这条一度白跑过）。
      await store.saveCardStyle(HomeCardStyle.both);
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [homeLayoutStoreProvider.overrideWith((ref) => store)],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    // 右栏那张卡：`CardFrame` 的容器。侧栏也有一张 → 取**最后一个**（右栏在 Row 末尾）。
    Rect paneCardRect() =>
        tester.getRect(find.byKey(cardFrameContainerKey).last);
    // 画面里必须有**两张**区域卡（侧栏 + 内容区），否则这条测试等于没测
    // （`cardStyle = none` 时 `CardFrame` 仍会建出来，只是半径 0 / 无描边）。
    expect(
      find.byKey(cardFrameContainerKey),
      findsNWidgets(2),
      reason: '侧栏 + 内容区各一张卡（cardStyle = both）',
    );
    final before = paneCardRect();
    expect(before.width, greaterThan(0));
    // 证明"卡片真的开着的"：`cardStyle = both` + 半径 8 → 容器上应当有圆角与非空阴影。
    // （不然这条测试可能在一个"根本没有卡片"的画面上空跑一遍。）
    final paneCardDecor =
        tester
                .widget<Container>(find.byKey(cardFrameContainerKey).last)
                .decoration!
            as BoxDecoration;
    expect(
      paneCardDecor.borderRadius,
      BorderRadius.circular(8),
      reason: '内容卡应当是圆角 8 的卡片形态',
    );
    expect(paneCardDecor.boxShadow, isNotEmpty, reason: '卡片要阴影');

    // 点侧栏里任意一个服务条目（真点，走 `_select` → setState → AnimatedSwitcher）。
    final rows = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('homeSidebarItem-'),
    );
    expect(rows, findsWidgets, reason: '侧栏应当有服务条目');
    final row = rows.first;
    await tester.ensureVisible(row);
    // ⚠ 这里**不能** `pumpAndSettle`：概览面板上有活的加载指示器，永远settle不下来
    // （实测「pumpAndSettle timed out」）。固定帧数推进即可。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    final rowCenter = tester.getCenter(row);

    final gesture = await tester.startGesture(rowCenter);
    await gesture.up();

    // 逐帧走完换页动画（`appPaneSwitchDuration` ≈ 220ms），每一帧都量卡片矩形。
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        paneCardRect(),
        before,
        reason: '第 ${(i + 1) * 16}ms：右栏卡片矩形变了 —— 卡片跟着换页动画动了',
      );
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(paneCardRect(), before, reason: '换完之后卡片矩形也不许变');
    expect(tester.takeException(), isNull);
  });
}
